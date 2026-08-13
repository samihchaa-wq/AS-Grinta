-- Non-régression des correctifs issus de l'audit du 13/08/2026.
--
-- Couvre les bugs 3 (validation des noms de profil), 5 (fuite
-- profile_badge_metrics), 9 (cohérence des statistiques), 13 (fin des matchs
-- internes), 14 (concurrence sur la composition), 19 (nettoyage du stockage),
-- 20 (suppression d'un compte ayant arbitré un Live), 27 (libellé d'audit),
-- 38 (RLS des tables private) et 41 (cascade de suppression d'un match).

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Identités et données exclusivement réservées aux tests. La transaction
-- finale est annulée ; aucune ligne ne subsiste dans la base locale.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('40000000-0000-0000-0000-000000000001', 'audit-admin@example.invalid',
   '{"first_name":"Admin","last_name":"Audit"}'::jsonb),
  ('40000000-0000-0000-0000-000000000002', 'audit-alice@example.invalid',
   '{"first_name":"Alice","last_name":"Audit"}'::jsonb),
  ('40000000-0000-0000-0000-000000000003', 'audit-bob@example.invalid',
   '{"first_name":"Bob","last_name":"Audit"}'::jsonb);

update public.profiles
set role = case
      when id = '40000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '40000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000003'
);

-- ---------------------------------------------------------------------------
-- Bug 3 — le déclencheur de validation des noms est exécutable par un membre
-- ---------------------------------------------------------------------------

select ok(
  has_function_privilege(
    'authenticated', 'public.is_valid_person_name(text)', 'execute'
  ),
  'authenticated peut exécuter is_valid_person_name (bug 3)'
);

-- ---------------------------------------------------------------------------
-- Bug 5 — profile_badge_metrics est cloisonnée
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege(
    'authenticated', 'private.profile_badge_metrics(uuid)', 'execute'
  ),
  'l’implémentation privée des métriques est hors de portée d’un membre'
);

select ok(
  has_function_privilege(
    'authenticated', 'public.profile_badge_metrics(uuid)', 'execute'
  ),
  'le point d’entrée public gardé reste appelable'
);

set local role authenticated;
set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000002';

select lives_ok(
  $$select * from public.profile_badge_metrics(
      '40000000-0000-0000-0000-000000000002'::uuid
    )$$,
  'un membre lit son propre bilan'
);

select throws_ok(
  $$select * from public.profile_badge_metrics(
      '40000000-0000-0000-0000-000000000003'::uuid
    )$$,
  '42501',
  'un membre ne peut pas lire le bilan d’un autre (bug 5)'
);

select throws_ok(
  $$select * from public.profile_badge_stars(
      '40000000-0000-0000-0000-000000000003'::uuid
    )$$,
  '42501',
  'les étoiles d’un autre membre sont également refusées'
);

-- featured_badges() doit continuer à fonctionner pour tout le monde : c'est le
-- chemin qui affiche les badges arborés partout dans l'application.
select lives_ok(
  $$select * from public.featured_badges()$$,
  'featured_badges reste lisible malgré le cloisonnement (bug 5)'
);

reset role;
set local request.jwt.claim.sub = '';

-- ---------------------------------------------------------------------------
-- Bug 13 — un match interne ne se termine pas au coup d'envoi
-- ---------------------------------------------------------------------------

insert into public.seasons (id, name, status)
values ('40000000-0000-0000-0000-0000000000a1', '2098-2099', 'open');

insert into public.matches (
  id, season_id, match_type, status, kickoff_at,
  match_date, match_time, location, planned_duration_minutes
)
values (
  '40000000-0000-0000-0000-0000000000b1',
  '40000000-0000-0000-0000-0000000000a1',
  'entre_nous', 'a_venir', now(),
  (now() at time zone 'Europe/Paris')::date,
  (now() at time zone 'Europe/Paris')::time,
  'domicile', 90
);

select is(
  private.finish_due_internal_matches(
    (select kickoff_at from public.matches
     where id = '40000000-0000-0000-0000-0000000000b1')
  ),
  0,
  'aucun match interne n’est terminé au coup d’envoi (bug 13)'
);

select is(
  private.finish_due_internal_matches(
    (select kickoff_at + interval '104 minutes' from public.matches
     where id = '40000000-0000-0000-0000-0000000000b1')
  ),
  0,
  'ni avant la fin de la durée planifiée + 15 minutes'
);

select is(
  private.finish_due_internal_matches(
    (select kickoff_at + interval '105 minutes' from public.matches
     where id = '40000000-0000-0000-0000-0000000000b1')
  ),
  1,
  'mais bien une fois ce délai atteint (90 + 15 minutes)'
);

-- ---------------------------------------------------------------------------
-- Bugs 20, 27 et 41 — suppression d'un compte, journal d'audit, cascade
-- ---------------------------------------------------------------------------

insert into public.opponents (id, name)
values ('40000000-0000-0000-0000-0000000000c1', 'Adversaire Audit');

insert into public.matches (
  id, season_id, opponent_id, match_type, status, kickoff_at,
  match_date, match_time, location, planned_duration_minutes
)
values (
  '40000000-0000-0000-0000-0000000000b2',
  '40000000-0000-0000-0000-0000000000a1',
  '40000000-0000-0000-0000-0000000000c1',
  'championnat', 'a_venir', now() + interval '2 days',
  (now() + interval '2 days')::date, '21:00', 'domicile', 90
);

insert into public.match_live_sessions (
  match_id, state, planned_duration_minutes, updated_by
)
values (
  '40000000-0000-0000-0000-0000000000b2', 'not_started', 90,
  '40000000-0000-0000-0000-000000000001'
);

insert into public.match_live_events (
  match_id, event_type, minute, half, score_adverse_after, created_by
)
values (
  '40000000-0000-0000-0000-0000000000b2', 'goal_them', 12, 1, 1,
  '40000000-0000-0000-0000-000000000001'
);

select lives_ok(
  $$select private.prepare_profile_for_hard_deletion(
      '40000000-0000-0000-0000-000000000001'::uuid
    )$$,
  'la préparation à la suppression s’exécute'
);

select is(
  (select count(*)::bigint from public.match_live_events
   where created_by = '40000000-0000-0000-0000-000000000001'),
  0::bigint,
  'match_live_events.created_by est réattribué (bug 20)'
);

select is(
  (select count(*)::bigint from public.match_live_sessions
   where updated_by = '40000000-0000-0000-0000-000000000001'),
  0::bigint,
  'match_live_sessions.updated_by est réattribué (bug 20)'
);

select lives_ok(
  $$delete from public.profiles
    where id = '40000000-0000-0000-0000-000000000001'$$,
  'le compte se supprime sans violation de clé étrangère (bug 20)'
);

insert into private.sport_admin_audit_log (
  match_id, action, actor_profile_id, reason
)
values (
  '40000000-0000-0000-0000-0000000000b2', 'update_composition',
  '00000000-0000-0000-0000-000000000001', 'Test audit'
);

select isnt(
  (select match_label from private.sport_admin_audit_log
   where match_id = '40000000-0000-0000-0000-0000000000b2'
   order by created_at desc limit 1),
  null,
  'le journal d’audit fige un libellé de match (bug 27)'
);

select lives_ok(
  $$delete from public.matches
    where id = '40000000-0000-0000-0000-0000000000b2'$$,
  'la suppression d’un match cascade sur les tables Live (bug 41)'
);

select isnt(
  (select match_label from private.sport_admin_audit_log
   where action = 'update_composition' and reason = 'Test audit'
   order by created_at desc limit 1),
  null,
  'le libellé survit à la suppression du match (bug 27)'
);

-- ---------------------------------------------------------------------------
-- Bugs 6 et 19 — nettoyage du stockage
-- ---------------------------------------------------------------------------

insert into storage.objects (bucket_id, name)
values
  ('profile-photos', '40000000-0000-0000-0000-000000000002/avatar_1.jpg'),
  ('profile-photos', '40000000-0000-0000-0000-000000000002/avatar_2.jpg');

-- Un membre ordinaire doit pouvoir enregistrer sa propre photo : sans cela,
-- l'envoi resterait refusé par guard_sensitive_profile_fields même la CSP
-- corrigée (bug 6).
set local role authenticated;
set local request.jwt.claim.sub = '40000000-0000-0000-0000-000000000002';

-- Chemin relatif : c'est désormais ce que l'application enregistre, le bucket
-- étant privé.
select lives_ok(
  $$update public.profiles
    set photo_url = '40000000-0000-0000-0000-000000000002/avatar_2.jpg'
    where id = '40000000-0000-0000-0000-000000000002'$$,
  'un membre enregistre sa propre photo (bug 6)'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (select count(*)::bigint from storage.objects
   where bucket_id = 'profile-photos'
     and name like '40000000-0000-0000-0000-000000000002/%'),
  1::bigint,
  'seule la photo remplacée est supprimée, la nouvelle est conservée (bug 6)'
);

update public.profiles
set status = 'archived'
where id = '40000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::bigint from storage.objects
   where bucket_id = 'profile-photos'
     and name like '40000000-0000-0000-0000-000000000002/%'),
  0::bigint,
  'l’archivage d’un compte efface ses photos (bug 19, RGPD)'
);

insert into public.badges (
  id, code, name, description, emoji, family, metric, threshold, image_url
)
values (
  '40000000-0000-0000-0000-0000000000d1', 'audit_badge_test', 'Audit',
  'Badge de test', '*', 'joueur', 'matches_played', 1,
  'https://example.invalid/storage/v1/object/public/badge-images/audit_v1.png'
);

insert into storage.objects (bucket_id, name)
values ('badge-images', 'audit_v1.png'), ('badge-images', 'audit_v2.png');

update public.badges
set image_url =
  'https://example.invalid/storage/v1/object/public/badge-images/audit_v2.png'
where id = '40000000-0000-0000-0000-0000000000d1';

select is(
  (select count(*)::bigint from storage.objects
   where bucket_id = 'badge-images' and name = 'audit_v1.png'),
  0::bigint,
  'le visuel de badge remplacé est supprimé du stockage (bug 19)'
);

-- ---------------------------------------------------------------------------
-- Bugs 9, 14 et 38 — contraintes et signatures
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_constraint
    where conname = 'historical_team_statistics_matches_played_check'
  ) and exists (
    select 1 from pg_constraint
    where conname = 'historical_player_statistics_matches_played_check'
  ),
  'les statistiques ne peuvent plus diverger de leurs résultats (bug 9)'
);

select ok(
  exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname = 'admin_save_match_composition'
      and pg_get_function_arguments(proc.oid) like '%p_expected_version%'
  ),
  'admin_save_match_composition accepte une version attendue (bug 14)'
);

select ok(
  (select convalidated from pg_constraint
   where conname = 'push_notification_log_kind_check'),
  'la contrainte de type des notifications est validée (bug 38)'
);

select is(
  (select count(*)::bigint
   from pg_class cls
   join pg_namespace nsp on nsp.oid = cls.relnamespace
   where nsp.nspname = 'private'
     and cls.relkind = 'r'
     and not cls.relrowsecurity),
  0::bigint,
  'toutes les tables du schéma private ont RLS activée (bug 38)'
);

select * from finish();
rollback;
