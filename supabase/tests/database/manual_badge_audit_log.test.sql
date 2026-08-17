begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('private.profile_badge_audit_log') is not null,
  'le journal privé des badges existe'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.profile_badge_audit_log'::regclass
  ),
  'le journal privé a la RLS activée'
);

select ok(
  not has_table_privilege('anon', 'private.profile_badge_audit_log', 'SELECT')
    and not has_table_privilege('authenticated', 'private.profile_badge_audit_log', 'SELECT')
    and not has_table_privilege('authenticated', 'private.profile_badge_audit_log', 'INSERT')
    and not has_table_privilege('authenticated', 'private.profile_badge_audit_log', 'UPDATE')
    and not has_table_privilege('authenticated', 'private.profile_badge_audit_log', 'DELETE'),
  'aucun client ne peut lire ou modifier directement le journal'
);

select is(
  (
    select count(*)
    from pg_trigger
    where tgrelid = 'private.profile_badge_audit_log'::regclass
      and tgname = 'trg_profile_badge_audit_immutable'
      and not tgisinternal
  ),
  1::bigint,
  'le journal est protégé par un trigger append-only'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('91000000-0000-0000-0000-000000000001', 'badge-audit-admin@example.invalid', '{"first_name":"Admin","last_name":"Audit"}'::jsonb),
  ('91000000-0000-0000-0000-000000000002', 'badge-audit-player@example.invalid', '{"first_name":"Player","last_name":"Audit"}'::jsonb);

update public.profiles
set role = case
      when id = '91000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select ok(
  public.staff_create_badge(
    'audit_manual_test',
    'Badge audit test',
    '🏅',
    'Badge réservé au test du journal.',
    null,
    '#C0455B'
  ),
  'un administrateur peut créer le badge de test'
);

select ok(
  public.staff_award_badge(
    '91000000-0000-0000-0000-000000000002',
    'audit_manual_test'
  ),
  'un administrateur peut attribuer le badge manuel'
);

-- Même action, même état : ne doit ni réécrire la ligne ni ajouter un événement.
select ok(
  public.staff_award_badge(
    '91000000-0000-0000-0000-000000000002',
    'audit_manual_test'
  ),
  'une attribution manuelle répétée reste idempotente'
);
reset role;

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where event_type = 'award'
      and profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and actor_profile_id = '91000000-0000-0000-0000-000000000001'
      and source = 'manual'
      and metadata ->> 'reason' = 'manual_award'
      and state_before is null
      and state_after ->> 'source' = 'manual'
      and not is_backfill
  ),
  1::bigint,
  'l’attribution idempotente ne produit qu’un seul événement complet'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.staff_revoke_badge(
    '91000000-0000-0000-0000-000000000002',
    'audit_manual_test'
  ),
  'un administrateur peut retirer le badge manuel'
);
reset role;

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where event_type = 'revoke'
      and profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and actor_profile_id = '91000000-0000-0000-0000-000000000001'
      and source = 'manual'
      and metadata ->> 'reason' = 'manual_revoke'
      and state_before ->> 'source' = 'manual'
      and state_after is null
      and not is_backfill
  ),
  1::bigint,
  'le retrait produit un événement complet et durable'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.staff_award_badge(
    '91000000-0000-0000-0000-000000000002',
    'audit_manual_test'
  ),
  'le badge peut être réattribué après retrait'
);
reset role;

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where event_type = 'award'
      and profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and source = 'manual'
      and not is_backfill
  ),
  2::bigint,
  'la réattribution conserve les deux attributions dans l’historique'
);

select is(
  (
    select count(*)
    from public.profile_badges pb
    join public.badges b on b.id = pb.badge_id
    where pb.profile_id = '91000000-0000-0000-0000-000000000002'
      and b.code = 'audit_manual_test'
      and pb.source = 'manual'
      and pb.awarded_by = '91000000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'la réattribution restaure exactement un état courant'
);

select throws_ok(
  $$update private.profile_badge_audit_log
    set badge_name = 'Altéré'
    where badge_code = 'audit_manual_test'$$,
  '55000',
  'profile_badge_audit_log is append-only',
  'un événement existant ne peut pas être modifié'
);

select throws_ok(
  $$delete from private.profile_badge_audit_log
    where badge_code = 'audit_manual_test'$$,
  '55000',
  'profile_badge_audit_log is append-only',
  'un événement existant ne peut pas être supprimé'
);

select * from finish();
rollback;
