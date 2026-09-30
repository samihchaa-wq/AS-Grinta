begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Les tâches planifiées chaque minute ne doivent incrémenter le signal de
-- synchronisation que lorsqu'elles modifient réellement une ligne. Sinon,
-- chaque client connecté recharge toutes ses données à chaque minute.

create temporary table signal_probe (label text primary key, revision bigint);
grant all on signal_probe to authenticated;

create or replace function pg_temp.shared_revision()
returns bigint
language sql
as $$
  select coalesce(
    (select revision from public.shared_data_change_signals where key = 'global'),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- Fin automatique des matchs internes
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data)
values (
  '92000000-0000-0000-0000-000000000001',
  'idle-cron-admin@example.invalid',
  '{"first_name":"Admin","last_name":"Cron"}'::jsonb
);

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where id = '92000000-0000-0000-0000-000000000001';

insert into public.seasons (id, name, status)
values ('91000000-0000-0000-0000-000000000001', '2095-2096', 'open');

insert into public.matches (
  id, season_id, match_type, status, kickoff_at,
  match_date, match_time, location, planned_duration_minutes, created_by
)
values (
  '91000000-0000-0000-0000-0000000000b1',
  '91000000-0000-0000-0000-000000000001',
  'entre_nous', 'a_venir', now(),
  (now() at time zone 'Europe/Paris')::date,
  (now() at time zone 'Europe/Paris')::time,
  'domicile', 90, '92000000-0000-0000-0000-000000000001'
);

-- Absorbe d'éventuels matchs internes des données de départ déjà échus.
select private.finish_due_internal_matches(now());
insert into signal_probe values ('finish_idle', pg_temp.shared_revision());

select is(
  private.finish_due_internal_matches(now()),
  0,
  'aucun match interne à terminer'
);

select is(
  pg_temp.shared_revision(),
  (select revision from signal_probe where label = 'finish_idle'),
  'une fin de match à vide ne réveille pas les clients'
);

select is(
  private.finish_due_internal_matches(now() + interval '105 minutes'),
  1,
  'le match interne se termine une fois le délai atteint'
);

select ok(
  pg_temp.shared_revision()
    > (select revision from signal_probe where label = 'finish_idle'),
  'une vraie fin de match signale bien le changement'
);

-- ---------------------------------------------------------------------------
-- Ouverture et fermeture des disponibilités
-- ---------------------------------------------------------------------------

insert into public.opponents (id, name)
values ('93000000-0000-0000-0000-000000000001', 'Cron FC');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '92000000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"92000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select set_config(
  'test.idle_cron_match',
  public.create_match_with_odds_and_sport_limit(
    '91000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    ((now() + interval '10 days') at time zone 'Europe/Paris')::date,
    ((now() + interval '10 days') at time zone 'Europe/Paris')::time,
    'domicile',
    2.10,
    3.20,
    2.90,
    14
  )::text,
  true
);

reset role;

-- Absorbe d'éventuels workflows des données de départ à ouvrir ou fermer.
select private.process_sport_availability_notifications(now());
insert into signal_probe values ('availability_idle', pg_temp.shared_revision());

select is(
  private.process_sport_availability_notifications(now())
    - 'notifications_created',
  '{"opened_workflows": 0, "closed_workflows": 0}'::jsonb,
  'aucun workflow à ouvrir ni à fermer'
);

select is(
  pg_temp.shared_revision(),
  (select revision from signal_probe where label = 'availability_idle'),
  'un passage à vide du moteur de disponibilités ne réveille pas les clients'
);

select is(
  (
    select availability_state::text
    from public.match_sport_workflows
    where match_id = current_setting('test.idle_cron_match')::uuid
  ),
  'pending',
  'le workflow du match à venir reste en attente'
);

select is(
  private.process_sport_availability_notifications(
    (
      select availability_opens_at
      from public.match_sport_workflows
      where match_id = current_setting('test.idle_cron_match')::uuid
    )
  ) #>> '{opened_workflows}',
  '1',
  'à l’échéance, le workflow s’ouvre toujours'
);

select ok(
  pg_temp.shared_revision()
    > (select revision from signal_probe where label = 'availability_idle'),
  'une vraie ouverture signale bien le changement'
);

insert into signal_probe values ('before_close', pg_temp.shared_revision());

select is(
  private.process_sport_availability_notifications(
    (
      select kickoff_at
      from public.matches
      where id = current_setting('test.idle_cron_match')::uuid
    )
  ) #>> '{closed_workflows}',
  '1',
  'au coup d’envoi, le workflow se ferme toujours'
);

select ok(
  pg_temp.shared_revision()
    > (select revision from signal_probe where label = 'before_close'),
  'une vraie fermeture signale bien le changement'
);

select * from finish();
rollback;
