begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Identités et données exclusivement réservées aux tests. La transaction finale
-- est annulée ; aucune ligne ne subsiste dans la base locale.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('10000000-0000-0000-0000-000000000001', 'admin-tests@example.invalid', '{"first_name":"Admin","last_name":"Tests"}'::jsonb),
  ('10000000-0000-0000-0000-000000000002', 'alice-tests@example.invalid', '{"first_name":"Alice","last_name":"Tests"}'::jsonb),
  ('10000000-0000-0000-0000-000000000003', 'bruno-tests@example.invalid', '{"first_name":"Bruno","last_name":"Tests"}'::jsonb),
  ('10000000-0000-0000-0000-000000000004', 'inactive-tests@example.invalid', '{"first_name":"Inactif","last_name":"Tests"}'::jsonb);

update public.profiles
set role = case
      when id = '10000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = '10000000-0000-0000-0000-000000000004' then 'pending'
      else 'active'
    end,
    updated_at = now()
where id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000004'
);

insert into public.seasons (id, name, status)
values ('20000000-0000-0000-0000-000000000001', '2098-2099', 'open');

insert into public.opponents (id, name)
values ('30000000-0000-0000-0000-000000000001', 'Adversaire Tests');

insert into public.season_players (
  id, season_id, first_name, last_name, is_goalkeeper, is_active, position
)
values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Gardien', 'Tests', true, true, 1),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'Buteur', 'Tests', false, true, 2);

insert into public.season_predictions (
  season_id, predictor_profile_id, season_player_id,
  category, predicted_value_30, is_filled
)
select
  sp.season_id,
  p.id,
  sp.id,
  case when sp.is_goalkeeper then 'clean_sheets' else 'buts' end,
  0,
  false
from public.season_players sp
cross join public.profiles p
where sp.season_id = '20000000-0000-0000-0000-000000000001'
  and sp.is_active
  and p.status = 'active';

-- Match d'abord ouvert : les pronostics historiques sont donc acceptés par le
-- garde serveur. Il est ensuite marqué terminé pour créditer un x2 à Alice.
insert into public.matches (
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
values (
  '50000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  date '2097-12-01', time '20:00', 'domicile', 90, 'a_venir',
  '10000000-0000-0000-0000-000000000001'
);

insert into public.match_odds (
  match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse
)
values ('50000000-0000-0000-0000-000000000001', 2.10, 3.20, 3.50);

update public.match_predictions
set predicted_score_as_grinta = case
      when profile_id = '10000000-0000-0000-0000-000000000002' then 2
      else 0
    end,
    predicted_score_adverse = 1,
    is_filled = true,
    updated_at = now()
where match_id = '50000000-0000-0000-0000-000000000001'
  and profile_id in (
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000003'
  );

update public.matches
set status = 'termine',
    score_as_grinta = 2,
    score_adverse = 1,
    result_validated_at = now(),
    predictions_closed_at = now(),
    updated_at = now()
where id = '50000000-0000-0000-0000-000000000001';

-- Match situé dans la fenêtre H-5.
insert into public.matches (
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
select
  '50000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  ((now() at time zone 'Europe/Paris') + interval '4 minutes')::date,
  ((now() at time zone 'Europe/Paris') + interval '4 minutes')::time,
  'domicile', 90, 'a_venir',
  '10000000-0000-0000-0000-000000000001';

-- Deux matchs ouverts dans un ordre déterministe.
insert into public.matches (
  id, season_id, opponent_id, match_date, match_time, location,
  planned_duration_minutes, status, created_by
)
values
  ('50000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-01-10', time '20:00', 'domicile', 90, 'a_venir', '10000000-0000-0000-0000-000000000001'),
  ('50000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-01-11', time '20:00', 'exterieur', 90, 'a_venir', '10000000-0000-0000-0000-000000000001');

insert into public.match_odds (
  match_id, odds_victoire_as_grinta, odds_nul, odds_victoire_adverse
)
values
  ('50000000-0000-0000-0000-000000000002', 2.10, 3.20, 3.50),
  ('50000000-0000-0000-0000-000000000003', 2.10, 3.20, 3.50),
  ('50000000-0000-0000-0000-000000000004', 2.20, 3.10, 3.40);

-- Authentification et RLS.
set local role anon;
select throws_ok(
  $$select count(*) from public.matches$$,
  '42501',
  'un appel anonyme ne peut pas lire les matchs'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*) from public.match_predictions where match_id = '50000000-0000-0000-0000-000000000003'),
  1::bigint,
  'un utilisateur ne voit que son pronostic sur un match non révélé'
);
select is(
  (select count(*) from public.match_predictions where match_id = '50000000-0000-0000-0000-000000000003' and profile_id = '10000000-0000-0000-0000-000000000003'),
  0::bigint,
  'le pronostic non révélé d’un autre utilisateur est masqué'
);
select is(
  (select count(*) from public.match_predictions where match_id = '50000000-0000-0000-0000-000000000001'),
  3::bigint,
  'les pronostics de tous les profils actifs sont révélés après le résultat'
);
select throws_ok(
  $$update public.profiles set role = 'admin' where id = '10000000-0000-0000-0000-000000000002'$$,
  '42501',
  'un utilisateur ne peut pas s’accorder le rôle administrateur'
);

update public.match_predictions
set predicted_score_as_grinta = 99
where match_id = '50000000-0000-0000-0000-000000000003'
  and profile_id = '10000000-0000-0000-0000-000000000003';
reset role;
select is(
  (select predicted_score_as_grinta from public.match_predictions where match_id = '50000000-0000-0000-0000-000000000003' and profile_id = '10000000-0000-0000-0000-000000000003'),
  0,
  'la RLS empêche la modification du pronostic d’un autre utilisateur'
);

-- Premier match et compte actif/inactif.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.save_match_prediction('50000000-0000-0000-0000-000000000003', 1, 0, false),
  'le premier match ouvert accepte le pronostic'
);
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000004', 1, 0, false)$$,
  '22023',
  'le deuxième match est refusé tant que le premier reste ouvert'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000003', 0, 0, false)$$,
  '42501',
  'un profil inactif ne peut pas pronostiquer'
);

-- Portefeuille x2.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000003', 1, 1, true)$$,
  '23514',
  'un x2 ne peut pas être dépensé sans crédit disponible'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.save_match_prediction('50000000-0000-0000-0000-000000000003', 1, 0, true),
  'un crédit x2 gagné peut être dépensé une fois'
);
select throws_ok(
  $$select public.close_match_predictions('50000000-0000-0000-0000-000000000003')$$,
  '42501',
  'un pronostiqueur ne peut pas fermer les pronostics'
);

-- Fermeture manuelle, non-redépense et H-5.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.close_match_predictions('50000000-0000-0000-0000-000000000003'),
  'un administrateur peut fermer les pronostics'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000003', 2, 0, false)$$,
  '22023',
  'un pronostic fermé manuellement ne peut plus être modifié'
);
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000004', 2, 1, true)$$,
  '23514',
  'le même crédit x2 ne peut pas être dépensé sur un second match'
);
select ok(
  public.save_match_prediction('50000000-0000-0000-0000-000000000004', 2, 1, false),
  'le deuxième match devient pronostiquable après fermeture du premier'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.close_match_predictions('50000000-0000-0000-0000-000000000004'),
  'le staff peut fermer le deuxième match'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.save_match_prediction('50000000-0000-0000-0000-000000000002', 0, 0, false)$$,
  'P0002',
  'un match situé à moins de cinq minutes est exclu de la fenêtre de pronostic'
);

-- Création réservée au staff et match+cotes atomiques.
select throws_ok(
  $$select public.create_match_with_odds('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-02-01', time '20:00', 'domicile', 2.10, 3.20, 3.50)$$,
  '42501',
  'un pronostiqueur ne peut pas créer de match'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.create_match_with_odds('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-02-01', time '20:00', 'domicile', 2.10, 3.20, 3.50)$$,
  'un administrateur peut créer un match avec ses cotes'
);
reset role;
select is(
  (select count(*) from public.matches m join public.match_odds mo on mo.match_id = m.id where m.match_date = date '2098-02-01' and mo.odds_victoire_as_grinta = 2.10 and mo.odds_nul = 3.20 and mo.odds_victoire_adverse = 3.50),
  1::bigint,
  'la création persiste le match et les trois cotes ensemble'
);

-- Modification réservée au staff et rollback si l’écriture des cotes échoue.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.update_match_with_odds((select id from public.matches where match_date = date '2098-02-01'), '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-02-01', time '20:30', 'exterieur', 'a_venir', 2.20, 3.30, 4.40)$$,
  '42501',
  'un pronostiqueur ne peut pas modifier un match'
);

reset role;
create or replace function public.test_reject_odds_write()
returns trigger
language plpgsql
as $function$
begin
  raise exception 'forced odds failure' using errcode = '23514';
end;
$function$;
create trigger test_reject_odds_write
before update on public.match_odds
for each row execute function public.test_reject_odds_write();

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.update_match_with_odds((select id from public.matches where match_date = date '2098-02-01'), '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', date '2098-02-01', time '20:30', 'exterieur', 'a_venir', 2.20, 3.30, 4.40)$$,
  '23514',
  'une erreur lors des cotes annule toute la modification'
);
reset role;
select is(
  (select concat_ws('|', m.location, to_char(m.match_time, 'HH24:MI'), mo.odds_victoire_as_grinta::text, mo.odds_nul::text, mo.odds_victoire_adverse::text) from public.matches m join public.match_odds mo on mo.match_id = m.id where m.match_date = date '2098-02-01'),
  'domicile|20:00|2.10|3.20|3.50',
  'aucun demi-état ne subsiste après l’échec de modification'
);
drop trigger test_reject_odds_write on public.match_odds;
drop function public.test_reject_odds_write();

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.update_match_with_odds(
    (select id from public.matches where match_date = date '2098-02-01'),
    '20000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    date '2098-02-01', time '20:30', 'exterieur', 'a_venir', 2.20, 3.30, 4.40
  ),
  'le staff peut modifier le match et les cotes atomiquement'
);
reset role;
select is(
  (select concat_ws('|', m.location, to_char(m.match_time, 'HH24:MI'), mo.odds_victoire_as_grinta::text, mo.odds_nul::text, mo.odds_victoire_adverse::text) from public.matches m join public.match_odds mo on mo.match_id = m.id where m.match_date = date '2098-02-01'),
  'exterieur|20:30|2.20|3.30|4.40',
  'la modification réussie met à jour les deux tables'
);

-- Finalisation réservée au staff, rollback complet, puis succès.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.finalize_match_postgame_with_lineup((select id from public.matches where match_date = date '2098-02-01'), 0, '[]'::jsonb, '40000000-0000-0000-0000-000000000001', 0, array['40000000-0000-0000-0000-000000000001']::uuid[], '40000000-0000-0000-0000-000000000001')$$,
  '42501',
  'un pronostiqueur ne peut pas finaliser un match'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.finalize_match_postgame_with_lineup((select id from public.matches where match_date = date '2098-02-01'), 0, jsonb_build_array(jsonb_build_object('season_player_id', '40000000-0000-0000-0000-000000000002', 'goals', 2)), '40000000-0000-0000-0000-000000000001', 1, array['40000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002']::uuid[], '40000000-0000-0000-0000-000000000001')$$,
  '22023',
  'une incohérence de score fait échouer la finalisation'
);
reset role;
select is(
  (select concat_ws('|', m.status, count(distinct a.season_player_id)::text, count(distinct mvp.season_player_id)::text) from public.matches m left join public.match_attendance a on a.match_id = m.id left join public.match_man_of_match mvp on mvp.match_id = m.id where m.match_date = date '2098-02-01' group by m.id, m.status),
  'a_venir|0|0',
  'l’échec de finalisation annule présence, MVP et résultat'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select ok(
  public.finalize_match_postgame_with_lineup(
    (select id from public.matches where match_date = date '2098-02-01'),
    0,
    '[]'::jsonb,
    '40000000-0000-0000-0000-000000000001',
    0,
    array['40000000-0000-0000-0000-000000000001']::uuid[],
    '40000000-0000-0000-0000-000000000001'
  ),
  'un administrateur peut finaliser un match valide'
);
reset role;
select is(
  (select concat_ws('|', m.status, m.score_as_grinta::text, m.score_adverse::text, count(distinct a.season_player_id)::text, count(distinct mvp.season_player_id)::text, count(distinct case when stats.clean_sheet then stats.season_player_id end)::text) from public.matches m left join public.match_attendance a on a.match_id = m.id left join public.match_man_of_match mvp on mvp.match_id = m.id left join public.match_player_stats stats on stats.match_id = m.id where m.match_date = date '2098-02-01' group by m.id, m.status, m.score_as_grinta, m.score_adverse),
  'termine|0|0|1|1|1',
  'la finalisation enregistre résultat, présence, MVP et clean sheet'
);

-- Rapport d’intégrité réservé au staff.
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.staff_app_integrity_report()$$,
  '42501',
  'un pronostiqueur ne peut pas appeler le rapport d’intégrité'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  (public.staff_app_integrity_report()->>'healthy')::boolean,
  true,
  'le rapport d’intégrité considère les données de test saines'
);
select is(
  (public.staff_app_integrity_report()->>'total_issues')::bigint,
  0::bigint,
  'le rapport d’intégrité ne remonte aucune anomalie'
);

reset role;
select * from finish();
rollback;
