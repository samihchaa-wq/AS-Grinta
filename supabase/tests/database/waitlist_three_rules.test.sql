begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Test sur base isolée uniquement : trois présents, deux places.
insert into auth.users(id,email,raw_user_meta_data) values
('b5100000-0000-0000-0000-000000000001','w3r-admin@example.invalid','{"first_name":"Admin"}'::jsonb),
('b5100000-0000-0000-0000-000000000002','w3r-a@example.invalid','{"first_name":"A"}'::jsonb),
('b5100000-0000-0000-0000-000000000003','w3r-b@example.invalid','{"first_name":"B"}'::jsonb),
('b5100000-0000-0000-0000-000000000004','w3r-c@example.invalid','{"first_name":"C"}'::jsonb);

update public.profiles
set role = case when id = 'b5100000-0000-0000-0000-000000000001'
  then 'admin' else 'pronostiqueur' end,
  status = 'active', updated_at = now()
where id in (
'b5100000-0000-0000-0000-000000000001',
'b5100000-0000-0000-0000-000000000002',
'b5100000-0000-0000-0000-000000000003',
'b5100000-0000-0000-0000-000000000004');

insert into public.seasons(id,name,status)
values ('b5200000-0000-0000-0000-000000000001','2094-2095','open');
insert into public.opponents(id,name)
values ('b5300000-0000-0000-0000-000000000001','Three Rules FC');
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
) values
('b5400000-0000-0000-0000-000000000001',
 'b5200000-0000-0000-0000-000000000001',
 'Alice','Armand',false,true,1,'b5100000-0000-0000-0000-000000000002'),
('b5400000-0000-0000-0000-000000000002',
 'b5200000-0000-0000-0000-000000000001',
 'Bruno','Bernard',false,true,2,'b5100000-0000-0000-0000-000000000003'),
('b5400000-0000-0000-0000-000000000003',
 'b5200000-0000-0000-0000-000000000001',
 'Charles','Charles',false,true,3,'b5100000-0000-0000-0000-000000000004');

update private.app_feature_flags
set enabled = true,updated_at=now(),
  updated_by='b5100000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"b5100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config('test.waitlist_three_match',
  public.create_match_with_odds_and_sport_limit(
    'b5200000-0000-0000-0000-000000000001',
    'b5300000-0000-0000-0000-000000000001',
    ((now()+interval '1 hour') at time zone 'Europe/Paris')::date,
    ((now()+interval '1 hour') at time zone 'Europe/Paris')::time,
    'domicile',2.10,3.20,2.90,2
  )::text,true
);
reset role;

select ok(
  private.waitlist_credit_cutoff(m.kickoff_at) <= now()
  and now() < m.kickoff_at,
  'Le créneau J-1 12 h jusqu au coup d envoi est actif'
) from public.matches m
where m.id = current_setting('test.waitlist_three_match')::uuid;

update public.match_sport_participants
set availability_status='available',updated_at=now()
where match_id=current_setting('test.waitlist_three_match')::uuid
  and is_eligible and season_player_id is not null;

select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);

select is(
  (select count(*)::integer
   from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.convocation_status='convoked'),
  2,'Deux convoqués pour deux places'
);

select is(
  (select p.convocation_status::text
   from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'not_convoked','Alice en haut de liste est en attente'
);
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger l
   where l.match_id=current_setting('test.waitlist_three_match')::uuid),
  1,'Une seule trace pour le joueur en attente'
);

-- A passe d'attente à convoqué après le créneau : son droit reste acquis.
update public.match_sport_participants p
set availability_status='absent',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000003';

select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
   and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'convoked','Alice promue après une absence'
);
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger l
   where l.match_id=current_setting('test.waitlist_three_match')::uuid
     and l.season_player_id='b5400000-0000-0000-0000-000000000001'),
  1,'Le passage acquis survit à la promotion'
);

update public.match_sport_participants p
set availability_status='available',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000003';

select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);
select is(
  (select count(*)::integer from private.sport_waitlist_passage_ledger l
   where l.match_id=current_setting('test.waitlist_three_match')::uuid
     and l.season_player_id='b5400000-0000-0000-0000-000000000001'),
  1,'Les recalculs répétés ne dupliquent pas le droit au +1'
);

-- Dans « Effectif », un choix manuel de l'admin est conservé par le recalcul.
update public.match_sport_participants p
set convocation_status='convoked',convocation_manual_override=true
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000001';
select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'convoked','Le recalcul conserve la convocation choisie par l admin'
);
select is(
  (select count(*)::integer from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.convocation_status='convoked'),
  2,'Le choix manuel prend une place : le quota reste respecté'
);

-- Un changement de disponibilité efface le choix manuel.
update public.match_sport_participants p
set availability_status='absent',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000001';
select is(
  (select p.convocation_manual_override from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  false,'Une nouvelle réponse du joueur efface le choix de l admin'
);
update public.match_sport_participants p
set availability_status='available',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000001';
select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'not_convoked','Sans choix manuel, Alice suit de nouveau la liste'
);

-- Les compteurs déterminent l'ordre et les futures convocations.
update public.sport_waitlist_entries
set manual_waitlist_count = 2
where season_player_id = 'b5400000-0000-0000-0000-000000000001';
select private.rebuild_sport_waitlist_order(
  'b5200000-0000-0000-0000-000000000001', null
);
select private.rebalance_upcoming_waitlist_matches(
  'b5200000-0000-0000-0000-000000000001'
);

select is(
  (select e.position from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  3,'Deux passages placent Alice en bas de liste'
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000002'),
  'not_convoked','Bruno devient le joueur en attente après changement de rang'
);

-- L'administrateur retire les +1 d'Alice : le classement est recalculé
-- aussitôt et les convocations suivent.
select lives_ok(
  $$select public.admin_set_waitlist_manual_count(
    'b5400000-0000-0000-0000-000000000001',0
  )$$,
  'l admin peut retirer des +1 à la main'
);
select is(
  (select e.position from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  1,'sans +1, Alice remonte aussitôt en haut de liste'
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'not_convoked','Alice redevient la joueuse en attente'
);
-- Il les rajoute : Alice redescend en bas de liste.
select lives_ok(
  $$select public.admin_set_waitlist_manual_count(
    'b5400000-0000-0000-0000-000000000001',5
  )$$,
  'l admin peut ajouter des +1 à la main'
);
select is(
  (select e.manual_waitlist_count from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  5,'le compteur corrigé est enregistré'
);
select is(
  (select e.position from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  3,'avec 5 passages, Alice redescend aussitôt en bas de liste'
);
select throws_ok(
  $$select public.admin_set_waitlist_manual_count(
    'b5400000-0000-0000-0000-000000000001',-1
  )$$,
  '22023',
  'Invalid count',
  'un compteur négatif est refusé'
);

-- L'administrateur place Alice tout en haut : les convocations suivent.
select public.admin_reorder_sport_waitlist(
  'b5200000-0000-0000-0000-000000000001',
  array[
    'b5400000-0000-0000-0000-000000000001'::uuid,
    'b5400000-0000-0000-0000-000000000002'::uuid,
    'b5400000-0000-0000-0000-000000000003'::uuid
  ],
  'Choix de l admin'
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'not_convoked','Alice placée en haut par l admin passe en attente'
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000002'),
  'convoked','Bruno descendu par l admin est convoqué'
);

-- Un changement de disponibilité ne défait pas l'ordre de l'admin.
update public.match_sport_participants p
set availability_status='absent',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000003';
update public.match_sport_participants p
set availability_status='available',updated_at=now()
where p.match_id=current_setting('test.waitlist_three_match')::uuid
  and p.season_player_id='b5400000-0000-0000-0000-000000000003';
select private.recompute_match_convocations_internal(
  current_setting('test.waitlist_three_match')::uuid,false
);
select is(
  (select e.position from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  1,'l ordre choisi par l admin survit aux recalculs de convocations'
);

-- « Recalculer » réapplique les trois critères.
select public.admin_recalculate_sport_waitlist(
  'b5200000-0000-0000-0000-000000000001'
);
select is(
  (select e.position from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  3,'Recalculer replace Alice selon son compteur'
);
select is(
  (select p.convocation_status::text from public.match_sport_participants p
   where p.match_id=current_setting('test.waitlist_three_match')::uuid
     and p.season_player_id='b5400000-0000-0000-0000-000000000002'),
  'not_convoked','après Recalculer, Bruno redevient le joueur en attente'
);

-- L'augmentation du quota à tous les présents neutralise les +1 du match.
update public.match_sport_workflows
set squad_size_limit=3
where match_id=current_setting('test.waitlist_three_match')::uuid;
select is(
  (select w.waitlist_passages_exempt from public.match_sport_workflows w
   where w.match_id=current_setting('test.waitlist_three_match')::uuid),
  true,'Le match devient exempt si le quota accueille tous les présents'
);
select is(
  private.finalize_match_waitlist_turns_internal(
    current_setting('test.waitlist_three_match')::uuid,false),
  0,'Aucun +1 n est crédité avant le coup d envoi'
);

-- Même un +1 déjà attribué est révoqué si le match est annulé.
-- L'essai simule le crédit sans attendre l'horloge du coup d'envoi.
select set_config(
  'test.waitlist_count_before_annulation',
  (select e.manual_waitlist_count::text
   from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  true
);
update public.match_sport_workflows
set waitlist_passages_exempt=false
where match_id=current_setting('test.waitlist_three_match')::uuid;
update private.sport_waitlist_passage_ledger
set credited_at=now(), voided_at=null
where match_id=current_setting('test.waitlist_three_match')::uuid
  and season_player_id='b5400000-0000-0000-0000-000000000001';
update public.sport_waitlist_entries
set manual_waitlist_count=manual_waitlist_count+1
where season_player_id='b5400000-0000-0000-0000-000000000001';

update public.matches
set status='annule'
where id=current_setting('test.waitlist_three_match')::uuid;

select ok(
  (select w.waitlist_passages_exempt
   from public.match_sport_workflows w
   where w.match_id=current_setting('test.waitlist_three_match')::uuid),
  'annuler le match le rend définitivement exempt'
);
select ok(
  (select l.voided_at is not null
   from private.sport_waitlist_passage_ledger l
   where l.match_id=current_setting('test.waitlist_three_match')::uuid
     and l.season_player_id='b5400000-0000-0000-0000-000000000001'),
  'le journal conserve la trace de la révocation'
);
select is(
  (select e.manual_waitlist_count
   from public.sport_waitlist_entries e
   where e.season_player_id='b5400000-0000-0000-0000-000000000001'),
  current_setting('test.waitlist_count_before_annulation')::integer,
  'un +1 déjà crédité est retiré du classement après annulation'
);

-- Point de départ de la mise en ligne : l'ordre de départ prime, seuls les
-- +1 gagnés ensuite font descendre un joueur.
delete from private.sport_waitlist_start
where season_id = 'b5200000-0000-0000-0000-000000000001';
insert into private.sport_waitlist_start
  (season_id, season_player_id, start_position, start_count)
select e.season_id, e.season_player_id,
  case e.season_player_id
    when 'b5400000-0000-0000-0000-000000000001' then 1
    when 'b5400000-0000-0000-0000-000000000002' then 2
    else 3 end,
  e.manual_waitlist_count
from public.sport_waitlist_entries e
where e.season_id = 'b5200000-0000-0000-0000-000000000001';
select private.rebuild_sport_waitlist_order(
  'b5200000-0000-0000-0000-000000000001', null
);
select is(
  (select array_agg(e.season_player_id order by e.position)
   from public.sport_waitlist_entries e
   where e.season_id = 'b5200000-0000-0000-0000-000000000001'),
  array[
    'b5400000-0000-0000-0000-000000000001'::uuid,
    'b5400000-0000-0000-0000-000000000002'::uuid,
    'b5400000-0000-0000-0000-000000000003'::uuid
  ],
  'les anciens compteurs ne chamboulent pas l ordre de départ'
);
select public.admin_set_waitlist_manual_count(
  'b5400000-0000-0000-0000-000000000002',
  (select e.manual_waitlist_count + 1 from public.sport_waitlist_entries e
   where e.season_player_id = 'b5400000-0000-0000-0000-000000000002')
);
select is(
  (select array_agg(e.season_player_id order by e.position)
   from public.sport_waitlist_entries e
   where e.season_id = 'b5200000-0000-0000-0000-000000000001'),
  array[
    'b5400000-0000-0000-0000-000000000001'::uuid,
    'b5400000-0000-0000-0000-000000000003'::uuid,
    'b5400000-0000-0000-0000-000000000002'::uuid
  ],
  'un nouveau +1 fait descendre Bruno en bas de liste'
);

select * from finish();
rollback;
