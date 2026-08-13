-- Correctifs de cycle de vie issus de l'audit du 13/08/2026.
--
-- Bug 13 : un « Match entre nous » basculait en `termine` a la minute meme du
--          coup d'envoi.
-- Bug 20 : deux cles etrangeres en RESTRICT oubliees rendaient un compte admin
--          impossible a supprimer des qu'il avait arbitre un Live.
-- Bug 27 : le journal d'audit perdait toute trace du match apres suppression.
-- Bug 41 : trois cles etrangeres en RESTRICT contredisaient la promesse de
--          suppression definitive d'un match.
-- Bug 42 : la cloture du vote HDM n'etait ni testable ni rejouable a une date
--          choisie.

begin;

-- ---------------------------------------------------------------------------
-- Bug 13 — fin automatique d'un match interne
-- ---------------------------------------------------------------------------

-- La duree planifiee et le tampon d'apres-match de 15 minutes, deja utilises
-- partout ailleurs (matchExpectedValidationAt cote application), etaient
-- ignores : l'admin perdait tous les controles du match a l'instant ou il
-- commencait, le dialogue « Terminer ce match ? » devenait inatteignable, et
-- recalculate_all_badges() tournait sur un score 0-0.
create or replace function private.finish_due_internal_matches(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_finished integer := 0;
begin
  update public.matches match
  set status = 'termine',
      updated_at = p_now
  where match.match_type = 'entre_nous'
    and match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at
        + make_interval(
            mins => coalesce(match.planned_duration_minutes, 90) + 15
          ) <= p_now;

  get diagnostics v_finished = row_count;
  return v_finished;
end;
$function$;

comment on function private.finish_due_internal_matches(timestamptz) is
  'Marque termine un Match entre nous une fois sa duree planifiee ecoulee, plus le tampon d apres-match de 15 minutes.';

revoke all on function private.finish_due_internal_matches(timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bug 42 — cloture HDM rejouable
-- ---------------------------------------------------------------------------

-- `now()` etait code en dur alors que les deux fonctions soeurs appelees par
-- le meme job acceptent un `p_now`. La transition prend desormais l'instant de
-- reference en parametre, ce qui la rend testable a une date choisie.
create or replace function private.transition_match_motm_election(
  p_match_id uuid,
  p_now timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_election public.match_sport_motm_elections%rowtype;
begin
  select * into v_election
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id
  for update;
  if not found then
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.closes_at is not null
     and p_now >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
    return;
  end if;

  if v_election.state = 'draft'
     and v_election.opens_at is not null
     and p_now >= v_election.opens_at
     and p_now < v_election.closes_at then
    update public.match_sport_motm_elections
    set state = 'open', updated_at = p_now
    where match_id = p_match_id;
    update public.match_sport_workflows
    set vote_state = 'open', updated_at = p_now
    where match_id = p_match_id;
    return;
  end if;

  if v_election.state = 'open'
     and v_election.closes_at is not null
     and p_now >= v_election.closes_at then
    perform private.close_match_motm_election(p_match_id, false);
  end if;
end;
$function$;

revoke all on function private.transition_match_motm_election(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function private.close_due_match_motm_elections(
  p_now timestamptz default now()
)
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
    select election.match_id
    from public.match_sport_motm_elections election
    where election.state in ('draft', 'open')
    order by election.closes_at nulls last, election.match_id
    for update skip locked
  loop
    perform private.transition_match_motm_election(v_row.match_id, p_now);
    v_processed := v_processed + 1;
  end loop;

  return v_processed;
end;
$function$;

comment on function private.close_due_match_motm_elections(timestamptz) is
  'Fait avancer les scrutins HDM arrives a echeance. Accepte un instant de reference, comme ses fonctions soeurs.';

revoke all on function private.close_due_match_motm_elections(timestamptz)
  from public, anon, authenticated;

-- L'ancienne signature sans parametre disparait au profit de la version
-- parametree, dont la valeur par defaut couvre l'appel du job.
drop function if exists private.close_due_match_motm_elections();
drop function if exists private.transition_match_motm_election(uuid);

create or replace function private.process_match_motm_jobs(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_transitions integer;
  v_open_notifications integer;
  v_result_notifications integer;
begin
  v_transitions := private.close_due_match_motm_elections(p_now);
  v_open_notifications := private.push_due_motm_open_notifications(p_now);
  v_result_notifications := private.push_due_motm_result_notifications(p_now);
  return jsonb_build_object(
    'transitions', v_transitions,
    'open_notifications', v_open_notifications,
    'result_notifications', v_result_notifications
  );
end;
$function$;

revoke all on function private.process_match_motm_jobs(timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bug 27 — le journal d'audit garde une trace lisible du match
-- ---------------------------------------------------------------------------

-- `match_id` est en ON DELETE SET NULL : apres la suppression d'un match, ses
-- entrees d'audit survivaient mais sans aucun moyen de savoir de quel match il
-- s'agissait. Une copie textuelle (date + adversaire) est donc figee a
-- l'ecriture.
alter table private.sport_admin_audit_log
  add column if not exists match_label text;

comment on column private.sport_admin_audit_log.match_label is
  'Copie figee « date — adversaire » du match concerne. Survit a la suppression du match, contrairement a match_id (ON DELETE SET NULL).';

create or replace function private.fill_sport_admin_audit_match_label()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.match_label is not null or new.match_id is null then
    return new;
  end if;

  select trim(
           both ' —' from
           coalesce(to_char(m.kickoff_at, 'DD/MM/YYYY'), '')
           || ' — '
           || coalesce(
                case when m.match_type = 'entre_nous'
                     then 'Match entre nous'
                     else opponent.name
                end,
                'Adversaire inconnu'
              )
         )
    into new.match_label
  from public.matches m
  left join public.opponents opponent on opponent.id = m.opponent_id
  where m.id = new.match_id;

  return new;
end;
$function$;

revoke all on function private.fill_sport_admin_audit_match_label()
  from public, anon, authenticated;

drop trigger if exists trg_fill_sport_admin_audit_match_label
  on private.sport_admin_audit_log;
create trigger trg_fill_sport_admin_audit_match_label
  before insert on private.sport_admin_audit_log
  for each row
  execute function private.fill_sport_admin_audit_match_label();

-- Rattrapage des 449 entrees existantes dont le match est encore present.
update private.sport_admin_audit_log entry
set match_label = trim(
      both ' —' from
      coalesce(to_char(m.kickoff_at, 'DD/MM/YYYY'), '')
      || ' — '
      || coalesce(
           case when m.match_type = 'entre_nous'
                then 'Match entre nous'
                else opponent.name
           end,
           'Adversaire inconnu'
         )
    )
from public.matches m
left join public.opponents opponent on opponent.id = m.opponent_id
where entry.match_id = m.id
  and entry.match_label is null;

-- ---------------------------------------------------------------------------
-- Bug 20 — suppression d'un compte ayant arbitre un Live
-- ---------------------------------------------------------------------------

-- 17 cles etrangeres en RESTRICT pointent vers profiles.id ; la fonction en
-- neutralisait 15. Les deux oubliees bloquaient la suppression des qu'un admin
-- avait touche au Tableau Blanc, avec pour seul retour « La demande n'a pas pu
-- etre traitee. ».
create or replace function private.prepare_profile_for_hard_deletion(
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_system_actor constant uuid := '00000000-0000-0000-0000-000000000001'::uuid;
begin
  if p_profile_id is null then
    raise exception 'Profile id is required' using errcode = '22023';
  end if;
  if p_profile_id = v_system_actor then
    raise exception 'Technical profile cannot be deleted' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = v_system_actor) then
    raise exception 'Technical replacement profile is missing' using errcode = '55000';
  end if;

  delete from public.sport_availability_notification_events
  where profile_id = p_profile_id;

  delete from public.match_sport_motm_votes
  where voter_profile_id = p_profile_id;

  update private.sport_admin_audit_log
  set actor_profile_id = v_system_actor
  where actor_profile_id = p_profile_id;

  update public.guest_players
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.guest_players
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  perform set_config('as_grinta.allow_postmatch_composition_write', 'on', true);

  update public.match_composition_publications
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_compositions
  set last_modified_by = v_system_actor
  where last_modified_by = p_profile_id;
  update public.match_compositions
  set published_by = v_system_actor
  where published_by = p_profile_id;

  update public.match_sport_finalization_versions
  set created_by = v_system_actor
  where created_by = p_profile_id;

  update public.match_sport_finalizations
  set validated_by = v_system_actor
  where validated_by = p_profile_id;
  update public.match_sport_finalizations
  set corrected_by = null
  where corrected_by = p_profile_id;

  update public.match_sport_workflows
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.match_sport_workflows
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  update public.sport_waitlist_entries
  set created_by = v_system_actor
  where created_by = p_profile_id;
  update public.sport_waitlist_entries
  set updated_by = v_system_actor
  where updated_by = p_profile_id;

  -- Les deux tables oubliees : elles se remplissent des le premier Live
  -- reellement arbitre.
  update public.match_live_events
  set created_by = v_system_actor
  where created_by = p_profile_id;

  update public.match_live_sessions
  set updated_by = v_system_actor
  where updated_by = p_profile_id;
end;
$function$;

revoke all on function private.prepare_profile_for_hard_deletion(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bug 41 — la suppression d'un match tient sa promesse
-- ---------------------------------------------------------------------------

-- Le dialogue annonce « Le match, ses pronostics, ses buteurs et ses
-- statistiques seront definitivement supprimes. » : 9 des 12 cles etrangeres
-- vers matches.id etaient en CASCADE, 3 en RESTRICT. En pratique le verrou
-- T-15 masquait le conflit, mais deux regles se recouvraient par accident.
alter table public.match_live_events
  drop constraint if exists match_live_events_match_id_fkey;
alter table public.match_live_events
  add constraint match_live_events_match_id_fkey
  foreign key (match_id) references public.matches(id) on delete cascade;

alter table public.match_live_sessions
  drop constraint if exists match_live_sessions_match_id_fkey;
alter table public.match_live_sessions
  add constraint match_live_sessions_match_id_fkey
  foreign key (match_id) references public.matches(id) on delete cascade;

alter table public.match_sport_workflows
  drop constraint if exists match_sport_workflows_match_id_fkey;
alter table public.match_sport_workflows
  add constraint match_sport_workflows_match_id_fkey
  foreign key (match_id) references public.matches(id) on delete cascade;

commit;
