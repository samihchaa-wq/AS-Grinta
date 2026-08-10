begin;

-- Le contrat produit HDM est strict : ouverture à H+1 h 45 après le coup
-- d'envoi. Une validation Stats ou un récapitulatif Live ne peut jamais avancer
-- cette fenêtre.
create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select match.kickoff_at + interval '1 hour 45 minutes'
  from public.matches match
  where match.id = p_match_id;
$function$;

comment on function private.match_motm_opens_at(uuid) is
  'Ouvre le vote HDM strictement à H+1 h 45 après le coup d''envoi.';

-- La fermeture reste fixe à H+24 après le coup d'envoi.
create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_exists boolean;
  v_kickoff timestamptz;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select match.kickoff_at into v_kickoff
  from public.matches match
  where match.id = p_match_id
    and match.status <> 'annule';
  if v_kickoff is null then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    'draft'::public.sport_vote_state,
    v_opens_at,
    v_closes_at,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft',
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

-- Le job périodique doit créer le scrutin dès H+1 h 45, et non H+2.
create or replace function private.close_due_match_motm_elections()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row record;
  v_processed integer := 0;
begin
  if not private.is_feature_enabled('sports_management') then
    return 0;
  end if;

  for v_row in
    select match.id as match_id
    from public.matches match
    where match.status <> 'annule'
      and match.kickoff_at + interval '1 hour 45 minutes' <= now()
      and match.kickoff_at > now() - interval '30 days'
      and not exists (
        select 1
        from public.match_sport_motm_elections election
        where election.match_id = match.id
      )
    order by match.kickoff_at, match.id
  loop
    perform private.ensure_match_motm_election(v_row.match_id);
  end loop;

  for v_row in
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

-- Réaligne les scrutins encore en brouillon sur la règle stricte. Les scrutins
-- déjà ouverts ne sont pas rétrogradés afin de ne pas invalider des votes déjà
-- exprimés pendant un déploiement.
update public.match_sport_motm_elections election
set opens_at = private.match_motm_opens_at(election.match_id),
    updated_at = now()
where election.state = 'draft';

-- Une finalisation post-match peut créer ou synchroniser le scrutin, mais ne
-- doit jamais avancer son heure d'ouverture avant H+1 h 45.
create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_opens_at timestamptz;
  v_vote_state public.sport_vote_state;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  update public.match_sport_motm_elections election
  set opens_at = v_opens_at,
      updated_at = now()
  where election.match_id = new.match_id
    and election.state = 'draft';

  perform private.transition_match_motm_election(new.match_id);

  select election.state
  into v_vote_state
  from public.match_sport_motm_elections election
  where election.match_id = new.match_id;

  if v_vote_state is not null then
    update public.match_sport_workflows workflow
    set vote_state = v_vote_state,
        updated_at = now()
    where workflow.match_id = new.match_id
      and workflow.vote_state is distinct from v_vote_state;
  end if;

  if v_vote_state = 'closed' then
    delete from public.match_man_of_match
    where match_id = new.match_id;

    insert into public.match_man_of_match(match_id, season_player_id)
    select result.match_id, participant.season_player_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    where result.match_id = new.match_id
      and result.is_winner
      and participant.season_player_id is not null
    on conflict do nothing;
  end if;

  return new;
end;
$function$;

-- Les anciens rappels/résultats HDM et le push score final ne font plus partie
-- du produit. Les triggers sont retirés de manière idempotente avant les
-- fonctions afin de rendre la migration compatible avec les bases historiques.
drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;
drop trigger if exists trg_push_on_match_result on public.matches;

drop function if exists private.push_due_motm_reminders(timestamptz);
drop function if exists public.push_on_motm_election_closed();
drop function if exists public.push_on_match_result();

-- Le transport HDM privé n'accepte plus que l'événement d'ouverture.
create or replace function private.dispatch_motm_push(
  p_kind text,
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  if p_kind <> 'motm_open' then
    raise exception 'Unknown MOTM notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management') then
    return false;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', p_kind,
      'match_id', p_match_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$function$;

-- Une nouvelle fenêtre de vote ne remet à zéro que son propre marqueur
-- d'ouverture. Les anciens types retirés restent intacts dans l'historique.
create or replace function public.push_on_motm_election_opened()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_is_new_window boolean := false;
begin
  if not private.is_feature_enabled('sports_management') then
    return new;
  end if;

  if new.state = 'open' then
    if tg_op = 'INSERT' then
      v_is_new_window := true;
    else
      v_is_new_window := old.state is distinct from 'open'
        or old.opens_at is distinct from new.opens_at
        or old.closes_at is distinct from new.closes_at
        or old.finalization_version is distinct from new.finalization_version;
    end if;
  end if;

  if v_is_new_window then
    delete from public.push_notification_log
    where match_id = new.match_id
      and kind = 'motm_open';

    if not private.is_feature_enabled('notifications_paused') then
      insert into public.push_notification_log(match_id, kind, sent_at)
      values (new.match_id, 'motm_open', now())
      on conflict do nothing;
      if found then
        perform private.dispatch_motm_push('motm_open', new.match_id);
      end if;
    end if;
  end if;

  return new;
end;
$function$;

-- Conserver l'historique des anciens événements sans autoriser de nouveaux
-- inserts avec des types retirés. La contrainte de livraison dépend de celle du
-- journal logique : on la retire donc en premier, sans CASCADE, puis on recrée
-- les deux dans l'ordre inverse. NOT VALID conserve les lignes d'audit passées.
alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;
alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;

alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (kind = any(array[
    'motm_open'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text
  ])) not valid;

alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check check (kind = any(array[
    'availability_open'::text,
    'availability_manual'::text,
    'motm_open'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text,
    'convocation_promoted'::text
  ])) not valid;

-- La signature historique avec le booléen x2 est uniquement un adaptateur vers
-- la RPC actuelle : elle n'a aucune raison d'exécuter avec des privilèges élevés.
create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_use_x2 boolean
)
returns boolean
language sql
security invoker
set search_path to ''
as $function$
  select public.save_match_prediction(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse
  );
$function$;

revoke all on function public.save_match_prediction(uuid, integer, integer, boolean)
  from public, anon;
grant execute on function public.save_match_prediction(uuid, integer, integer, boolean)
  to authenticated;

-- Index de couverture des clés étrangères signalées par l'advisor Supabase.
create index if not exists match_internal_composition_entries_participant_match_idx
  on public.match_internal_composition_entries(participant_id, match_id);
create index if not exists match_live_events_created_by_idx
  on public.match_live_events(created_by);
create index if not exists match_live_events_player_in_participant_match_idx
  on public.match_live_events(player_in_participant_id, match_id);
create index if not exists match_live_events_player_out_participant_match_idx
  on public.match_live_events(player_out_participant_id, match_id);
create index if not exists match_live_events_scorer_participant_match_idx
  on public.match_live_events(scorer_participant_id, match_id);
create index if not exists match_live_sessions_updated_by_idx
  on public.match_live_sessions(updated_by);

-- Les anciennes policies FOR ALL ajoutaient une seconde policy permissive en
-- SELECT. On conserve la lecture existante et on sépare les écritures.
drop policy if exists match_internal_compositions_write
  on public.match_internal_compositions;
create policy match_internal_compositions_insert
  on public.match_internal_compositions
  for insert to authenticated
  with check (public.is_match_staff());
create policy match_internal_compositions_update
  on public.match_internal_compositions
  for update to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());
create policy match_internal_compositions_delete
  on public.match_internal_compositions
  for delete to authenticated
  using (public.is_match_staff());

drop policy if exists match_internal_composition_entries_write
  on public.match_internal_composition_entries;
create policy match_internal_composition_entries_insert
  on public.match_internal_composition_entries
  for insert to authenticated
  with check (public.is_match_staff());
create policy match_internal_composition_entries_update
  on public.match_internal_composition_entries
  for update to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());
create policy match_internal_composition_entries_delete
  on public.match_internal_composition_entries
  for delete to authenticated
  using (public.is_match_staff());

commit;
