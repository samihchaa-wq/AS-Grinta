begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values
  ('91000000-0000-0000-0000-000000000001', 'badge-audit-admin@example.invalid', '{"first_name":"Admin","last_name":"Audit"}'::jsonb),
  ('91000000-0000-0000-0000-000000000002', 'badge-audit-target@example.invalid', '{"first_name":"Joueur","last_name":"Audit"}'::jsonb);

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

insert into public.badges (
  id, code, name, description, emoji, family, auto, kind, category, sort_order
) values (
  '92000000-0000-0000-0000-000000000001',
  'audit_manual_test',
  'Badge audit test',
  'Fixture du journal de badges manuels',
  '🏅',
  'joueur',
  false,
  'custom',
  'faits_de_jeu',
  9999
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
  'un administrateur peut attribuer le badge de test'
);

reset role;

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and event_type = 'award'
      and actor_profile_id = '91000000-0000-0000-0000-000000000001'
      and not is_backfill
  ),
  1::bigint,
  'l attribution manuelle est journalisee avec son acteur'
);

set local role authenticated;
select ok(
  public.staff_revoke_badge(
    '91000000-0000-0000-0000-000000000002',
    'audit_manual_test'
  ),
  'un administrateur peut retirer le badge de test'
);
reset role;

select is(
  (
    select count(*)
    from private.profile_badge_audit_log
    where profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and event_type in ('award', 'revoke')
  ),
  2::bigint,
  'attribution et revocation restent toutes les deux dans le journal'
);

select is(
  (
    select count(*)
    from public.profile_badges
    where profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_id = '92000000-0000-0000-0000-000000000001'
  ),
  0::bigint,
  'le badge manuel reste retire apres la revocation'
);

select throws_ok(
  $$
    update private.profile_badge_audit_log
    set badge_name = 'Modifie'
    where badge_code = 'audit_manual_test'
  $$,
  '55000',
  'profile_badge_audit_log is append-only',
  'le journal ne peut pas etre modifie'
);

select throws_ok(
  $$
    delete from private.profile_badge_audit_log
    where badge_code = 'audit_manual_test'
  $$,
  '55000',
  'profile_badge_audit_log is append-only',
  'le journal ne peut pas etre efface'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.profile_badge_audit_log',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.profile_badge_audit_log',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.profile_badge_audit_log',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.profile_badge_audit_log',
    'DELETE'
  ),
  'un client authentifie ne peut ni lire ni modifier le journal prive'
);

select * from finish();
rollback;
