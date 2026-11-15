begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Les +1 sont exclusivement manuels ; aucune réponse ne crée de crédit.
select ok(
  to_regprocedure('private.normalize_waitlisted_withdrawal()') is null,
  'le traitement historique de désistement est supprimé'
);
select is(
  (
    select count(*)::integer
    from pg_trigger t
    where t.tgrelid = 'public.match_sport_participants'::regclass
      and t.tgname = 'normalize_waitlisted_withdrawal_before_update'
      and not t.tgisinternal
  ), 0,
  'aucun déclencheur historique ne peut effacer un +1 acquis'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '81000000-0000-0000-0000-000000000001',
    'waitlist-fix-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Fix"}'::jsonb
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    'waitlist-fix-player@example.invalid',
    '{"first_name":"Player","last_name":"Fix"}'::jsonb
  );

update public.profiles
set role = case
      when id = '81000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('82000000-0000-0000-0000-000000000001', '2096-2097', 'open');

insert into public.opponents(id, name)
values ('83000000-0000-0000-0000-000000000001', 'Fairness FC');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values (
  '84000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  'Player', 'Fix', false, true, 1,
  '81000000-0000-0000-0000-000000000002'
);

insert into public.matches(
  id, season_id, opponent_id, match_date, match_time, kickoff_at,
  location, planned_duration_minutes, status, created_by
)
values
  (
    '85000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    time '20:00', now() + interval '3 days',
    'domicile', 90, 'a_venir',
    '81000000-0000-0000-0000-000000000001'
  ),
  (
    '85000000-0000-0000-0000-000000000002',
    '82000000-0000-0000-0000-000000000001',
    '83000000-0000-0000-0000-000000000001',
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::date,
    ((now() + interval '2 hours') at time zone 'Europe/Paris')::time,
    now() + interval '2 hours',
    'exterieur', 90, 'a_venir',
    '81000000-0000-0000-0000-000000000001'
  );

insert into public.match_sport_workflows(
  match_id,
  availability_state,
  availability_opens_at,
  availability_opened_at,
  squad_size_limit,
  convocation_state,
  late_withdrawal_cutoff_at,
  created_by,
  updated_by
)
values
  (
    '85000000-0000-0000-0000-000000000001',
    'open', now() - interval '1 day', now() - interval '1 day',
    14, 'published', now() + interval '1 day',
    '81000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001'
  ),
  (
    '85000000-0000-0000-0000-000000000002',
    'open', now() - interval '1 day', now() - interval '1 day',
    14, 'published', now() - interval '1 minute',
    '81000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001'
  );

insert into public.match_sport_participants(
  id,
  match_id,
  season_player_id,
  availability_status,
  convocation_status,
  waitlist_turn_should_consume,
  waitlist_turn_state
)
values
  (
    '86000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000001',
    'available', 'not_convoked', true, 'pending'
  ),
  (
    '86000000-0000-0000-0000-000000000002',
    '85000000-0000-0000-0000-000000000002',
    '84000000-0000-0000-0000-000000000001',
    'available', 'not_convoked', true, 'pending'
  );

-- Avant J-1 midi, une mise en attente ne génère pas encore de +1.
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger
    where match_id = '85000000-0000-0000-0000-000000000001'),
  0, 'aucun +1 avant l ouverture de la période'
);

-- Après J-1 midi, une mise en attente ne crée pas davantage de crédit.
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger
    where match_id = '85000000-0000-0000-0000-000000000002'),
  0, 'aucun crédit automatique après J-1 midi'
);

update public.match_sport_participants
set availability_status = 'absent',
    availability_comment_private = 'Indisponible'
where match_id in (
  '85000000-0000-0000-0000-000000000001',
  '85000000-0000-0000-0000-000000000002'
);

select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger
    where match_id = '85000000-0000-0000-0000-000000000001'),
  0, 'le désistement avant la période ne crée aucun passage'
);
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger
    where match_id = '85000000-0000-0000-0000-000000000002'),
  0, 'le désistement ne crée aucun crédit automatique'
);

-- Les anciens chemins d'automatisation doivent rester sans effet, y compris
-- avec des crédits historiques encore en attente au moment de la bascule.
select is(
  (select count(*)::integer from cron.job
   where jobname = 'as-grinta-waitlist-credit-v2'),
  0, 'la tâche automatique des +1 est désinscrite'
);
select is(
  (select count(*)::integer from pg_trigger
   where not tgisinternal and tgname in (
     'trg_record_waitlist_presence', 'trg_void_waitlist_on_exemption',
     'trg_exempt_waitlist_when_all_fit', 'trg_exempt_waitlist_on_reschedule'
   )),
  0, 'les quatre déclencheurs de crédits automatiques sont retirés'
);

select private.ensure_sport_waitlist(
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_waitlist_manual_count(
    '84000000-0000-0000-0000-000000000001', 5
  )$$,
  'un admin peut ajouter les +1 manuellement'
);
reset role;
select is(
  (select manual_waitlist_count from public.sport_waitlist_entries
   where season_player_id = '84000000-0000-0000-0000-000000000001'),
  5, 'le compteur manuel est enregistré'
);
select ok(
  exists (select 1 from private.sport_admin_audit_log
    where action = 'set_waitlist_manual_count'
      and actor_profile_id = '81000000-0000-0000-0000-000000000001'
      and metadata ->> 'season_player_id' = '84000000-0000-0000-0000-000000000001'
      and metadata ->> 'new_count' = '5'),
  'la modification manuelle reste auditée'
);

-- Un ancien crédit attribué et un ancien crédit en attente sont conservés.
insert into private.sport_waitlist_passage_ledger
  (match_id, season_player_id, first_eligible_at, credited_at)
values
  ('85000000-0000-0000-0000-000000000001',
   '84000000-0000-0000-0000-000000000001', now() - interval '1 day', now()),
  ('85000000-0000-0000-0000-000000000002',
   '84000000-0000-0000-0000-000000000001', now() - interval '1 day', null);

select set_config('test.manual_ledger_before',
  (select jsonb_agg(to_jsonb(l) order by l.match_id)::text
   from private.sport_waitlist_passage_ledger l
   where l.season_player_id = '84000000-0000-0000-0000-000000000001'), true
);

update public.match_sport_participants
set availability_status = 'available', availability_comment_private = null,
    convocation_status = 'not_convoked'
where match_id = '85000000-0000-0000-0000-000000000002';
update public.matches
set kickoff_at = now() - interval '1 hour',
    match_date = ((now() - interval '1 hour') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '1 hour') at time zone 'Europe/Paris')::time
where id = '85000000-0000-0000-0000-000000000002';

select is(private.finalize_match_waitlist_turns_internal(
  '85000000-0000-0000-0000-000000000002', false
), 0, 'le coup d envoi ne crédite aucun +1');
select is(private.finalize_match_waitlist_turns_internal(
  '85000000-0000-0000-0000-000000000002', true
), 0, 'la finalisation forcée ne crédite aucun +1');
select is(private.finalize_due_waitlist_turns_for_season(
  '82000000-0000-0000-0000-000000000001'
), 0, 'le rattrapage de saison ne crédite aucun +1');
select is(private.process_due_waitlist_credits(), 0,
  'un ancien appel de la tâche ne crédite aucun +1');

set local role authenticated;
select is(public.admin_finalize_match_waitlist_turns(
  '85000000-0000-0000-0000-000000000002'
), 0, 'l ancienne RPC admin reste compatible sans créditer de +1');
select public.admin_get_sport_waitlist('82000000-0000-0000-0000-000000000001');
reset role;

-- Report, annulation, quota élargi et anciennes fonctions de révocation
-- doivent conserver les valeurs choisies par l'admin et l'ancien journal.
update public.matches
set kickoff_at = kickoff_at + interval '1 day',
    match_date = match_date + 1
where id = '85000000-0000-0000-0000-000000000001';
update public.matches set status = 'annule'
where id = '85000000-0000-0000-0000-000000000001';
update public.match_sport_workflows
set squad_size_limit = 30, waitlist_passages_exempt = true
where match_id = '85000000-0000-0000-0000-000000000001';
select is(private.void_match_waitlist_credits(
  '85000000-0000-0000-0000-000000000001'
), 0, 'l ancienne révocation ne retire aucun +1');
select is(
  (select manual_waitlist_count from public.sport_waitlist_entries
   where season_player_id = '84000000-0000-0000-0000-000000000001'),
  5, 'lecture, coup d envoi, report, quota et annulation préservent le compteur'
);
select is(
  (select jsonb_agg(to_jsonb(l) order by l.match_id)
   from private.sport_waitlist_passage_ledger l
   where l.season_player_id = '84000000-0000-0000-0000-000000000001'),
  current_setting('test.manual_ledger_before')::jsonb,
  'les crédits historiques sont conservés sans rattrapage ni révocation'
);

set local role authenticated;
select lives_ok(
  $$select public.admin_set_waitlist_manual_count(
    '84000000-0000-0000-0000-000000000001', 4
  )$$, 'un admin peut aussi retirer un +1 manuellement'
);
reset role;
select is(
  (select manual_waitlist_count from public.sport_waitlist_entries
   where season_player_id = '84000000-0000-0000-0000-000000000001'),
  4, 'le retrait manuel est enregistré'
);

select set_config('request.jwt.claims',
  '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_waitlist_manual_count(
    '84000000-0000-0000-0000-000000000001', 99
  )$$, '42501', 'Active administrator role required',
  'un joueur ne peut pas modifier les +1'
);
reset role;
select is(
  (select manual_waitlist_count from public.sport_waitlist_entries
   where season_player_id = '84000000-0000-0000-0000-000000000001'),
  4, 'le refus joueur préserve le compteur'
);

select * from finish();
rollback;
