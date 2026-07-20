begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure('public.internal_push_dispatch(text,uuid)') is not null
  and to_regprocedure('private.push_due_motm_reminders(timestamptz)') is not null,
  'les fonctions de notification HDM existent'
);

select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'sports-motm-push-reminders'
      and schedule = '* * * * *'
  ),
  'le rappel HDM est vérifié chaque minute'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.push_due_motm_reminders(timestamptz)',
    'EXECUTE'
  ),
  'le worker HDM n’est pas exposé au rôle anonyme'
);

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'motm-push-admin@example.invalid',
    '{"first_name":"Admin"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'motm-push-one@example.invalid',
    '{"first_name":"Votant Un"}'::jsonb
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'motm-push-two@example.invalid',
    '{"first_name":"Votant Deux"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'd1000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    notify_match_reminders = true,
    updated_at = now()
where id in (
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000002',
  'd1000000-0000-0000-0000-000000000003'
);

insert into public.seasons(id, name, status)
values ('d2000000-0000-0000-0000-000000000001', '2097-2098', 'open');

insert into public.opponents(id, name)
values ('d3000000-0000-0000-0000-000000000001', 'Push FC');

insert into public.season_players(
  id,
  season_id,
  first_name,
  last_name,
  is_goalkeeper,
  is_active,
  position,
  profile_id
) values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    'Votant',
    'Un',
    false,
    true,
    1,
    'd1000000-0000-0000-0000-000000000002'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000001',
    'Votant',
    'Deux',
    false,
    true,
    2,
    'd1000000-0000-0000-0000-000000000003'
  );

insert into public.push_subscriptions(
  profile_id,
  endpoint,
  p256dh,
  auth,
  user_agent
) values
  (
    'd1000000-0000-0000-0000-000000000002',
    'https://push.example.invalid/motm-one',
    'p256dh-one',
    'auth-one',
    'pgTAP'
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'https://push.example.invalid/motm-two',
    'p256dh-two',
    'auth-two',
    'pgTAP'
  );

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = 'd1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.motm_push_match',
  public.create_match_with_odds_and_sport_limit(
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    ((now() + interval '5 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '5 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    14
  )::text,
  true
);

reset role;
update public.matches
set kickoff_at = now() - interval '2 hours',
    match_date = ((now() - interval '2 hours') at time zone 'Europe/Paris')::date,
    match_time = ((now() - interval '2 hours') at time zone 'Europe/Paris')::time
where id = current_setting('test.motm_push_match')::uuid;

select set_config(
  'test.motm_push_player_one_participant',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.motm_push_match')::uuid
      and participant.season_player_id =
        'd4000000-0000-0000-0000-000000000001'::uuid
  ),
  true
);

select set_config(
  'test.motm_push_player_two_participant',
  (
    select participant.id::text
    from public.match_sport_participants participant
    where participant.match_id = current_setting('test.motm_push_match')::uuid
      and participant.season_player_id =
        'd4000000-0000-0000-0000-000000000002'::uuid
  ),
  true
);

create or replace function pg_temp.motm_push_final_payload()
returns jsonb
language sql
stable
as $function$
  select jsonb_agg(
    jsonb_build_object(
      'participant_id', participant.id,
      'present', true,
      'final_selection_status', case
        when participant.season_player_id =
          'd4000000-0000-0000-0000-000000000001'::uuid then 'starter'
        else 'substitute'
      end,
      'goals', 0,
      'clean_sheet', false
    ) order by participant.id
  )
  from public.match_sport_participants participant
  where participant.match_id = current_setting('test.motm_push_match')::uuid;
$function$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.admin_finalize_match_sport_postgame(
    current_setting('test.motm_push_match')::uuid,
    1,
    0,
    pg_temp.motm_push_final_payload(),
    'Validation ouvrant le scrutin et sa notification'
  ) #>> '{vote_state}',
  'open',
  'la validation ouvre le scrutin'
);

reset role;
select is(
  (
    select count(*)
    from public.push_notification_log
    where match_id = current_setting('test.motm_push_match')::uuid
      and kind = 'motm_open'
  ),
  1::bigint,
  'l’ouverture crée une seule notification anti-doublon'
);

select is(
  jsonb_array_length(
    public.internal_push_dispatch(
      'motm_open',
      current_setting('test.motm_push_match')::uuid
    ) -> 'subscriptions'
  ),
  2,
  'les deux joueurs permanents présents reçoivent l’ouverture'
);

select like(
  public.internal_push_dispatch(
    'motm_open',
    current_setting('test.motm_push_match')::uuid
  ) #>> '{payload,url}',
  'matches/%/vote',
  'la notification ouvre directement l’écran de vote'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.cast_match_motm_vote(
    current_setting('test.motm_push_match')::uuid,
    current_setting('test.motm_push_player_two_participant')::uuid
  ) #>> '{accepted}',
  'true',
  'le premier joueur vote avant le rappel'
);

reset role;
update public.match_sport_motm_elections
set opens_at = now() - interval '19 hours',
    closes_at = now() + interval '5 hours'
where match_id = current_setting('test.motm_push_match')::uuid;

select is(
  private.push_due_motm_reminders(now()),
  1,
  'un rappel est créé six heures avant la clôture'
);

select is(
  private.push_due_motm_reminders(now()),
  0,
  'une seconde exécution ne crée aucun doublon'
);

select is(
  jsonb_array_length(
    public.internal_push_dispatch(
      'motm_reminder',
      current_setting('test.motm_push_match')::uuid
    ) -> 'subscriptions'
  ),
  1,
  'le rappel cible uniquement le joueur présent qui n’a pas voté'
);

select is(
  public.internal_push_dispatch(
    'motm_reminder',
    current_setting('test.motm_push_match')::uuid
  ) #>> '{subscriptions,0,profile_id}',
  'd1000000-0000-0000-0000-000000000003',
  'le joueur ayant déjà voté est exclu du rappel'
);

update public.match_sport_motm_elections
set opens_at = now() - interval '25 hours',
    closes_at = now() - interval '1 hour'
where match_id = current_setting('test.motm_push_match')::uuid;

select ok(
  private.close_match_motm_election(
    current_setting('test.motm_push_match')::uuid,
    false
  ),
  'la clôture calcule le résultat'
);

select is(
  (
    select count(*)
    from public.push_notification_log
    where match_id = current_setting('test.motm_push_match')::uuid
      and kind = 'motm_results'
  ),
  1::bigint,
  'la clôture annonce une seule fois les résultats'
);

select like(
  public.internal_push_dispatch(
    'motm_results',
    current_setting('test.motm_push_match')::uuid
  ) #>> '{payload,body}',
  '%Votant Deux%',
  'le message de résultat contient le gagnant réel'
);

select is(
  jsonb_array_length(
    public.internal_push_dispatch(
      'motm_results',
      current_setting('test.motm_push_match')::uuid
    ) -> 'subscriptions'
  ),
  2,
  'les joueurs actifs de la saison reçoivent le résultat'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.admin_restart_match_motm_vote(
    current_setting('test.motm_push_match')::uuid,
    'Relance contrôlée du scrutin et des notifications'
  ) #>> '{state}',
  'open',
  'une relance ouvre un nouveau cycle'
);

reset role;
select is(
  (
    select count(*)
    from public.push_notification_log
    where match_id = current_setting('test.motm_push_match')::uuid
      and kind in ('motm_open', 'motm_reminder', 'motm_results')
  ),
  1::bigint,
  'la relance retire les anciens marqueurs et conserve seulement la nouvelle ouverture'
);

select is(
  (
    select kind
    from public.push_notification_log
    where match_id = current_setting('test.motm_push_match')::uuid
      and kind in ('motm_open', 'motm_reminder', 'motm_results')
  ),
  'motm_open',
  'le nouveau cycle recommence par la notification d’ouverture'
);

update private.app_feature_flags
set enabled = false,
    updated_at = now(),
    updated_by = 'd1000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select is(
  jsonb_array_length(
    public.internal_push_dispatch(
      'motm_open',
      current_setting('test.motm_push_match')::uuid
    ) -> 'subscriptions'
  ),
  0,
  'le feature flag désactivé bloque les destinataires HDM'
);

select is(
  private.push_due_motm_reminders(now() + interval '19 hours'),
  0,
  'le feature flag désactivé bloque également le worker'
);

select * from finish();
rollback;
