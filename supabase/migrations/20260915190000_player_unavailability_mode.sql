begin;

-- ---------------------------------------------------------------------------
-- Mode Indisponibilité
--
-- Un joueur peut déclarer lui-même une période pendant laquelle il n'est pas
-- disponible, avec la raison de son choix. Pendant cette période il sort de
-- l'effectif convocable : il est posé « absent » sur les matchs à venir qui
-- tombent dedans, il ne peut plus répondre à la disponibilité de ces matchs,
-- et il ne reçoit plus les notifications qui découlent de l'effectif
-- (ouverture des disponibilités, relances, convocation, composition).
--
-- La période reste modifiable et annulable tant qu'elle n'est pas terminée.
-- Annuler rend simplement les matchs concernés à leur état « sans réponse »,
-- sauf ceux où le joueur s'était déjà déclaré absent de lui-même : cette
-- réponse-là lui appartient et n'est jamais écrasée.
--
-- Les administrateurs déclarent la leur comme tout le monde et disposent en
-- plus d'une lecture de l'ensemble des indisponibilités du club. Personne ne
-- crée, ne modifie ni n'annule l'indisponibilité d'un autre.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. La période déclarée
-- ---------------------------------------------------------------------------
--
-- Les bornes sont des dates, incluses toutes les deux, lues en Europe/Paris :
-- « je ne suis pas là du 12 au 25 » est la façon dont on en parle, et un match
-- appartient à la période dès que sa date de coup d'envoi y tombe.

create table if not exists public.player_unavailabilities (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_unavailabilities_period_ordered
    check (ends_on >= starts_on),
  constraint player_unavailabilities_period_bounded
    check (ends_on <= starts_on + 366),
  constraint player_unavailabilities_reason_filled
    check (char_length(btrim(reason)) between 1 and 200)
);

create index if not exists player_unavailabilities_profile_period_idx
  on public.player_unavailabilities (profile_id, starts_on, ends_on);

create index if not exists player_unavailabilities_ends_on_idx
  on public.player_unavailabilities (ends_on desc);

alter table public.player_unavailabilities enable row level security;

-- Aucune écriture ni lecture directe : tout passe par les RPC ci-dessous, qui
-- seules savent qui a le droit de voir quoi.
drop policy if exists "deny_client_access" on public.player_unavailabilities;
create policy "deny_client_access"
  on public.player_unavailabilities
  as restrictive to authenticated, anon
  using (false)
  with check (false);

drop policy if exists "active_authenticated_profile_only"
  on public.player_unavailabilities;
create policy "active_authenticated_profile_only"
  on public.player_unavailabilities
  as restrictive to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

revoke all on table public.player_unavailabilities from public;
revoke all on table public.player_unavailabilities from anon;
revoke all on table public.player_unavailabilities from authenticated;
grant all on table public.player_unavailabilities to service_role;

comment on table public.player_unavailabilities is
  'Periods declared by a player during which they are not part of the convocable squad.';

-- ---------------------------------------------------------------------------
-- 2. Marqueur sur la participation au match
-- ---------------------------------------------------------------------------
--
-- Sans lui, annuler une période ne saurait pas distinguer l'absence posée par
-- l'indisponibilité de celle que le joueur a écrite lui-même. Seule la
-- première est reprise quand la période disparaît.

alter table public.match_sport_participants
  add column if not exists availability_forced_by_unavailability boolean
    not null default false;

comment on column public.match_sport_participants.availability_forced_by_unavailability is
  'True when the absence was posted by a declared unavailability period, not by the player or an administrator.';

-- ---------------------------------------------------------------------------
-- 3. Lecture : ce match tombe-t-il dans une indisponibilité déclarée ?
-- ---------------------------------------------------------------------------

create or replace function private.player_unavailability_reason_at(
  p_profile_id uuid,
  p_kickoff_at timestamptz
)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select unavailability.reason
  from public.player_unavailabilities unavailability
  where p_profile_id is not null
    and p_kickoff_at is not null
    and unavailability.profile_id = p_profile_id
    and (p_kickoff_at at time zone 'Europe/Paris')::date
        between unavailability.starts_on and unavailability.ends_on
  order by unavailability.starts_on
  limit 1;
$function$;

revoke all on function private.player_unavailability_reason_at(uuid, timestamptz)
  from public, anon, authenticated;

comment on function private.player_unavailability_reason_at(uuid, timestamptz) is
  'Returns the reason of the declared unavailability covering a kickoff, or null.';

create or replace function private.is_player_unavailable_at(
  p_profile_id uuid,
  p_kickoff_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.player_unavailability_reason_at(p_profile_id, p_kickoff_at)
    is not null;
$function$;

revoke all on function private.is_player_unavailable_at(uuid, timestamptz)
  from public, anon, authenticated;

comment on function private.is_player_unavailable_at(uuid, timestamptz) is
  'True when a declared unavailability period covers the kickoff of a match.';

-- ---------------------------------------------------------------------------
-- 4. Application aux matchs à venir
-- ---------------------------------------------------------------------------
--
-- Une seule fonction réconcilie tous les matchs à venir d'un joueur avec la
-- totalité de ses périodes courantes. Elle est donc idempotente et sert aussi
-- bien à la création, à la modification qu'à l'annulation d'une période.
--
-- Deux règles gouvernent l'écriture :
--
--   * on ne touche jamais une absence que le joueur a posée lui-même ; elle
--     lui appartient, et l'effet recherché est déjà obtenu ;
--   * un joueur convoqué qui devient indisponible se retire exactement comme
--     s'il s'était déclaré absent, liste d'attente comprise : le suivant
--     monte, et le tour n'est pas consommé avant l'heure limite.
--
-- Les matchs passés ou déjà commencés ne sont jamais touchés.

create or replace function private.sync_player_unavailability(p_profile_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_changed integer := 0;
begin
  if p_profile_id is null then
    return 0;
  end if;

  for v_row in
    select
      participant.id as participant_id,
      participant.match_id,
      participant.availability_status,
      participant.availability_forced_by_unavailability as forced,
      participant.availability_comment_private,
      participant.convocation_status,
      participant.is_eligible,
      player.is_coach,
      workflow.convocation_state,
      private.player_unavailability_reason_at(p_profile_id, match.kickoff_at)
        as reason
    from public.match_sport_participants participant
    join public.season_players player
      on player.id = participant.season_player_id
    join public.matches match on match.id = participant.match_id
    join public.match_sport_workflows workflow
      on workflow.match_id = participant.match_id
    where player.profile_id = p_profile_id
      and match.status = 'a_venir'
      and match.kickoff_at is not null
      and match.kickoff_at > now()
    order by match.kickoff_at
  loop
    if v_row.reason is not null then
      -- Le joueur est couvert par une période. Une absence déjà posée, par
      -- lui ou par un administrateur, reste telle quelle.
      continue when v_row.availability_status = 'absent';

      update public.match_sport_participants participant
      set availability_status = 'absent',
          availability_comment_private = left(btrim(v_row.reason), 500),
          availability_forced_by_unavailability = true,
          availability_updated_at = now(),
          availability_updated_by = p_profile_id,
          updated_at = now()
      where participant.id = v_row.participant_id;

      insert into public.match_sport_participant_events (
        participant_id, match_id, event_type, old_value, new_value,
        actor_profile_id, actor_kind
      ) values (
        v_row.participant_id, v_row.match_id, 'availability_changed',
        jsonb_build_object(
          'status', v_row.availability_status,
          'private_comment', v_row.availability_comment_private
        ),
        jsonb_build_object(
          'status', 'absent',
          'private_comment', left(btrim(v_row.reason), 500),
          'source', 'player_unavailability'
        ),
        p_profile_id, 'player'
      );

      if v_row.is_eligible
         and not v_row.is_coach
         and v_row.convocation_state = 'published'
         and v_row.convocation_status = 'convoked' then
        perform private.handle_convoked_withdrawal(
          v_row.match_id, v_row.participant_id, p_profile_id, 'player'
        );
      else
        perform private.recompute_match_convocations_internal(
          v_row.match_id, false
        );
      end if;

      v_changed := v_changed + 1;

    elsif v_row.forced then
      -- La période ne couvre plus ce match : on rend la main au joueur.
      update public.match_sport_participants participant
      set availability_status = 'no_response',
          availability_comment_private = null,
          availability_forced_by_unavailability = false,
          availability_updated_at = now(),
          availability_updated_by = p_profile_id,
          updated_at = now()
      where participant.id = v_row.participant_id;

      insert into public.match_sport_participant_events (
        participant_id, match_id, event_type, old_value, new_value,
        actor_profile_id, actor_kind
      ) values (
        v_row.participant_id, v_row.match_id, 'availability_changed',
        jsonb_build_object(
          'status', v_row.availability_status,
          'private_comment', v_row.availability_comment_private
        ),
        jsonb_build_object(
          'status', 'no_response',
          'private_comment', null,
          'source', 'player_unavailability_cancelled'
        ),
        p_profile_id, 'player'
      );

      perform private.recompute_match_convocations_internal(
        v_row.match_id, false
      );

      v_changed := v_changed + 1;
    end if;
  end loop;

  return v_changed;
end;
$function$;

revoke all on function private.sync_player_unavailability(uuid)
  from public, anon, authenticated;

comment on function private.sync_player_unavailability(uuid) is
  'Reconciles the upcoming matches of one profile with their declared unavailability periods.';

-- ---------------------------------------------------------------------------
-- 5. Deux rattrapages automatiques
-- ---------------------------------------------------------------------------
--
-- Un match configuré après coup, ou déplacé à une autre date, ne doit pas
-- ramener dans l'effectif un joueur qui a déjà dit qu'il ne serait pas là.

create or replace function private.apply_unavailability_on_new_participant()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_reason text;
begin
  if new.season_player_id is null then
    return new;
  end if;

  select private.player_unavailability_reason_at(player.profile_id, match.kickoff_at)
  into v_reason
  from public.season_players player
  join public.matches match on match.id = new.match_id
  where player.id = new.season_player_id
    and match.status = 'a_venir'
    and match.kickoff_at > now();

  if v_reason is null then
    return new;
  end if;

  -- La convocation n'existe pas encore à cet instant : poser la réponse
  -- suffit, le calcul de l'effectif la lira quand il passera.
  update public.match_sport_participants participant
  set availability_status = 'absent',
      availability_comment_private = left(btrim(v_reason), 500),
      availability_forced_by_unavailability = true,
      availability_updated_at = now(),
      updated_at = now()
  where participant.id = new.id
    and participant.availability_status = 'no_response';

  return new;
end;
$function$;

revoke all on function private.apply_unavailability_on_new_participant()
  from public, anon, authenticated;

comment on function private.apply_unavailability_on_new_participant() is
  'Posts the declared absence on a participant row created after the period was declared.';

drop trigger if exists trg_apply_unavailability_on_new_participant
  on public.match_sport_participants;

create trigger trg_apply_unavailability_on_new_participant
after insert on public.match_sport_participants
for each row
execute function private.apply_unavailability_on_new_participant();

create or replace function private.resync_unavailability_on_reschedule()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_id uuid;
begin
  if new.kickoff_at is not distinct from old.kickoff_at then
    return new;
  end if;

  for v_profile_id in
    select distinct player.profile_id
    from public.match_sport_participants participant
    join public.season_players player
      on player.id = participant.season_player_id
    where participant.match_id = new.id
      and player.profile_id is not null
      and exists (
        select 1
        from public.player_unavailabilities unavailability
        where unavailability.profile_id = player.profile_id
      )
  loop
    perform private.sync_player_unavailability(v_profile_id);
  end loop;

  return new;
end;
$function$;

revoke all on function private.resync_unavailability_on_reschedule()
  from public, anon, authenticated;

comment on function private.resync_unavailability_on_reschedule() is
  'Re-applies declared unavailabilities after a match kickoff moved to another date.';

drop trigger if exists trg_resync_unavailability_on_reschedule
  on public.matches;

-- Volontairement sans clause `of kickoff_at` : `UPDATE OF` réagit aux colonnes
-- citées dans l'ordre SQL, pas à celles qui changent réellement. Or le coup
-- d'envoi est recalculé par un trigger BEFORE à partir de la date et de
-- l'heure ; une mise à jour qui ne cite que la date ne réveillerait donc
-- jamais celui-ci. La comparaison faite dans la fonction suffit.
--
-- L'ordre d'exécution compte : `trg_notification_match_changes` remet les
-- disponibilités à « sans réponse » quand la date bouge, et PostgreSQL exécute
-- les triggers AFTER par ordre alphabétique de nom. `trg_n…` passe donc avant
-- `trg_r…`, et l'indisponibilité est réappliquée après cette remise à zéro.
create trigger trg_resync_unavailability_on_reschedule
after update on public.matches
for each row
execute function private.resync_unavailability_on_reschedule();

-- ---------------------------------------------------------------------------
-- 6. Points d'entrée du joueur
-- ---------------------------------------------------------------------------

create or replace function public.get_my_unavailabilities()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_today date := (now() at time zone 'Europe/Paris')::date;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', unavailability.id,
        'starts_on', unavailability.starts_on,
        'ends_on', unavailability.ends_on,
        'reason', unavailability.reason,
        'created_at', unavailability.created_at,
        'updated_at', unavailability.updated_at,
        'is_past', unavailability.ends_on < v_today,
        'is_current',
          v_today between unavailability.starts_on and unavailability.ends_on
      )
      order by unavailability.starts_on desc
    )
    from public.player_unavailabilities unavailability
    where unavailability.profile_id = v_actor
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_my_unavailabilities() from public, anon;
grant execute on function public.get_my_unavailabilities()
  to authenticated, service_role;

comment on function public.get_my_unavailabilities() is
  'Returns the unavailability periods declared by the current profile.';

-- Crée la période quand `p_id` est nul, la remplace sinon. Une période déjà
-- terminée n'est plus modifiable : elle appartient à l'historique du club.
create or replace function public.set_my_unavailability(
  p_id uuid,
  p_starts_on date,
  p_ends_on date,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_reason text := nullif(btrim(p_reason), '');
  v_id uuid;
  v_previous_end date;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if p_starts_on is null or p_ends_on is null then
    raise exception 'Les deux dates de la période sont obligatoires.'
      using errcode = '22023';
  end if;
  if p_ends_on < p_starts_on then
    raise exception 'La fin de la période ne peut pas précéder son début.'
      using errcode = '22023';
  end if;
  if p_ends_on > p_starts_on + 366 then
    raise exception 'Une indisponibilité ne peut pas dépasser un an.'
      using errcode = '22023';
  end if;
  if p_ends_on < v_today then
    raise exception 'Une indisponibilité déjà terminée ne peut pas être déclarée.'
      using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'La raison est obligatoire.' using errcode = '22023';
  end if;
  if char_length(v_reason) > 200 then
    raise exception 'La raison ne peut pas dépasser 200 caractères.'
      using errcode = '22023';
  end if;

  if p_id is not null then
    select unavailability.ends_on
    into v_previous_end
    from public.player_unavailabilities unavailability
    where unavailability.id = p_id
      and unavailability.profile_id = v_actor
    for update;

    if not found then
      raise exception 'Indisponibilité introuvable.' using errcode = 'P0002';
    end if;
    if v_previous_end < v_today then
      raise exception 'Une indisponibilité terminée ne peut plus être modifiée.'
        using errcode = '22023';
    end if;
  end if;

  if exists (
    select 1
    from public.player_unavailabilities unavailability
    where unavailability.profile_id = v_actor
      and unavailability.id is distinct from p_id
      and daterange(unavailability.starts_on, unavailability.ends_on, '[]')
          && daterange(p_starts_on, p_ends_on, '[]')
  ) then
    raise exception 'Cette période en chevauche une autre déjà déclarée.'
      using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.player_unavailabilities (
      profile_id, starts_on, ends_on, reason
    ) values (
      v_actor, p_starts_on, p_ends_on, v_reason
    )
    returning id into v_id;
  else
    update public.player_unavailabilities unavailability
    set starts_on = p_starts_on,
        ends_on = p_ends_on,
        reason = v_reason,
        updated_at = now()
    where unavailability.id = p_id
      and unavailability.profile_id = v_actor
    returning unavailability.id into v_id;
  end if;

  return jsonb_build_object(
    'id', v_id,
    'synchronized_matches', private.sync_player_unavailability(v_actor)
  );
end;
$function$;

revoke all on function public.set_my_unavailability(uuid, date, date, text)
  from public, anon;
grant execute on function public.set_my_unavailability(uuid, date, date, text)
  to authenticated, service_role;

comment on function public.set_my_unavailability(uuid, date, date, text) is
  'Creates or replaces one unavailability period of the current profile.';

create or replace function public.cancel_my_unavailability(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_ends_on date;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'Indisponibilité introuvable.' using errcode = 'P0002';
  end if;

  select unavailability.ends_on
  into v_ends_on
  from public.player_unavailabilities unavailability
  where unavailability.id = p_id
    and unavailability.profile_id = v_actor
  for update;

  if not found then
    raise exception 'Indisponibilité introuvable.' using errcode = 'P0002';
  end if;
  if v_ends_on < v_today then
    raise exception 'Une indisponibilité terminée ne peut plus être annulée.'
      using errcode = '22023';
  end if;

  delete from public.player_unavailabilities unavailability
  where unavailability.id = p_id
    and unavailability.profile_id = v_actor;

  return jsonb_build_object(
    'id', p_id,
    'synchronized_matches', private.sync_player_unavailability(v_actor)
  );
end;
$function$;

revoke all on function public.cancel_my_unavailability(uuid) from public, anon;
grant execute on function public.cancel_my_unavailability(uuid)
  to authenticated, service_role;

comment on function public.cancel_my_unavailability(uuid) is
  'Cancels one unavailability period of the current profile and restores their upcoming matches.';

-- ---------------------------------------------------------------------------
-- 7. Lecture d'ensemble, réservée aux administrateurs
-- ---------------------------------------------------------------------------
--
-- La raison saisie par un joueur ne sort jamais de ce point d'entrée : elle
-- n'apparaît ni dans le tableau des disponibilités, ni pour les autres
-- joueurs.

create or replace function public.admin_get_player_unavailabilities()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', unavailability.id,
        'profile_id', unavailability.profile_id,
        'first_name', profile.first_name,
        'last_name', profile.last_name,
        'display_name', coalesce(
          nullif(btrim(profile.surnom), ''),
          nullif(btrim(profile.first_name), ''),
          btrim(profile.last_name)
        ),
        'photo_url', profile.photo_url,
        'starts_on', unavailability.starts_on,
        'ends_on', unavailability.ends_on,
        'reason', unavailability.reason,
        'created_at', unavailability.created_at,
        'updated_at', unavailability.updated_at,
        'is_past', unavailability.ends_on < v_today,
        'is_current',
          v_today between unavailability.starts_on and unavailability.ends_on
      )
      order by unavailability.starts_on desc, unavailability.created_at desc
    )
    from public.player_unavailabilities unavailability
    join public.profiles profile on profile.id = unavailability.profile_id
    where unavailability.ends_on >= v_today - 365
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.admin_get_player_unavailabilities()
  from public, anon;
grant execute on function public.admin_get_player_unavailabilities()
  to authenticated, service_role;

comment on function public.admin_get_player_unavailabilities() is
  'Returns every declared unavailability of the club for administrators, with its author and reason.';

-- ---------------------------------------------------------------------------
-- 8. Ce que l'indisponibilité change dans le cycle du match
-- ---------------------------------------------------------------------------
--
-- La réponse de disponibilité est fermée pendant la période, des deux côtés :
-- le joueur ne peut plus se remettre disponible sans annuler sa période, et un
-- administrateur ne peut pas l'y remettre à sa place. Il n'existe donc qu'une
-- seule source de vérité, celle que le joueur tient lui-même.

create or replace function private.get_my_match_availability(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', participant.match_id,
    'participant_id', participant.id,
    'season_player_id', participant.season_player_id,
    'is_eligible', participant.is_eligible,
    'is_coach', player.is_coach,
    'availability_status', participant.availability_status,
    'private_comment', participant.availability_comment_private,
    'availability_updated_at', participant.availability_updated_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'kickoff_at', match.kickoff_at,
    'unavailability_reason', unavailability.reason,
    'unavailability_starts_on', unavailability.starts_on,
    'unavailability_ends_on', unavailability.ends_on,
    'can_respond', (participant.is_eligible or player.is_coach)
      and now() >= workflow.availability_opens_at
      and now() < match.kickoff_at
      and workflow.availability_state <> 'closed'
      and unavailability.id is null,
    'composition_state', workflow.composition_state,
    'convocation_state', workflow.convocation_state,
    'convocation_status', case
      when workflow.convocation_state = 'published'
        and (participant.is_eligible or player.is_coach)
        then participant.convocation_status::text
      else null
    end
  ) into v_result
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  left join lateral (
    select period.id, period.reason, period.starts_on, period.ends_on
    from public.player_unavailabilities period
    where period.profile_id = player.profile_id
      and (match.kickoff_at at time zone 'Europe/Paris')::date
          between period.starts_on and period.ends_on
    order by period.starts_on
    limit 1
  ) unavailability on true
  where participant.match_id = p_match_id
    and player.profile_id = v_actor;

  return v_result;
end;
$function$;

create or replace function private.set_my_match_availability(
  p_match_id uuid,
  p_status text,
  p_private_comment text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_is_eligible boolean;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_composition_state public.sport_composition_state;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
  v_is_coach boolean;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'absent') then
    raise exception 'Availability status must be available or absent' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status = 'available' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.is_eligible, player.is_coach,
    participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.composition_state,
    workflow.convocation_state, match.kickoff_at
  into v_participant_id, v_is_eligible, v_is_coach, v_old_status, v_old_comment,
    v_workflow_state,
    v_opens_at, v_composition_state, v_convocation_state, v_kickoff_at
  from public.match_sport_participants participant
  join public.season_players player on player.id = participant.season_player_id
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  where participant.match_id = p_match_id
    and (participant.is_eligible or player.is_coach)
    and player.profile_id = v_actor
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;
  if private.is_player_unavailable_at(v_actor, v_kickoff_at) then
    raise exception 'Ce match tombe dans une indisponibilité que tu as déclarée.'
      using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_forced_by_unavailability = false,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'player'
    );

    -- Le coach répond comme tout le monde, mais il n'occupe aucune place de
    -- la rotation : sa réponse le pose dans l'effectif ou l'en retire sans
    -- jamais faire monter ni redescendre un joueur de la liste d'attente.
    if v_is_coach then
      perform private.recompute_match_convocations_internal(p_match_id, false);
    elsif v_is_eligible then
      if v_convocation_state = 'published'
         and v_old_status = 'available'
         and v_new_status = 'absent' then
        v_promoted_player_id := private.handle_convoked_withdrawal(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      elsif v_convocation_state = 'published'
         and v_old_status = 'absent'
         and v_new_status = 'available' then
        v_promoted_player_id := private.restore_returning_convoked_player(
          p_match_id, v_participant_id, v_actor, 'player'
        );
      else
        perform private.recompute_match_convocations_internal(p_match_id, false);
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id,
    'composition_already_published',
      v_composition_state in ('published', 'updated', 'closed')
  );
end;
$function$;

create or replace function private.override_match_availability(
  p_match_id uuid,
  p_season_player_id uuid,
  p_status text,
  p_private_comment text default null::text,
  p_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_participant_id uuid;
  v_old_status public.sport_availability_status;
  v_old_comment text;
  v_new_status public.sport_availability_status;
  v_new_comment text := nullif(btrim(p_private_comment), '');
  v_reason text := nullif(btrim(p_reason), '');
  v_workflow_state public.sport_availability_state;
  v_opens_at timestamptz;
  v_kickoff_at timestamptz;
  v_convocation_state public.sport_convocation_state;
  v_changed boolean;
  v_promoted_player_id uuid;
  v_target_profile_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('no_response', 'available', 'absent') then
    raise exception 'Invalid availability override status' using errcode = '22023';
  end if;
  if v_reason is null then
    raise exception 'Override reason is required' using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'Override reason cannot exceed 500 characters' using errcode = '22023';
  end if;

  v_new_status := p_status::public.sport_availability_status;
  if v_new_status <> 'absent' then v_new_comment := null; end if;
  if v_new_comment is not null and char_length(v_new_comment) > 500 then
    raise exception 'Availability comment cannot exceed 500 characters' using errcode = '22023';
  end if;

  select participant.id, participant.availability_status,
    participant.availability_comment_private, workflow.availability_state,
    workflow.availability_opens_at, workflow.convocation_state, match.kickoff_at,
    player.profile_id
  into v_participant_id, v_old_status, v_old_comment, v_workflow_state,
    v_opens_at, v_convocation_state, v_kickoff_at, v_target_profile_id
  from public.match_sport_participants participant
  join public.match_sport_workflows workflow on workflow.match_id = participant.match_id
  join public.matches match on match.id = participant.match_id
  left join public.season_players player on player.id = participant.season_player_id
  where participant.match_id = p_match_id
    and participant.season_player_id = p_season_player_id
    and (
      participant.is_eligible
      or private.participant_is_coach(participant.season_player_id)
    )
  for update of participant, workflow;

  if not found then
    raise exception 'Eligible match participant not found' using errcode = 'P0002';
  end if;
  if now() < v_opens_at then
    raise exception 'Availability window is not open yet' using errcode = '22023';
  end if;
  if now() >= v_kickoff_at then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;
  -- L'indisponibilité appartient au joueur. La corriger à sa place ferait
  -- diverger l'effectif de ce qu'il a déclaré, et la prochaine relecture de
  -- sa période effacerait la correction sans prévenir.
  if private.is_player_unavailable_at(v_target_profile_id, v_kickoff_at) then
    raise exception 'Ce joueur a déclaré une indisponibilité sur cette période.'
      using errcode = '22023';
  end if;

  if v_workflow_state = 'pending' then
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, now()),
        updated_by = v_actor,
        updated_at = now()
    where workflow.match_id = p_match_id;
  elsif v_workflow_state <> 'open' then
    raise exception 'Availability window is closed' using errcode = '22023';
  end if;

  v_changed := v_old_status is distinct from v_new_status
    or v_old_comment is distinct from v_new_comment;

  if v_changed then
    update public.match_sport_participants participant
    set availability_status = v_new_status,
        availability_comment_private = v_new_comment,
        availability_forced_by_unavailability = false,
        availability_updated_at = now(),
        availability_updated_by = v_actor,
        updated_at = now()
    where participant.id = v_participant_id;

    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    ) values (
      v_participant_id, p_match_id, 'availability_changed',
      jsonb_build_object('status', v_old_status, 'private_comment', v_old_comment),
      jsonb_build_object('status', v_new_status, 'private_comment', v_new_comment),
      v_actor, 'staff'
    );

    -- Le coach n'occupe aucune place de la rotation : le faire entrer ou
    -- sortir de l'effectif ne promeut ni ne redescend personne.
    if private.participant_is_coach(p_season_player_id) then
      perform private.recompute_match_convocations_internal(p_match_id, false);
    elsif v_convocation_state = 'published'
       and v_old_status = 'available'
       and v_new_status = 'absent' then
      v_promoted_player_id := private.handle_convoked_withdrawal(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    elsif v_convocation_state = 'published'
       and v_old_status = 'absent'
       and v_new_status = 'available' then
      v_promoted_player_id := private.restore_returning_convoked_player(
        p_match_id, v_participant_id, v_actor, 'staff'
      );
    else
      perform private.recompute_match_convocations_internal(p_match_id, false);
    end if;

    insert into private.sport_admin_audit_log (
      match_id, action, actor_profile_id, reason, metadata
    ) values (
      p_match_id, 'override_availability', v_actor, v_reason,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'season_player_id', p_season_player_id,
        'old_status', v_old_status,
        'new_status', v_new_status,
        'promoted_season_player_id', v_promoted_player_id
      )
    );
  end if;

  return jsonb_build_object(
    'match_id', p_match_id,
    'participant_id', v_participant_id,
    'availability_status', v_new_status,
    'private_comment', v_new_comment,
    'changed', v_changed,
    'promoted_season_player_id', v_promoted_player_id
  );
end;
$function$;

-- Les notifications d'ouverture des disponibilités sautent les joueurs
-- couverts par une période. Les relances, elles, ne visent que les réponses
-- manquantes : une absence déjà posée les écarte sans règle supplémentaire.
create or replace function private.process_sport_availability_notifications(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_event_id bigint;
  v_opened integer := 0;
  v_closed integer := 0;
  v_created integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object(
      'opened_workflows', 0,
      'closed_workflows', 0,
      'notifications_created', 0
    );
  end if;

  with opened as (
    update public.match_sport_workflows workflow
    set availability_state = 'open',
        availability_opened_at = coalesce(workflow.availability_opened_at, p_now),
        updated_at = p_now
    from public.matches match
    where match.id = workflow.match_id
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and workflow.availability_state = 'pending'
      and workflow.availability_opens_at <= p_now
    returning workflow.match_id
  )
  select count(*)::integer into v_opened from opened;

  with closed as (
    update public.match_sport_workflows workflow
    set availability_state = 'closed', updated_at = p_now
    from public.matches match
    where match.id = workflow.match_id
      and workflow.availability_state <> 'closed'
      and (match.status <> 'a_venir' or match.kickoff_at <= p_now)
    returning workflow.match_id
  )
  select count(*)::integer into v_closed from closed;

  if private.is_feature_enabled('notifications_paused') then
    return jsonb_build_object(
      'opened_workflows', v_opened,
      'closed_workflows', v_closed,
      'notifications_created', 0
    );
  end if;

  for v_row in
    select
      workflow.match_id,
      workflow.availability_opens_at,
      workflow.availability_opened_at,
      participant.id as participant_id,
      player.profile_id
    from public.match_sport_workflows workflow
    join public.matches match on match.id = workflow.match_id
    join public.match_sport_participants participant on participant.match_id = workflow.match_id
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where workflow.availability_state = 'open'
      and match.status = 'a_venir'
      and match.kickoff_at > p_now
      and (participant.is_eligible or player.is_coach)
      and profile.status = 'active'
      and not private.is_player_unavailable_at(player.profile_id, match.kickoff_at)
      and not exists (
        select 1
        from public.sport_availability_notification_events event
        where event.participant_id = participant.id
          and event.kind = 'availability_open'
          and event.source = 'automatic'
          and event.scheduled_for = workflow.availability_opens_at
      )
      and not exists (
        select 1
        from public.push_notification_log log
        where log.match_id = workflow.match_id
          and log.kind = 'match_rescheduled_date'
          and workflow.availability_opened_at is not null
          and log.sent_at >= workflow.availability_opened_at
      )
    order by match.kickoff_at, participant.id
  loop
    v_event_id := private.create_sport_availability_notification(
      v_row.match_id,
      v_row.participant_id,
      v_row.profile_id,
      'availability_open',
      'automatic',
      v_row.availability_opens_at,
      null,
      null
    );
    if v_event_id is not null then
      v_created := v_created + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'opened_workflows', v_opened,
    'closed_workflows', v_closed,
    'notifications_created', v_created
  );
end;
$function$;

-- Un match « entre nous » notifie tout le club et non les seuls convoqués :
-- c'est le seul envoi de composition qui doit filtrer lui-même les joueurs
-- indisponibles, les autres ne visent déjà que des convoqués.
create or replace function private.notify_composition_published(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_match_type text;
  v_kickoff_at timestamptz;
  v_first boolean;
  v_profile_ids uuid[];
begin
  select m.status, m.match_type, m.kickoff_at
  into v_status, v_match_type, v_kickoff_at
  from public.matches m
  where m.id = p_match_id;

  if not found or v_status <> 'a_venir' or v_kickoff_at is null then
    return false;
  end if;
  if now() >= v_kickoff_at then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- Aucun ancien client, sauvegarde papier ou RPC historique ne peut
    -- consommer la notification : seul V5 pose ce marqueur transactionnel.
    if coalesce(
      pg_catalog.current_setting(
        'as_grinta.internal_visual_publish',
        true
      ),
      ''
    ) <> '1' then
      return false;
    end if;

    if not private.internal_composition_visual_is_complete(p_match_id) then
      return false;
    end if;
  end if;

  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, 'composition_published', now())
  on conflict (match_id, kind) do nothing;

  get diagnostics v_first = row_count;
  if not v_first then
    return false;
  end if;

  if v_match_type = 'entre_nous' then
    -- « Tous » signifie tous les profils actifs qui ont conservé le réglage
    -- de notification de composition activé, pas seulement les convoqués.
    select array_agg(profile.id order by profile.id)
    into v_profile_ids
    from public.profiles profile
    where profile.status = 'active'
      and profile.notify_composition
      and not private.is_player_unavailable_at(profile.id, v_kickoff_at);
  else
    select array_agg(distinct player.profile_id)
    into v_profile_ids
    from public.match_sport_participants participant
    join public.season_players player
      on player.id = participant.season_player_id
    join public.profiles profile
      on profile.id = player.profile_id
    where participant.match_id = p_match_id
      and (participant.is_eligible or player.is_coach)
      and participant.convocation_status = 'convoked'
      and profile.status = 'active'
      and profile.notify_composition;
  end if;

  if v_profile_ids is null or cardinality(v_profile_ids) = 0 then
    return false;
  end if;

  return private.dispatch_composition_published_push(p_match_id, v_profile_ids);
end;
$function$;

-- Le tableau des disponibilités distingue l'absence déclarée à l'avance de
-- l'absence ponctuelle. La raison, elle, n'y apparaît jamais.
create or replace function private.get_match_availability_board(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'match_id', match.id,
    'kickoff_at', match.kickoff_at,
    'availability_state', case
      when now() >= match.kickoff_at then 'closed'
      when now() >= workflow.availability_opens_at
        and workflow.availability_state = 'pending' then 'open'
      else workflow.availability_state::text
    end,
    'availability_opens_at', workflow.availability_opens_at,
    'squad_size_limit', workflow.squad_size_limit,
    'convocation_state', workflow.convocation_state,
    'convocation_version', workflow.convocation_version,
    'composition_published', exists (
      select 1
      from public.match_composition_publications publication
      where publication.match_id = match.id
    ),
    'players', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'first_name', coalesce(player.first_name, guest.first_name),
        'last_name', coalesce(player.last_name, guest.last_name),
        'display_name', case
          when guest.id is not null then btrim(guest.first_name)
          else coalesce(nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''), btrim(player.first_name))
        end,
        'is_guest', guest.id is not null,
        'is_coach', coalesce(player.is_coach, false),
        'is_unavailable', private.is_player_unavailable_at(
          profile.id, match.kickoff_at
        ),
        'status', participant.availability_status,
        'convocation_status', participant.convocation_status,
        'waitlist_position', waitlist.position,
        'promoted_from_participant_id', participant.promoted_from_participant_id
      )
      order by
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null) then 0
          when participant.availability_status = 'available' then 1
          when participant.availability_status = 'absent' then 2
          when participant.availability_status = 'no_response' then 3
          else 4
        end,
        case
          when participant.convocation_status = 'convoked'
            and (participant.availability_status = 'available' or guest.id is not null)
            then waitlist.position
        end desc nulls last,
        case
          when participant.convocation_status = 'not_convoked'
            and participant.availability_status = 'available'
            then waitlist.position
        end asc nulls last,
        lower(coalesce(player.first_name, guest.first_name, '')),
        participant.id
    ) filter (where participant.id is not null), '[]'::jsonb)
  )
  into v_result
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_participants participant
    on participant.match_id = match.id
   and (
     participant.is_eligible
     or private.participant_is_coach(participant.season_player_id)
   )
  left join public.season_players player
    on player.id = participant.season_player_id
  left join public.profiles profile
    on profile.id = player.profile_id
  left join public.guest_players guest
    on guest.id = participant.guest_player_id
  left join public.sport_waitlist_entries waitlist
    on waitlist.season_player_id = participant.season_player_id
  where match.id = p_match_id
  group by match.id, workflow.match_id;

  if v_result is null then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

commit;
