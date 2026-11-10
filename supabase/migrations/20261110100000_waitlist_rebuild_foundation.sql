-- Premier composant de la refonte : un seul journal des passages en attente
-- et un seul ordre de classement calculé. NON ACTIVÉ EN PRODUCTION.
begin;

create table if not exists private.sport_waitlist_passage_ledger (
  match_id uuid not null references public.matches(id) on delete cascade,
  season_player_id uuid not null references public.season_players(id) on delete cascade,
  first_eligible_at timestamptz not null,
  credited_at timestamptz,
  primary key (match_id, season_player_id)
);
-- La PK commence par match_id : cet index supplémentaire couvre la FK
-- season_player_id lors des suppressions de joueurs et des vérifications.
create index if not exists sport_waitlist_passage_ledger_player_idx
  on private.sport_waitlist_passage_ledger (season_player_id);
alter table private.sport_waitlist_passage_ledger enable row level security;
revoke all on private.sport_waitlist_passage_ledger from public, anon, authenticated;

-- J-1 à 12:00 heure française, sans supposer un décalage UTC fixe.
create or replace function private.waitlist_credit_cutoff(p_kickoff timestamptz)
returns timestamptz
language sql immutable
set search_path to ''
as $$
  select (((p_kickoff at time zone 'Europe/Paris')::date - 1)
           + time '12:00') at time zone 'Europe/Paris';
$$;
revoke all on function private.waitlist_credit_cutoff(timestamptz)
  from public, anon, authenticated;

-- Un passage bref suffit. On mémorise la transition d'entrée OU de sortie :
-- 14h attente -> 15h convoqué conserve ainsi son droit au +1.
create or replace function private.record_waitlist_presence()
returns trigger
language plpgsql security definer set search_path to ''
as $$
declare
  v_kickoff timestamptz;
  v_status text;
  v_before boolean := false;
  v_after boolean := false;
begin
  if new.season_player_id is null then
    return new;
  end if;

  select m.kickoff_at, m.status into v_kickoff, v_status
  from public.matches m where m.id = new.match_id;

  if v_kickoff is null or v_status <> 'a_venir'
     or now() < private.waitlist_credit_cutoff(v_kickoff)
     or now() >= v_kickoff then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_before := old.is_eligible
      and old.availability_status = 'available'
      and old.convocation_status = 'not_convoked';
  end if;
  v_after := new.is_eligible
    and new.availability_status = 'available'
    and new.convocation_status = 'not_convoked';

  if v_before or v_after then
    insert into private.sport_waitlist_passage_ledger
      (match_id, season_player_id, first_eligible_at)
    values (new.match_id, new.season_player_id, now())
    on conflict (match_id, season_player_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.record_waitlist_presence()
  from public, anon, authenticated;

drop trigger if exists trg_record_waitlist_presence on public.match_sport_participants;
create trigger trg_record_waitlist_presence
after insert or update of
  convocation_status, availability_status, is_eligible
on public.match_sport_participants
for each row execute function private.record_waitlist_presence();

-- Recalcul unique : moins de passages, puis moins de matchs joués,
-- puis ordre alphabétique. Aucun déplacement individuel arbitraire.
create or replace function private.rebuild_sport_waitlist_order(
  p_season_id uuid, p_actor uuid default null
)
returns void language plpgsql security definer set search_path to ''
as $$
declare
  v_offset integer;
begin
  -- Sérialiser les reclassements de la même saison.
  perform 1 from public.seasons where id = p_season_id for update;
  if not found then
    raise exception 'Season not found' using errcode = 'P0002';
  end if;

  -- Pas d'écriture quand le classement respecte déjà les trois critères.
  if not exists (
    select 1 from (
      select e.position, row_number() over (
        order by e.manual_waitlist_count,
          e.previous_season_attendance_count,
          lower(p.last_name), lower(p.first_name), e.season_player_id
      )::integer as expected
      from public.sport_waitlist_entries e
      join public.season_players p on p.id = e.season_player_id
      where e.season_id = p_season_id
    ) ranks where ranks.position <> ranks.expected
  ) then
    return;
  end if;

  -- Les positions intermédiaires dépassent toutes les anciennes positions :
  -- on respecte UNIQUE(season_id, position) sans table temporaire.
  select coalesce(max(position), 0) + count(*)::integer + 1
    into v_offset
  from public.sport_waitlist_entries where season_id = p_season_id;

  update public.sport_waitlist_entries
     set position = position + v_offset
   where season_id = p_season_id;

  with ranked as (
    select e.season_player_id,
      row_number() over (
        order by e.manual_waitlist_count,
          e.previous_season_attendance_count,
          lower(p.last_name), lower(p.first_name), e.season_player_id
      )::integer as position
    from public.sport_waitlist_entries e
    join public.season_players p on p.id = e.season_player_id
    where e.season_id = p_season_id
  )
  update public.sport_waitlist_entries e
     set position = r.position,
         updated_by = coalesce(p_actor, e.updated_by),
         updated_at = now()
    from ranked r
   where e.season_id = p_season_id
     and e.season_player_id = r.season_player_id;
end;
$$;
revoke all on function private.rebuild_sport_waitlist_order(uuid, uuid)
  from public, anon, authenticated;

commit;
