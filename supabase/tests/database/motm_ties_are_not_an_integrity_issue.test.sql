begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Une égalité au vote élit tous les joueurs à égalité : c'est la règle du club,
-- appliquée par private.close_match_motm_election. Un match archivé comptant
-- plusieurs Hommes du match est donc un résultat normal, et le rapport
-- d'intégrité ne doit pas le compter comme une anomalie.

insert into auth.users (id, email, raw_user_meta_data)
values (
  '96000000-0000-0000-0000-000000000001',
  'motm-tie-regression@example.invalid',
  '{"first_name":"Motm","last_name":"Tie"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '96000000-0000-0000-0000-000000000001';

-- Total d'anomalies avant l'ajout du match à double Homme du match.
select set_config(
  'request.jwt.claims',
  '{"sub":"96000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.motm_tie_issues_before',
  (public.staff_app_integrity_report()->>'total_issues'),
  true
);
reset role;

insert into public.opponents (id, name)
values ('96000000-0000-0000-0000-000000000020', 'Egalite HDM FC');

insert into public.historical_match_scores (
  id, opponent_id, match_date, score_as_grinta, score_adverse, is_home
)
values (
  '96000000-0000-0000-0000-000000000100',
  '96000000-0000-0000-0000-000000000020',
  date '2097-05-11', 2, 1, true
);

-- Deux joueurs sont élus Hommes du match sur cette rencontre.
insert into public.historical_match_details (
  match_id, formation, field_players, bench_players, present_names, scorers, motm_names
)
values (
  '96000000-0000-0000-0000-000000000100',
  '4-4-2',
  '[]'::jsonb,
  '[]'::jsonb,
  '["Egalite Premier","Egalite Second"]'::jsonb,
  '[{"name":"Egalite Premier","goals":1},{"name":"Egalite Second","goals":1}]'::jsonb,
  '["Egalite Premier","Egalite Second"]'::jsonb
);

select is(
  (
    select count(*)
    from public.historical_match_players
    where match_id = '96000000-0000-0000-0000-000000000100'::uuid
      and is_motm
  ),
  2::bigint,
  'un match archivé conserve les deux Hommes du match élus à égalité'
);

set local role authenticated;

select is(
  (
    select count(*)
    from jsonb_array_elements(public.staff_app_integrity_report()->'checks') check_row
    where check_row->>'check' = 'historical_multiple_motm'
  ),
  0::bigint,
  'le rapport d’intégrité ne comporte plus de contrôle sur les Hommes du match multiples'
);

select is(
  (public.staff_app_integrity_report()->>'total_issues')::bigint,
  current_setting('test.motm_tie_issues_before')::bigint,
  'une égalité au vote n’ajoute aucune anomalie au rapport d’intégrité'
);

reset role;
select * from finish();

rollback;
