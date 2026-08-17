begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '92000000-0000-0000-0000-000000000001',
  'badge-auto-audit@example.invalid',
  '{"first_name":"Auto","last_name":"Audit"}'::jsonb
);

update public.profiles
set role = 'pronostiqueur', status = 'active', updated_at = now()
where id = '92000000-0000-0000-0000-000000000001';

insert into public.badges (
  code, name, description, emoji, family, auto,
  metric, threshold, sort_order, kind, category
)
values (
  'audit_auto_test',
  'Badge auto audit test',
  'Badge réservé au test du journal automatique.',
  '🤖',
  'pronostiqueur',
  true,
  'matches_played',
  0,
  999999,
  'tier',
  'all_time'
);

select lives_ok(
  $$select public.recalculate_profile_badges(
      '92000000-0000-0000-0000-000000000001'::uuid
    )$$,
  'le recalcul automatique s’exécute'
);

select is(
  (
    select count(*)
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.profile_id = '92000000-0000-0000-0000-000000000001'
      and b.code = 'audit_auto_test'
      and pb.source = 'auto'
  ),
  1::bigint,
  'le recalcul attribue le badge automatique'
);

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where profile_id = '92000000-0000-0000-0000-000000000001'
      and badge_code = 'audit_auto_test'
      and event_type = 'award'
      and source = 'auto'
      and actor_profile_id is null
      and metadata ->> 'reason' = 'metric_threshold_met'
      and metadata ->> 'metric' = 'matches_played'
      and (metadata ->> 'threshold')::int = 0
      and (metadata ->> 'value')::int = 0
      and state_before is null
      and state_after ->> 'source' = 'auto'
  ),
  1::bigint,
  'la première attribution automatique produit un événement complet'
);

select lives_ok(
  $$select public.recalculate_profile_badges(
      '92000000-0000-0000-0000-000000000001'::uuid
    )$$,
  'un second recalcul identique s’exécute'
);

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where profile_id = '92000000-0000-0000-0000-000000000001'
      and badge_code = 'audit_auto_test'
      and event_type = 'award'
      and source = 'auto'
  ),
  1::bigint,
  'un recalcul idempotent ne crée aucun événement supplémentaire'
);

select lives_ok(
  $$delete from public.profiles
    where id = '92000000-0000-0000-0000-000000000001'::uuid$$,
  'un profil de test sans dépendance métier peut être supprimé'
);

select is(
  (
    select count(*)
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.profile_id = '92000000-0000-0000-0000-000000000001'
      and b.code = 'audit_auto_test'
  ),
  0::bigint,
  'la suppression du profil nettoie bien l’état courant par cascade'
);

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where profile_id = '92000000-0000-0000-0000-000000000001'
      and badge_code = 'audit_auto_test'
      and event_type = 'award'
      and source = 'auto'
  ),
  1::bigint,
  'l’historique automatique survit à la suppression du profil'
);

select * from finish();
rollback;
