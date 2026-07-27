begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'e3000000-0000-0000-0000-000000000001',
    'matrix-admin@example.invalid',
    '{"first_name":"Matrix","last_name":"Admin"}'::jsonb
  ),
  (
    'e3000000-0000-0000-0000-000000000002',
    'matrix-player@example.invalid',
    '{"first_name":"Matrix","last_name":"Player"}'::jsonb
  ),
  (
    'e3000000-0000-0000-0000-000000000003',
    'matrix-pending@example.invalid',
    '{"first_name":"Matrix","last_name":"Pending"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'e3000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = 'e3000000-0000-0000-0000-000000000003' then 'pending'
      else 'active'
    end,
    updated_at = now()
where id in (
  'e3000000-0000-0000-0000-000000000001',
  'e3000000-0000-0000-0000-000000000002',
  'e3000000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('e3100000-0000-0000-0000-000000000001', '2110-2111', 'open');

insert into public.opponents(id, name)
values ('e3200000-0000-0000-0000-000000000001', 'Matrice FC');

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
values (
  'e3300000-0000-0000-0000-000000000001',
  'e3100000-0000-0000-0000-000000000001',
  'e3200000-0000-0000-0000-000000000001',
  date '2110-09-01', time '20:00', 'domicile', 90, 'a_venir',
  'e3000000-0000-0000-0000-000000000001'
);

select ok(
  not has_table_privilege('anon', 'public.profiles', 'SELECT')
  and not has_table_privilege('anon', 'public.matches', 'SELECT')
  and not has_table_privilege('anon', 'public.match_predictions', 'SELECT')
  and not has_table_privilege('anon', 'public.season_predictions', 'SELECT')
  and not has_table_privilege('anon', 'public.push_subscriptions', 'SELECT')
  and not has_table_privilege(
    'anon', 'public.match_sport_motm_votes', 'SELECT'
  ),
  'un visiteur anonyme ne reçoit aucun droit de lecture sur les données privées essentielles'
);

set local role anon;
select throws_ok(
  $$select count(*) from public.matches$$,
  '42501',
  'un visiteur ne peut pas lire les matchs directement'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(private.is_active_profile(), false, 'un compte en attente reste inactif côté serveur');
select is(private.is_admin(), false, 'un compte en attente ne reçoit aucun droit administrateur');
select is(
  (select count(*) from public.matches),
  0::bigint,
  'la RLS masque les matchs à un compte en attente'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(private.is_active_profile(), true, 'un joueur validé est actif côté serveur');
select is(private.is_admin(), false, 'un joueur validé ne devient pas administrateur');
select is(
  (select count(*) from public.matches),
  1::bigint,
  'un joueur actif peut lire les matchs'
);
select throws_ok(
  $$select public.close_match_predictions('e3300000-0000-0000-0000-000000000001')$$,
  '42501',
  'un joueur ne peut pas lancer une action administrateur'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(private.is_active_profile(), true, 'un administrateur validé est actif');
select is(private.is_admin(), true, 'le rôle administrateur est reconnu côté serveur');
select is(
  (select count(*) from public.matches),
  1::bigint,
  'un administrateur peut lire les matchs'
);
select ok(
  public.close_match_predictions('e3300000-0000-0000-0000-000000000001'),
  'un administrateur peut exécuter l’action protégée'
);

reset role;
select * from finish();
rollback;
