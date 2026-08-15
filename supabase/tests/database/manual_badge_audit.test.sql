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
    first_name = case
      when id = '91000000-0000-0000-0000-000000000001' then 'Admin Audit'
      else 'Joueur Audit'
    end,
    surnom = null,
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
      and action = 'award'
      and actor_profile_id = '91000000-0000-0000-0000-000000000001'
      and profile_label = 'Joueur Audit'
      and actor_label = 'Admin Audit'
  ),
  1::bigint,
  'l attribution manuelle est journalisee avec acteur et cible'
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
  ),
  2::bigint,
  'attribution et revocation restent toutes les deux dans le journal'
);

select is(
  (
    select metadata ->> 'previous_source'
    from private.profile_badge_audit_log
    where profile_id = '91000000-0000-0000-0000-000000000002'
      and badge_code = 'audit_manual_test'
      and action = 'revoke'
    order by id desc
    limit 1
  ),
  'manual',
  'la revocation conserve la source precedente'
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
  'Badge audit log is append-only',
  'le journal ne peut pas etre modifie'
);

select throws_ok(
  $$
    delete from private.profile_badge_audit_log
    where badge_code = 'audit_manual_test'
  $$,
  '55000',
  'Badge audit log is append-only',
  'le journal ne peut pas etre efface'
);

set local role authenticated;
select throws_ok(
  $$select count(*) from private.profile_badge_audit_log$$,
  '42501',
  'permission denied for table profile_badge_audit_log',
  'un client authentifie ne peut pas lire directement le journal prive'
);
reset role;

select * from finish();
rollback;
