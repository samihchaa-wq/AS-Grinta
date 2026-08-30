begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data) values
('4d000000-0000-0000-0000-000000000001','delete-lock-admin@example.invalid','{"first_name":"Delete","last_name":"Admin"}'::jsonb),
('4d000000-0000-0000-0000-000000000002','delete-lock-player@example.invalid','{"first_name":"Delete","last_name":"Player"}'::jsonb);

update public.profiles
set role = case when id = '4d000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status = 'active',
    updated_at = now()
where id in ('4d000000-0000-0000-0000-000000000001','4d000000-0000-0000-0000-000000000002');

insert into public.seasons(id, name, status)
values ('4d000000-0000-0000-0000-000000000010', '2096-2097', 'open');

insert into public.opponents(id, name) values
('4d000000-0000-0000-0000-000000000011','Adversaire suppression live'),
('4d000000-0000-0000-0000-000000000012','Adversaire suppression passe');

-- Un match dont le coup d'envoi est passé depuis moins de 24 h : il doit
-- rester supprimable par le staff même si le Live a été ouvert.
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, match_type, created_by
) values (
  '4d000000-0000-0000-0000-000000000020',
  '4d000000-0000-0000-0000-000000000010',
  '4d000000-0000-0000-0000-000000000011',
  ((now() at time zone 'Europe/Paris') - interval '1 hour')::date,
  ((now() at time zone 'Europe/Paris') - interval '1 hour')::time,
  'domicile', 90, 'a_venir', 'championnat',
  '4d000000-0000-0000-0000-000000000001'
);

insert into public.match_live_sessions(
  match_id, state, planned_duration_minutes, started_at, updated_by
) values (
  '4d000000-0000-0000-0000-000000000020', 'paused', 90, now() - interval '1 hour',
  '4d000000-0000-0000-0000-000000000001'
);

-- Un match dont le coup d'envoi remonte à plus de 24 h doit désormais être
-- conservé, même pour le staff.
insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, match_type, created_by
) values (
  '4d000000-0000-0000-0000-000000000021',
  '4d000000-0000-0000-0000-000000000010',
  '4d000000-0000-0000-0000-000000000012',
  (now() at time zone 'Europe/Paris')::date - 30,
  '20:00'::time, 'exterieur', 90, 'a_venir', 'championnat',
  '4d000000-0000-0000-0000-000000000001'
);

insert into public.match_sport_workflows(
  match_id, availability_opens_at, created_by, updated_by
) values (
  '4d000000-0000-0000-0000-000000000021', now() - interval '40 days',
  '4d000000-0000-0000-0000-000000000001',
  '4d000000-0000-0000-0000-000000000001'
);

insert into public.match_compositions(
  match_id, formation_code, status, version, last_modified_by
) values (
  '4d000000-0000-0000-0000-000000000021', '4-4-2', 'draft', 0,
  '4d000000-0000-0000-0000-000000000001'
);

update public.matches
set status = 'termine',
    score_as_grinta = 2,
    score_adverse = 1,
    result_validated_at = now() - interval '3 days',
    updated_at = now()
where id = '4d000000-0000-0000-0000-000000000021';

-- Toute suppression directe reste refusée : seule la RPC vérifiée du staff
-- passe le garde-fou.
select throws_ok(
  $$delete from public.matches where id = '4d000000-0000-0000-0000-000000000020'$$,
  '22023',
  'une suppression directe reste refusée après l’ouverture du Live'
);

select throws_ok(
  $$delete from public.matches where id = '4d000000-0000-0000-0000-000000000021'$$,
  '22023',
  'une suppression directe reste refusée sur un match passé'
);

set local role authenticated;
set local request.jwt.claim.sub = '4d000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claims',
  '{"sub":"4d000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true);

select throws_ok(
  $$select public.delete_match('4d000000-0000-0000-0000-000000000020')$$,
  '42501',
  'un pronostiqueur ne peut pas supprimer un match'
);

set local request.jwt.claim.sub = '4d000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims',
  '{"sub":"4d000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true);

select is(
  public.delete_match('4d000000-0000-0000-0000-000000000020'),
  true,
  'le staff supprime un match moins de 24 h après le coup d’envoi'
);

select throws_ok(
  $$select public.delete_match('4d000000-0000-0000-0000-000000000021')$$,
  '22023',
  'Un match ne peut être supprimé que jusqu’à 24 heures après son coup d’envoi.',
  'le staff ne peut plus supprimer un match plus de 24 h après le coup d’envoi'
);

reset role;
set local request.jwt.claim.sub = '';
select set_config('request.jwt.claims', '', true);

select is(
  (select count(*)::int from public.matches
   where id = '4d000000-0000-0000-0000-000000000020'),
  0,
  'le match récent a bien été supprimé'
);

select is(
  (select count(*)::int from public.matches
   where id = '4d000000-0000-0000-0000-000000000021'),
  1,
  'le match ancien est conservé'
);

select * from finish();
rollback;
