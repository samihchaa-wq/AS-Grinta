-- Moteur v2 : une sélection, une trace de passage, un classement.
-- À valider sur base de test AVANT toute fusion en production.
begin;

-- Évite de créditer les anciens matchs lors de l'installation initiale.
create table if not exists private.sport_waitlist_engine_activation (
  singleton boolean primary key default true check (singleton),
  activated_at timestamptz not null default now()
);
alter table private.sport_waitlist_engine_activation enable row level security;
revoke all on private.sport_waitlist_engine_activation
  from public, anon, authenticated;
insert into private.sport_waitlist_engine_activation(singleton)
values(true) on conflict (singleton) do nothing;

alter table public.match_sport_workflows
  add column if not exists waitlist_passages_exempt boolean not null default false;

-- Un quota modifié pour accueillir tous les présents annule les +1
-- si le match a connu une attente ; aucun joueur n'est choisi manuellement.
create or replace function private.exempt_waitlist_when_all_fit()
returns trigger language plpgsql security definer
set search_path to ''
as $$
declare
  v_present integer;
begin
  if new.squad_size_limit = old.squad_size_limit then
    return new;
  end if;
  select count(*)::integer into v_present
  from public.match_sport_participants p
  join public.season_players sp on sp.id = p.season_player_id
  where p.match_id = new.match_id
    and p.is_eligible
    and p.availability_status = 'available'
    and not sp.is_coach;

  if v_present > 0
     and new.squad_size_limit >= v_present
     and (
       v_present > old.squad_size_limit
       or exists (
         select 1 from private.sport_waitlist_passage_ledger l
         where l.match_id = new.match_id
       )
     ) then
    new.waitlist_passages_exempt := true;
  end if;
  return new;
end;
$$;
revoke all on function private.exempt_waitlist_when_all_fit()
  from public, anon, authenticated;
drop trigger if exists trg_exempt_waitlist_when_all_fit
  on public.match_sport_workflows;
create trigger trg_exempt_waitlist_when_all_fit
before update of squad_size_limit on public.match_sport_workflows
for each row execute function private.exempt_waitlist_when_all_fit();

-- Tout report de l'heure ou du jour neutralise les +1 du match,
-- même avant l'ouverture de la période de comptage.
create or replace function private.exempt_waitlist_on_reschedule()
returns trigger language plpgsql security definer
set search_path to ''
as $$
begin
  if old.kickoff_at is not null
     and new.kickoff_at is distinct from old.kickoff_at then
    update public.match_sport_workflows
      set waitlist_passages_exempt = true
    where match_id = new.id;
  end if;
  return new;
end;
$$;
revoke all on function private.exempt_waitlist_on_reschedule()
  from public, anon, authenticated;
drop trigger if exists trg_exempt_waitlist_on_reschedule on public.matches;
create trigger trg_exempt_waitlist_on_reschedule
after update of kickoff_at on public.matches
for each row execute function private.exempt_waitlist_on_reschedule();

-- Règle 1 : le même calcul décide chaque convocation. Aucune exception
-- convocation_manual_override, aucune promotion/rétrogradation spéciale.
create or replace function private.recompute_match_convocations_internal(
  p_match_id uuid, p_reset_overrides boolean default false
)
returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_season_id uuid;
  v_limit integer;
  v_kickoff timestamptz;
  v_status text;
  v_available integer;
  v_convoked integer;
  v_waiting integer;
begin
  perform private.require_sports_management_enabled();
  select m.season_id, w.squad_size_limit, m.kickoff_at, m.status
    into v_season_id, v_limit, v_kickoff, v_status
  from public.matches m
  join public.match_sport_workflows w on w.match_id = m.id
  where m.id = p_match_id for update of w;
  if not found then
    raise exception 'Sport workflow not found' using errcode = 'P0002';
  end if;

  -- L'effectif est déjà verrouillé à T-15 : ne rien réécrire pour ce match.
  if v_status = 'a_venir'
     and v_kickoff is not null
     and now() < v_kickoff - interval '15 minutes' then
    perform private.ensure_sport_waitlist(v_season_id, v_actor);
    perform private.rebuild_sport_waitlist_order(v_season_id, v_actor);

    -- Un seul passage fixe l'état de TOUS les membres du match :
    -- le rang ne concerne que les joueurs présents et éligibles.
    with ranked as (
      select p.id, row_number() over (
        order by e.position desc, p.id
      ) as priority
      from public.match_sport_participants p
      join public.sport_waitlist_entries e
        on e.season_player_id = p.season_player_id
       and e.season_id = v_season_id
      where p.match_id = p_match_id
        and p.is_eligible
        and p.availability_status = 'available'
    ), decision as (
      select p.id, e.position, sp.is_coach, r.priority,
        case
          when sp.is_coach and p.availability_status = 'available'
            then 'convoked'::public.sport_convocation_status
          when r.priority <= v_limit
            then 'convoked'::public.sport_convocation_status
          when r.priority > v_limit
            then 'not_convoked'::public.sport_convocation_status
          else 'not_applicable'::public.sport_convocation_status
        end as status
      from public.match_sport_participants p
      join public.season_players sp on sp.id = p.season_player_id
      left join public.sport_waitlist_entries e
        on e.season_player_id = p.season_player_id
       and e.season_id = v_season_id
      left join ranked r on r.id = p.id
      where p.match_id = p_match_id
    )
    update public.match_sport_participants p
       set convocation_status = d.status,
           convocation_manual_override = false,
           waitlist_position_snapshot =
             case when d.is_coach then null else d.position end,
           waitlist_recommended_not_convoked =
             coalesce(d.priority > v_limit, false),
           waitlist_turn_should_consume =
             coalesce(d.priority > v_limit, false),
           waitlist_turn_state = case
             when d.is_coach then 'not_applicable'::public.sport_waitlist_turn_state
             when p.waitlist_turn_state = 'consumed'
               then 'consumed'::public.sport_waitlist_turn_state
             when d.priority is null
               then 'not_applicable'::public.sport_waitlist_turn_state
             when d.priority > v_limit
               then 'pending'::public.sport_waitlist_turn_state
             else 'waived'::public.sport_waitlist_turn_state
           end,
           waitlist_turn_updated_at = now(),
           updated_at = now()
      from decision d
     where p.id = d.id;

    update public.match_sport_workflows
       set convocation_generated_at = now(),
           updated_by = coalesce(v_actor, updated_by),
           updated_at = now()
    where match_id = p_match_id;
  end if;

  select count(*)::integer,
         count(*) filter (where p.convocation_status = 'convoked')::integer,
         count(*) filter (where p.convocation_status = 'not_convoked')::integer
    into v_available, v_convoked, v_waiting
  from public.match_sport_participants p
  join public.season_players sp on sp.id = p.season_player_id
  where p.match_id = p_match_id
    and p.is_eligible
    and p.availability_status = 'available'
    and not sp.is_coach;

  return jsonb_build_object(
    'match_id', p_match_id,
    'squad_size_limit', v_limit,
    'available_count', v_available,
    'convoked_count', v_convoked,
    'not_convoked_count', v_waiting,
    'over_limit_count', greatest(0, v_convoked - v_limit)
  );
end;
$$;

-- Ces deux anciens scénarios deviennent de simples appels au même calcul.
create or replace function private.handle_convoked_withdrawal(
  p_match_id uuid, p_participant_id uuid, p_actor uuid, p_actor_kind text
)
returns uuid language plpgsql security definer set search_path to ''
as $$
declare
  v_candidate uuid;
begin
  select p.season_player_id into v_candidate
  from public.match_sport_participants p
  join public.sport_waitlist_entries e on e.season_player_id = p.season_player_id
  where p.match_id = p_match_id
    and p.availability_status = 'available'
    and p.is_eligible
    and p.convocation_status = 'not_convoked'
  order by e.position desc, p.id limit 1;

  perform private.recompute_match_convocations_internal(p_match_id, false);

  if v_candidate is not null and exists (
    select 1 from public.match_sport_participants p
    where p.match_id = p_match_id
      and p.season_player_id = v_candidate
      and p.convocation_status = 'convoked'
  ) then
    return v_candidate;
  end if;
  return null;
end;
$$;

create or replace function private.restore_returning_convoked_player(
  p_match_id uuid, p_participant_id uuid, p_actor uuid, p_actor_kind text
)
returns uuid language plpgsql security definer set search_path to ''
as $$
declare
  v_candidate uuid;
begin
  select p.season_player_id into v_candidate
  from public.match_sport_participants p
  join public.sport_waitlist_entries e on e.season_player_id = p.season_player_id
  where p.match_id = p_match_id
    and p.id <> p_participant_id
    and p.availability_status = 'available'
    and p.is_eligible
    and p.convocation_status = 'convoked'
  order by e.position asc, p.id limit 1;

  perform private.recompute_match_convocations_internal(p_match_id, false);

  if v_candidate is not null and exists (
    select 1 from public.match_sport_participants p
    where p.match_id = p_match_id
      and p.season_player_id = v_candidate
      and p.convocation_status = 'not_convoked'
  ) then
    return v_candidate;
  end if;
  return null;
end;
$$;

-- L'admin peut régler le quota, pas décider qui remplace le classement.
create or replace function private.publish_match_effectif(
  p_match_id uuid, p_squad_size_limit integer, p_decisions jsonb,
  p_reason text default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_kickoff timestamptz;
  v_status text;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_squad_size_limit is null or p_squad_size_limit < 1
     or p_squad_size_limit > 30 then
    raise exception 'Invalid squad size' using errcode = '22023';
  end if;
  if p_decisions is null or jsonb_typeof(p_decisions) <> 'array' then
    raise exception 'Invalid effectif payload' using errcode = '22023';
  end if;
  select m.kickoff_at, m.status into v_kickoff, v_status
  from public.matches m
  join public.match_sport_workflows w on w.match_id = m.id
  where m.id = p_match_id for update of m, w;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' or now() >= v_kickoff - interval '15 minutes' then
    raise exception 'Effectif already locked' using errcode = '22023';
  end if;

  update public.match_sport_workflows
  set squad_size_limit = p_squad_size_limit,
      updated_by = v_actor, updated_at = now()
  where match_id = p_match_id;

  -- Les décisions manuelles reçues des anciens clients ne sont jamais
  -- appliquées : elles ne doivent pas pouvoir contourner la règle n°1.
  perform private.publish_match_convocations(p_match_id, p_reason);

  -- Préserver l'audit de chaque enregistrement de quota : ce journal est
  -- distinct du calcul des convocations et utile aux administrateurs.
  insert into private.sport_admin_audit_log (
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id, 'update_match_effectif', v_actor,
    nullif(btrim(p_reason), ''),
    jsonb_build_object('squad_size_limit', p_squad_size_limit)
  );
  return private.get_match_convocations(p_match_id);
end;
$$;

-- Ce RPC n'a plus de sens : garder la signature, mais refuser explicitement.
create or replace function private.set_match_convocation(
  p_match_id uuid, p_season_player_id uuid, p_status text,
  p_turn_should_consume boolean, p_reason text default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
begin
  raise exception 'Convocations automatiques : modifier les disponibilités ou le quota.'
    using errcode = '22023';
end;
$$;

-- Les modifications individuelles de rang sont interdites : seul le tri
-- des trois critères peut définir l'ordre. La signature est conservée.
create or replace function private.reorder_sport_waitlist(
  p_season_id uuid, p_ordered_player_ids uuid[], p_reason text default null
)
returns jsonb language plpgsql security definer set search_path to ''
as $$
declare
  v_season_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  v_season_id := private.resolve_open_sport_season(p_season_id);
  perform private.ensure_sport_waitlist(v_season_id, (select auth.uid()));
  perform private.rebuild_sport_waitlist_order(v_season_id, (select auth.uid()));
  perform private.rebalance_upcoming_waitlist_matches(v_season_id);
  return private.get_sport_waitlist(v_season_id);
end;
$$;

-- Toute modification validée du compteur réordonne automatiquement la liste.
create or replace function public.admin_set_waitlist_manual_count(
  p_season_player_id uuid, p_count integer
)
returns void language plpgsql security definer set search_path to ''
as $$
declare
  v_season_id uuid;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_count is null or p_count < 0 then
    raise exception 'Invalid count' using errcode = '22023';
  end if;
  update public.sport_waitlist_entries
     set manual_waitlist_count = p_count,
         updated_at = now(), updated_by = (select auth.uid())
   where season_player_id = p_season_player_id
   returning season_id into v_season_id;
  if not found then
    raise exception 'Waitlist entry not found' using errcode = 'P0002';
  end if;
  perform private.rebuild_sport_waitlist_order(v_season_id, (select auth.uid()));
  perform private.rebalance_upcoming_waitlist_matches(v_season_id);
end;
$$;

-- Rebalance toutes les prochaines convocations non verrouillées.
create or replace function private.rebalance_upcoming_waitlist_matches(
  p_season_id uuid
)
returns void language plpgsql security definer set search_path to ''
as $$
declare v_match record;
begin
  for v_match in
    select m.id from public.matches m
    join public.match_sport_workflows w on w.match_id = m.id
    where m.season_id = p_season_id
      and m.status = 'a_venir'
      and m.kickoff_at > now() + interval '15 minutes'
    order by m.kickoff_at, m.id
  loop
    perform private.recompute_match_convocations_internal(v_match.id, false);
  end loop;
end;
$$;

-- Règle 2 : comptabilisation EXACTEMENT au coup d'envoi, au plus une fois.
-- Les entrées dans le journal survivent aux promotions et aux absences.
create or replace function private.finalize_match_waitlist_turns_internal(
  p_match_id uuid, p_force boolean default false
)
returns integer language plpgsql security definer set search_path to ''
as $$
declare
  v_season_id uuid;
  v_kickoff timestamptz;
  v_status text;
  v_exempt boolean;
  v_enabled_at timestamptz;
  v_count integer := 0;
begin
  perform private.require_sports_management_enabled();

  select m.season_id, m.kickoff_at, m.status, w.waitlist_passages_exempt
    into v_season_id, v_kickoff, v_status, v_exempt
  from public.matches m
  join public.match_sport_workflows w on w.match_id = m.id
  where m.id = p_match_id
  for update of w;
  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  select activated_at into v_enabled_at
  from private.sport_waitlist_engine_activation where singleton;

  if v_kickoff is null or now() < v_kickoff
     or v_kickoff < v_enabled_at
     or v_status = 'annule' or v_exempt then
    return 0;
  end if;

  perform private.ensure_sport_waitlist(v_season_id, null);

  -- Un joueur toujours en attente au coup d'envoi doit être crédité même
  -- s'il ne s'est produit aucun changement depuis J-1 à 12 h.
  insert into private.sport_waitlist_passage_ledger
      (match_id, season_player_id, first_eligible_at)
  select p_match_id, p.season_player_id,
         private.waitlist_credit_cutoff(v_kickoff)
  from public.match_sport_participants p
  join public.sport_waitlist_entries e
    on e.season_player_id = p.season_player_id
   and e.season_id = v_season_id
  where p.match_id = p_match_id
    and p.is_eligible and p.availability_status = 'available'
    and p.convocation_status = 'not_convoked'
  on conflict (match_id, season_player_id) do nothing;

  -- Une seule instruction transactionnelle crédite et incrémente
  -- le compteur utilisé par l'interface et par le classement.
  with fresh as (
    update private.sport_waitlist_passage_ledger l
    set credited_at = now()
    where l.match_id = p_match_id
      and l.credited_at is null
    returning l.season_player_id
  ), grouped as (
    select season_player_id, count(*)::integer as increment
    from fresh group by season_player_id
  )
  update public.sport_waitlist_entries e
     set manual_waitlist_count = e.manual_waitlist_count + g.increment,
         updated_at = now()
    from grouped g
   where e.season_player_id = g.season_player_id
     and e.season_id = v_season_id;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    update public.match_sport_participants p
      set waitlist_turn_state = 'consumed',
          waitlist_turn_should_consume = true,
          waitlist_turn_updated_at = now(),
          updated_at = now()
    where p.match_id = p_match_id
      and exists (
        select 1 from private.sport_waitlist_passage_ledger l
        where l.match_id = p.match_id
          and l.season_player_id = p.season_player_id
          and l.credited_at is not null
      );

    -- Préserve l'événement historique sans en produire plusieurs au retry.
    insert into public.match_sport_participant_events (
      participant_id, match_id, event_type, old_value, new_value,
      actor_profile_id, actor_kind
    )
    select p.id, p_match_id, 'waitlist_turn_consumed',
      '{}'::jsonb,
      jsonb_build_object('counted_at', l.credited_at),
      null, 'system'
    from public.match_sport_participants p
    join private.sport_waitlist_passage_ledger l
      on l.match_id = p.match_id and l.season_player_id = p.season_player_id
    where p.match_id = p_match_id and l.credited_at is not null
      and not exists (
        select 1 from public.match_sport_participant_events ev
        where ev.participant_id = p.id
          and ev.match_id = p_match_id
          and ev.event_type = 'waitlist_turn_consumed'
      );

    perform private.rebuild_sport_waitlist_order(v_season_id, null);
    perform private.rebalance_upcoming_waitlist_matches(v_season_id);
  end if;

  return v_count;
end;
$$;

create or replace function private.finalize_due_waitlist_turns_for_season(
  p_season_id uuid
)
returns integer language plpgsql security definer set search_path to ''
as $$
declare
  v_match record;
  v_total integer := 0;
  v_enabled_at timestamptz;
begin
  select activated_at into v_enabled_at
  from private.sport_waitlist_engine_activation where singleton;

  for v_match in
    select m.id from public.matches m
    join public.match_sport_workflows w on w.match_id = m.id
    where m.season_id = p_season_id
      and m.kickoff_at <= now()
      and m.kickoff_at >= v_enabled_at
      and m.status <> 'annule'
      and not w.waitlist_passages_exempt
      and (
        exists (select 1 from private.sport_waitlist_passage_ledger l
                where l.match_id = m.id and l.credited_at is null)
        or exists (
          select 1 from public.match_sport_participants p
          where p.match_id = m.id and p.is_eligible
            and p.availability_status = 'available'
            and p.convocation_status = 'not_convoked'
            and not exists (
              select 1 from private.sport_waitlist_passage_ledger l
              where l.match_id = m.id
                and l.season_player_id = p.season_player_id
            )
        )
      )
    order by m.kickoff_at, m.id
  loop
    v_total := v_total
      + private.finalize_match_waitlist_turns_internal(v_match.id, false);
  end loop;
  return v_total;
end;
$$;

-- Une tâche minute déjà adaptée au rythme actuel des disponibilités.
create or replace function private.process_due_waitlist_credits()
returns integer language plpgsql security definer set search_path to ''
as $$
declare
  v_season record;
  v_total integer := 0;
begin
  for v_season in
    select s.id from public.seasons s where s.status = 'open'
  loop
    v_total := v_total
      + private.finalize_due_waitlist_turns_for_season(v_season.id);
  end loop;
  return v_total;
end;
$$;

-- Réconciliation non destructive de l'historique déjà enregistré.
-- Avant cette refonte, le +1 déplaçait un joueur sans toujours augmenter
-- le compteur. On récupère les passages des matchs réellement joués,
-- sans doublonner un même match, tout en conservant toute correction manuelle
-- existante qui serait supérieure à l'historique reconstitué.
with historic_passages as (
  select p.season_player_id, count(distinct p.match_id)::integer as turns
  from public.match_sport_participants p
  join public.matches m on m.id = p.match_id
  where m.status in ('termine', 'archive')
    and p.season_player_id is not null
    and (
      p.waitlist_turn_state = 'consumed'
      or exists (
        select 1
        from public.match_sport_participant_events ev
        where ev.participant_id = p.id
          and ev.event_type = 'waitlist_turn_consumed'
      )
    )
  group by p.season_player_id
)
update public.sport_waitlist_entries e
set manual_waitlist_count = h.turns,
    updated_at = now()
from historic_passages h, public.seasons s
where e.season_player_id = h.season_player_id
  and e.season_id = s.id
  and s.status = 'open'
  and h.turns > e.manual_waitlist_count;

-- À l'installation, l'ordre existant est rétabli selon les trois critères
-- puis répercuté sur les seuls matchs non verrouillés.
do $$
declare
  v_season record;
begin
  for v_season in
    select distinct e.season_id from public.sport_waitlist_entries e
    join public.seasons s on s.id = e.season_id
    where s.status = 'open'
  loop
    perform private.rebuild_sport_waitlist_order(v_season.season_id, null);
    perform private.rebalance_upcoming_waitlist_matches(v_season.season_id);
  end loop;
end;
$$;

-- Exécuter exactement une fois par minute ; doublons sans effet grâce au PK.
select cron.schedule(
  'as-grinta-waitlist-credit-v2',
  '* * * * *',
  'select private.process_due_waitlist_credits();'
);

-- Sécurité : toutes les primitives restent hors de l'API publique.
revoke all on function private.recompute_match_convocations_internal(uuid,boolean)
  from public, anon, authenticated;
revoke all on function private.finalize_match_waitlist_turns_internal(uuid,boolean)
  from public, anon, authenticated;
revoke all on function private.finalize_due_waitlist_turns_for_season(uuid)
  from public, anon, authenticated;
revoke all on function private.rebalance_upcoming_waitlist_matches(uuid)
  from public, anon, authenticated;
revoke all on function private.process_due_waitlist_credits()
  from public, anon, authenticated;
revoke all on function private.handle_convoked_withdrawal(uuid,uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function private.restore_returning_convoked_player(uuid,uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function private.publish_match_effectif(uuid,integer,jsonb,text)
  from public, anon, authenticated;
revoke all on function private.set_match_convocation(uuid,uuid,text,boolean,text)
  from public, anon, authenticated;
revoke all on function private.reorder_sport_waitlist(uuid,uuid[],text)
  from public, anon, authenticated;

commit;
