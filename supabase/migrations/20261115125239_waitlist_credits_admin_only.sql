-- Les +1 sont exclusivement manuels. Aucun compteur, ordre ou historique
-- existant n'est modifié lors de la bascule.
begin;

-- Arrête le travail périodique ; ses anciennes exécutions restent auditées.
select cron.unschedule(jobid)
from cron.job
where jobname = 'as-grinta-waitlist-credit-v2';

-- Un passage en attente, un report, une annulation ou un changement de quota
-- ne crée plus de crédit et ne retire plus un crédit déjà attribué.
drop trigger if exists trg_record_waitlist_presence
  on public.match_sport_participants;
drop trigger if exists trg_void_waitlist_on_exemption
  on public.match_sport_workflows;
drop trigger if exists trg_exempt_waitlist_when_all_fit
  on public.match_sport_workflows;
drop trigger if exists trg_exempt_waitlist_on_reschedule
  on public.matches;

-- Ces signatures sont encore appelées par les lectures admin, la fin de
-- match et d'anciens clients. Les conserver sans effet empêche également
-- le rattrapage d'anciens crédits en attente, même avec p_force = true.
create or replace function private.finalize_match_waitlist_turns_internal(
  p_match_id uuid, p_force boolean default false
)
returns integer language sql stable security invoker set search_path to ''
as $$ select 0; $$;

create or replace function private.finalize_due_waitlist_turns_for_season(
  p_season_id uuid
)
returns integer language sql stable security invoker set search_path to ''
as $$ select 0; $$;

create or replace function private.process_due_waitlist_credits()
returns integer language sql stable security invoker set search_path to ''
as $$ select 0; $$;

create or replace function private.void_match_waitlist_credits(p_match_id uuid)
returns integer language sql stable security invoker set search_path to ''
as $$ select 0; $$;

revoke all on function private.finalize_match_waitlist_turns_internal(uuid,boolean)
  from public, anon, authenticated;
revoke all on function private.finalize_due_waitlist_turns_for_season(uuid)
  from public, anon, authenticated;
revoke all on function private.process_due_waitlist_credits()
  from public, anon, authenticated;
revoke all on function private.void_match_waitlist_credits(uuid)
  from public, anon, authenticated;

comment on column public.sport_waitlist_entries.manual_waitlist_count is
  'Compteur de passages en attente géré exclusivement par un administrateur via admin_set_waitlist_manual_count ; aucun ajout ni retrait automatique.';
comment on function public.admin_finalize_match_waitlist_turns(uuid) is
  'Compatibilité : retourne 0 sans modifier les compteurs. Les +1 sont exclusivement manuels via admin_set_waitlist_manual_count.';

-- admin_set_waitlist_manual_count reste l'unique écriture fonctionnelle du
-- compteur : contrôle admin, audit, reclassement et prochaines convocations.
-- Les journaux historiques et le point de départ de la saison sont conservés.
commit;
