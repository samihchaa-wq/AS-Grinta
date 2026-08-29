begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Compte rendu de match : effectif rejouable, faits du match durables et
-- statistiques dérivées côté serveur.

insert into auth.users(id,email,raw_user_meta_data)
select ('a1000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('match-report-%s@example.invalid',n),
       jsonb_build_object('first_name','Report','last_name','Match')
from generate_series(1,16) n;

update public.profiles
set role=case when id='a1000000-0000-0000-0000-000000000001' then 'admin' else 'pronostiqueur' end,
    status='active',updated_at=now()
where id::text like 'a1000000-0000-0000-0000-%';

insert into public.seasons(id,name,status)
values('a2000000-0000-0000-0000-000000000001','2205-2206','open');
insert into public.opponents(id,name)
values('a3000000-0000-0000-0000-000000000001','Report United');

-- Le joueur 1 est gardien : c'est lui qui doit recevoir le clean sheet
-- automatique, sans que personne ne le coche.
insert into public.season_players(
  id,season_id,first_name,last_name,is_goalkeeper,is_active,position,profile_id
)
select ('a4000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       'a2000000-0000-0000-0000-000000000001',
       format('Joueur%s',n),'Report',
       n=1,true,n,('a1000000-0000-0000-0000-'||lpad((n+1)::text,12,'0'))::uuid
from generate_series(1,15) n;

update private.app_feature_flags
set enabled=true,updated_at=now(),updated_by='a1000000-0000-0000-0000-000000000001'
where key='sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.report_match',
  public.create_match_with_odds_and_sport_limit(
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    ((now()+interval '3 days') at time zone 'Europe/Paris')::date,
    ((now()+interval '3 days') at time zone 'Europe/Paris')::time,
    'domicile',2.1,3.2,2.9,16
  )::text,
  true
);
reset role;

update public.matches
set match_date=((now()-interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time=((now()-interval '2 hours') at time zone 'Europe/Paris')::time,
    kickoff_at=now()-interval '2 hours'
where id=current_setting('test.report_match')::uuid;
update public.match_sport_workflows
set availability_state='closed'
where match_id=current_setting('test.report_match')::uuid;
update public.match_sport_participants
set availability_status='available',convocation_status='convoked',selection_status='substitute'
where match_id=current_setting('test.report_match')::uuid;

-- ---------------------------------------------------------------------------
-- Aides de fabrication des paquets envoyés par l'écran
-- ---------------------------------------------------------------------------

create or replace function pg_temp.participant_of(p_position integer)
returns uuid language sql stable as $function$
  select participant.id
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=current_setting('test.report_match')::uuid
    and player.position=p_position;
$function$;
grant execute on function pg_temp.participant_of(integer) to authenticated;

-- p_starters titulaires (positions 1..p_starters), p_bench remplaçants,
-- le reste retiré du compte rendu.
create or replace function pg_temp.report_lineup(
  p_starters integer,
  p_bench integer
)
returns jsonb language sql stable as $function$
  select jsonb_build_object(
    'formation_code','4-4-2',
    'entries', jsonb_agg(jsonb_build_object(
      'participant_id',participant.id,
      'zone',case
        when player.position<=p_starters then 'field'
        when player.position<=p_starters+p_bench then 'bench'
        else 'not_selected'
      end,
      'x',case when player.position<=p_starters
        then round((0.05*player.position)::numeric,6) else null end,
      'y',case when player.position<=p_starters
        then round((0.05*player.position)::numeric,6) else null end,
      'sort_order',player.position
    ) order by player.position)
  )
  from public.match_sport_participants participant
  join public.season_players player on player.id=participant.season_player_id
  where participant.match_id=current_setting('test.report_match')::uuid
    and participant.is_eligible;
$function$;
grant execute on function pg_temp.report_lineup(integer,integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Lecture : aucun joueur placé -> tout le monde sur le banc
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.report_initial',
  public.admin_get_match_sport_report(current_setting('test.report_match')::uuid)::text,
  true
);
reset role;

select is(
  (
    select count(*)
    from jsonb_array_elements(
      current_setting('test.report_initial')::jsonb#>'{lineup,entries}'
    ) entry
    where entry->>'zone'='field'
  ),
  0::bigint,
  'sans composition, le terrain du compte rendu est vide'
);

select cmp_ok(
  (
    select count(*)
    from jsonb_array_elements(
      current_setting('test.report_initial')::jsonb#>'{lineup,entries}'
    ) entry
    where entry->>'zone'='bench'
  ),
  '>=',
  15::bigint,
  'sans composition, tout l’effectif disponible est sur le banc'
);

select is(
  current_setting('test.report_initial')::jsonb->>'is_correction',
  'false',
  'un match jamais validé n’est pas présenté comme une correction'
);
select is(
  current_setting('test.report_initial')::jsonb->>'is_editable',
  'true',
  'un match terminé non validé est modifiable'
);

-- ---------------------------------------------------------------------------
-- 2. Validation initiale : le serveur dérive buts, passes et clean sheet
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.report_validated',
  public.admin_submit_match_sport_report(
    current_setting('test.report_match')::uuid,
    3,0,
    pg_temp.report_lineup(11,3),
    jsonb_build_array(
      -- 12' Joueur2 servi par Joueur3
      jsonb_build_object(
        'minute',12,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(2),
        'assist_participant_id',pg_temp.participant_of(3),
        'assist_kind','player','is_own_goal',false
      ),
      -- minute inconnue, buteur connu, aucune passe
      jsonb_build_object(
        'minute',null,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(4),
        'assist_kind','none','is_own_goal',false
      ),
      -- CSC adverse : personne n’est crédité
      jsonb_build_object(
        'minute',90,'team_side','as_grinta','is_own_goal',true,'assist_kind','none'
      )
    ),
    'validation initiale du compte rendu'
  )::text,
  true
);
reset role;

select is(
  current_setting('test.report_validated')::jsonb->>'validation_kind',
  'initial',
  'la première validation du compte rendu est initiale'
);

select is(
  (select count(*) from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid),
  3::bigint,
  'les trois buts sont enregistrés comme faits durables'
);

select is(
  (select minute from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=1),
  null::smallint,
  'une minute inconnue est conservée telle quelle'
);

select is(
  (select assist_kind from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=1),
  'none',
  '« aucune passe décisive » se distingue d’une passe non attribuée'
);

select is(
  (select scorer_participant_id from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=2),
  null::uuid,
  'un CSC adverse n’est crédité à aucun buteur'
);

-- Le lien exact but -> buteur -> passeur est conservé.
select is(
  (select assist_participant_id from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=0),
  pg_temp.participant_of(3),
  'le passeur reste rattaché à son but précis'
);

-- Compteurs dérivés, jamais saisis par le client.
select is(
  (select final_goals from public.match_sport_participants
   where id=pg_temp.participant_of(2)),
  1::smallint,
  'le buteur est crédité automatiquement'
);
select is(
  (select final_assists from public.match_sport_participants
   where id=pg_temp.participant_of(3)),
  1,
  'le passeur est crédité automatiquement'
);
select is(
  (select final_goals from public.match_sport_participants
   where id=pg_temp.participant_of(1)),
  0::smallint,
  'un CSC adverse ne gonfle le total de personne'
);

-- Clean sheet automatique : adversaire à zéro, gardien titulaire crédité.
select is(
  (select final_clean_sheet from public.match_sport_participants
   where id=pg_temp.participant_of(1)),
  true,
  'le clean sheet se déduit du score adverse et du gardien aligné'
);
select is(
  (select count(*) from public.match_sport_participants
   where match_id=current_setting('test.report_match')::uuid and final_clean_sheet),
  1::bigint,
  'un seul gardien reçoit le clean sheet'
);

-- Les statistiques permanentes suivent.
select is(
  (select goals from public.match_player_stats
   where match_id=current_setting('test.report_match')::uuid
     and season_player_id='a4000000-0000-0000-0000-000000000002'),
  1,
  'les statistiques permanentes reprennent le but dérivé'
);
select is(
  (select assists from public.match_player_stats
   where match_id=current_setting('test.report_match')::uuid
     and season_player_id='a4000000-0000-0000-0000-000000000003'),
  1,
  'les statistiques permanentes reprennent la passe dérivée'
);

-- ---------------------------------------------------------------------------
-- 3. Le score ne peut jamais diverger des faits
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,4,0,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object('team_side','as_grinta','assist_kind','unknown')
    )::text)
  ),
  '22023',
  'The score must match the recorded goals exactly',
  'un score supérieur au nombre de buts est refusé'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,1,0,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object(
        'minute',91,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(2),'assist_kind','unknown'
      )
    )::text)
  ),
  '22023',
  'A goal minute must be between 0 and 90',
  'une minute au-delà de la 90ᵉ est refusée'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,1,0,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object(
        'minute',10,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(2),
        'assist_participant_id',pg_temp.participant_of(2),'assist_kind','player'
      )
    )::text)
  ),
  '22023',
  'An assist requires a different scorer',
  'un joueur ne peut pas être son propre passeur'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,0,1,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object(
        'minute',10,'team_side','opponent',
        'scorer_participant_id',pg_temp.participant_of(2),'assist_kind','none'
      )
    )::text)
  ),
  '22023',
  'An opponent goal cannot be credited to an AS Grinta player',
  'un but adverse ne crédite jamais un joueur d’AS Grinta'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,1,0,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object(
        'minute',10,'team_side','as_grinta','is_own_goal',true,
        'scorer_participant_id',pg_temp.participant_of(2),'assist_kind','none'
      )
    )::text)
  ),
  '22023',
  'An own goal cannot be credited to a player',
  'un CSC ne crédite jamais un buteur'
);

-- Un buteur retiré de l’effectif ne peut pas rester attribué.
select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,1,0,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object(
        'minute',10,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(15),'assist_kind','unknown'
      )
    )::text)
  ),
  '22023',
  'A scorer or assist must be part of the match squad',
  'un buteur hors de l’effectif du compte rendu est refusé'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,0,0,%s::jsonb,'[]'::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(12,2)::text)
  ),
  '22023',
  'A match cannot have more than eleven actual starters',
  'un douzième titulaire est refusé'
);

reset role;

-- ---------------------------------------------------------------------------
-- 4. Minutes limites acceptées, et joueur retiré -> attribution effacée
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select set_config(
  'test.report_corrected',
  public.admin_submit_match_sport_report(
    current_setting('test.report_match')::uuid,
    2,1,
    -- Joueur2, l’ancien buteur, est retiré du compte rendu.
    (
      select jsonb_build_object(
        'formation_code','4-4-2',
        'entries',jsonb_agg(jsonb_build_object(
          'participant_id',participant.id,
          'zone',case
            when player.position=2 then 'not_selected'
            when player.position<=11 then 'field'
            when player.position<=14 then 'bench'
            else 'not_selected'
          end,
          'x',case when player.position<>2 and player.position<=11
            then round((0.05*player.position)::numeric,6) else null end,
          'y',case when player.position<>2 and player.position<=11
            then round((0.05*player.position)::numeric,6) else null end,
          'sort_order',player.position
        ) order by player.position)
      )
      from public.match_sport_participants participant
      join public.season_players player on player.id=participant.season_player_id
      where participant.match_id=current_setting('test.report_match')::uuid
        and participant.is_eligible
    ),
    jsonb_build_array(
      -- Le but du joueur retiré devient « non attribué » sans disparaître.
      jsonb_build_object('minute',0,'team_side','as_grinta','assist_kind','unknown'),
      jsonb_build_object(
        'minute',90,'team_side','as_grinta',
        'scorer_participant_id',pg_temp.participant_of(4),'assist_kind','none'
      ),
      -- CSC AS Grinta : c’est un but adverse.
      jsonb_build_object(
        'minute',60,'team_side','opponent','is_own_goal',true,'assist_kind','none'
      )
    ),
    'correction du compte rendu'
  )::text,
  true
);
reset role;

select is(
  current_setting('test.report_corrected')::jsonb->>'validation_kind',
  'correction',
  'une deuxième validation est enregistrée comme correction'
);
select is(
  (current_setting('test.report_corrected')::jsonb->>'version')::integer,
  2,
  'la correction incrémente la version du compte rendu'
);
select is(
  (select count(*) from public.match_sport_finalization_versions
   where match_id=current_setting('test.report_match')::uuid),
  2::bigint,
  'chaque version du compte rendu est archivée'
);

select is(
  (select minute from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=0),
  0::smallint,
  'la minute 0 est acceptée'
);
select is(
  (select minute from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=1),
  90::smallint,
  'la minute 90 est acceptée'
);
select is(
  (select is_own_goal from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid and ordinal=2),
  true,
  'un CSC AS Grinta est enregistré comme but adverse'
);

select is(
  (select final_goals from public.match_sport_participants
   where id=pg_temp.participant_of(2)),
  0::smallint,
  'le joueur retiré perd ses attributions'
);
select is(
  (select final_presence_status::text from public.match_sport_participants
   where id=pg_temp.participant_of(2)),
  'actual_absent',
  'le joueur retiré ne fait plus partie du compte rendu'
);
select is(
  (select count(*) from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid),
  3::bigint,
  'retirer un joueur ne supprime jamais son but'
);

-- L’adversaire a marqué : plus aucun clean sheet.
select is(
  (select count(*) from public.match_sport_participants
   where match_id=current_setting('test.report_match')::uuid and final_clean_sheet),
  0::bigint,
  'le clean sheet disparaît dès que l’adversaire marque'
);
select is(
  (select score_as_grinta||'-'||score_adverse from public.matches
   where id=current_setting('test.report_match')::uuid),
  '2-1',
  'le score du match suit exactement les faits enregistrés'
);

-- ---------------------------------------------------------------------------
-- 5. Les faits survivent à la suppression de la chronologie Live
-- ---------------------------------------------------------------------------

select is(
  (select count(*) from public.match_sport_goal_actions
   where match_id=current_setting('test.report_match')::uuid
     and source_live_event_id is null),
  3::bigint,
  'les faits du compte rendu ne dépendent d’aucun événement Live'
);

-- ---------------------------------------------------------------------------
-- 5 bis. Ajouter un joueur à l'effectif du compte rendu
-- ---------------------------------------------------------------------------

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Un invité créé après coup : le chemin passe par l'index d'unicité partiel.
select set_config(
  'test.report_guest',
  public.admin_attach_match_sport_report_player(
    current_setting('test.report_match')::uuid,
    null, null, 'Momo', 'Invite', false, 'renfort de dernière minute'
  )::text,
  true
);

-- Le même invité une seconde fois ne doit pas doubler la participation.
select lives_ok(
  format(
    $$select public.admin_attach_match_sport_report_player(
        %L::uuid, null, null, 'Momo', 'Invite', false, null
      )$$,
    current_setting('test.report_match')
  ),
  'rattacher deux fois le même invité reste sans effet de bord'
);

reset role;

select is(
  (
    select count(*)
    from public.match_sport_participants participant
    join public.guest_players guest on guest.id = participant.guest_player_id
    where participant.match_id = current_setting('test.report_match')::uuid
      and lower(btrim(guest.first_name)) = 'momo'
  ),
  1::bigint,
  'un invité n’est rattaché qu’une seule fois au match'
);

-- L'invité rejoint l'effectif du compte rendu sur le banc : l'administrateur
-- le place ensuite sur le terrain s'il le souhaite.
select is(
  (
    select entry->>'zone'
    from jsonb_array_elements(
      current_setting('test.report_guest')::jsonb#>'{lineup,entries}'
    ) entry
    where entry->>'participant_id'
      = current_setting('test.report_guest')::jsonb->>'added_participant_id'
  ),
  'bench',
  'un joueur ajouté rejoint l’effectif sur le banc'
);

select is(
  (
    select entry->>'display_name'
    from jsonb_array_elements(
      current_setting('test.report_guest')::jsonb#>'{lineup,entries}'
    ) entry
    where entry->>'participant_id'
      = current_setting('test.report_guest')::jsonb->>'added_participant_id'
  ),
  'Momo Invite (Invité)',
  'le joueur ajouté est identifié comme invité dans le compte rendu'
);

-- ---------------------------------------------------------------------------
-- 6. Match archivé : plus aucune modification
-- ---------------------------------------------------------------------------

update public.matches set status='archive'
where id=current_setting('test.report_match')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select is(
  public.admin_get_match_sport_report(
    current_setting('test.report_match')::uuid
  )->>'is_editable',
  'false',
  'un match archivé n’est plus modifiable'
);

select throws_ok(
  format(
    $$select public.admin_submit_match_sport_report(%L::uuid,2,1,%s::jsonb,%s::jsonb,null)$$,
    current_setting('test.report_match'),
    quote_literal(pg_temp.report_lineup(11,3)::text),
    quote_literal(jsonb_build_array(
      jsonb_build_object('team_side','as_grinta','assist_kind','unknown'),
      jsonb_build_object('team_side','as_grinta','assist_kind','unknown'),
      jsonb_build_object('team_side','opponent','assist_kind','none')
    )::text)
  ),
  '22023',
  'Only upcoming or finished matches can be validated',
  'un match archivé refuse toute nouvelle validation'
);

reset role;

select * from finish();
rollback;
