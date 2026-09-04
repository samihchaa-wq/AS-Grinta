begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Dans le Calendrier, un joueur est appelé par son surnom. Les matchs archivés
-- gardent le nom écrit sur la vieille feuille de match : la lecture d'une
-- archive renvoie donc, à côté des photos, l'identité du club de chaque joueur
-- reconnu (surnom sinon prénom, plus l'initiale du nom de famille).

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'e1000000-0000-0000-0000-000000000001',
    'archive-surnom@example.invalid',
    '{"first_name":"Olivierarchive","last_name":"Milletarchive"}'::jsonb
  ),
  (
    'e1000000-0000-0000-0000-000000000002',
    'archive-sans-surnom@example.invalid',
    '{"first_name":"Simonarchive","last_name":"Reisarchive"}'::jsonb
  );

update public.profiles
set role = 'pronostiqueur',
    status = 'active',
    surnom = case
      when id = 'e1000000-0000-0000-0000-000000000001'::uuid then 'Poulain'
      else surnom
    end,
    updated_at = now()
where id in (
  'e1000000-0000-0000-0000-000000000001'::uuid,
  'e1000000-0000-0000-0000-000000000002'::uuid
);

insert into public.opponents(id, name)
values ('e2000000-0000-0000-0000-000000000001', 'Adversaire test surnoms');

insert into public.historical_match_scores(
  id, opponent_id, match_date, score_as_grinta, score_adverse, is_home
)
values (
  'e3000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000001',
  date '2097-05-01', 2, 1, true
);

insert into public.historical_match_details(
  match_id, formation, field_players, bench_players, present_names, scorers, motm_names
)
values (
  'e3000000-0000-0000-0000-000000000001',
  '4-4-2',
  '[
     {"name":"Olivierarchive Milletarchive","is_gk":false,"x_pct":30,"y_pct":40},
     {"name":"Simonarchive Reisarchive","is_gk":false,"x_pct":60,"y_pct":40}
   ]'::jsonb,
  '[]'::jsonb,
  '["Olivierarchive Milletarchive","Simonarchive Reisarchive"]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb
);

-- L'archive relie chaque nom de feuille de match à l'identité canonique du
-- joueur ; c'est ce lien qui permet de retrouver le surnom du compte.
update public.profiles profile
set player_id = archive.player_id
from public.historical_match_players archive
where archive.match_id = 'e3000000-0000-0000-0000-000000000001'::uuid
  and archive.source_name = 'Olivierarchive Milletarchive'
  and profile.id = 'e1000000-0000-0000-0000-000000000001'::uuid;

update public.profiles profile
set player_id = archive.player_id
from public.historical_match_players archive
where archive.match_id = 'e3000000-0000-0000-0000-000000000001'::uuid
  and archive.source_name = 'Simonarchive Reisarchive'
  and profile.id = 'e1000000-0000-0000-0000-000000000002'::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

create or replace function pg_temp.archive_identity(p_source text, p_key text)
returns text
language sql
stable
as $function$
  select detail.display_names -> p_source ->> p_key
  from public.get_historical_match_detail(
    'e3000000-0000-0000-0000-000000000001'::uuid
  ) detail;
$function$;

select is(
  pg_temp.archive_identity('Olivierarchive Milletarchive', 'name'),
  'Poulain',
  'un joueur d’archive surnommé est rendu sous son surnom'
);

select is(
  pg_temp.archive_identity('Olivierarchive Milletarchive', 'last_initial'),
  'M',
  'son initiale de nom de famille accompagne le surnom'
);

select is(
  pg_temp.archive_identity('Simonarchive Reisarchive', 'name'),
  'Simonarchive',
  'sans surnom, le prénom du compte est rendu'
);

select is(
  pg_temp.archive_identity('Simonarchive Reisarchive', 'last_initial'),
  'R',
  'l’initiale suit aussi les joueurs sans surnom'
);

reset role;

select * from finish();
rollback;
