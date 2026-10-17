begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Le prono s'ouvre à J-6 à 12 h, ou dès l'ouverture des disponibilités si un
-- admin l'a avancée. Une ouverture plus tardive ne le retarde jamais.

select ok(
  not has_function_privilege(
    'authenticated',
    'private.match_predictions_open_at(uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.match_predictions_open_at(uuid,timestamp with time zone)',
    'EXECUTE'
  ),
  'l’ouverture du prono n’est calculée que par les fonctions du serveur'
);

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    '9e100000-0000-0000-0000-000000000001',
    'early-prono-admin@example.invalid',
    '{"first_name":"Admin","last_name":"Prono"}'::jsonb
  ),
  (
    '9e100000-0000-0000-0000-000000000002',
    'early-prono-player@example.invalid',
    '{"first_name":"Joueur","last_name":"Prono"}'::jsonb
  );

update public.profiles
set role = case
      when id = '9e100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id in (
  '9e100000-0000-0000-0000-000000000001',
  '9e100000-0000-0000-0000-000000000002'
);

insert into public.seasons(id, name, status)
values ('9e200000-0000-0000-0000-000000000001', '2093-2094', 'open');

insert into public.opponents(id, name)
values ('9e300000-0000-0000-0000-000000000001', 'Prono Anticipé FC');

update private.app_feature_flags
set enabled = true,
    updated_at = now(),
    updated_by = '9e100000-0000-0000-0000-000000000001'
where key = 'sports_management';

select set_config(
  'request.jwt.claims',
  '{"sub":"9e100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

-- Dans vingt jours, disponibilités ouvertes tout de suite.
select set_config(
  'test.early_now',
  public.admin_create_match_complete_v2(
    '9e200000-0000-0000-0000-000000000001',
    '9e300000-0000-0000-0000-000000000001',
    ((now() + interval '20 days') at time zone 'Europe/Paris')::date,
    time '20:00', 'domicile',
    2, 3, 4, 14, null, false, 'amical', null,
    'now', null
  )::text,
  true
);

-- Dans vingt et un jours, ouverture automatique (J-6) : pas encore ouverte.
select set_config(
  'test.far_automatic',
  public.admin_create_match_complete_v2(
    '9e200000-0000-0000-0000-000000000001',
    '9e300000-0000-0000-0000-000000000001',
    ((now() + interval '21 days') at time zone 'Europe/Paris')::date,
    time '20:00', 'exterieur',
    2, 3, 4, 14, null, false, 'amical', null,
    'automatic', null
  )::text,
  true
);

-- Dans trois jours (J-6 déjà passé), disponibilités repoussées à demain.
select set_config(
  'test.late_custom',
  public.admin_create_match_complete_v2(
    '9e200000-0000-0000-0000-000000000001',
    '9e300000-0000-0000-0000-000000000001',
    ((now() + interval '3 days') at time zone 'Europe/Paris')::date,
    time '20:00', 'domicile',
    2, 3, 4, 14, null, false, 'amical', null,
    'custom', now() + interval '1 day'
  )::text,
  true
);

reset role;

select ok(
  (
    select private.match_predictions_open_at(match.id, match.kickoff_at) <= now()
      and private.match_features_open_at(match.kickoff_at) > now()
    from public.matches match
    where match.id = current_setting('test.early_now')::uuid
  ),
  'des disponibilités ouvertes avant J-6 avancent l’ouverture du prono'
);

select is(
  (
    select private.match_predictions_open_at(match.id, match.kickoff_at)
    from public.matches match
    where match.id = current_setting('test.late_custom')::uuid
  ),
  (
    select private.match_features_open_at(match.kickoff_at)
    from public.matches match
    where match.id = current_setting('test.late_custom')::uuid
  ),
  'des disponibilités ouvertes après J-6 ne retardent pas le prono'
);

select is(
  private.match_predictions_open_at(
    '9e900000-0000-0000-0000-000000000001',
    timestamptz '2099-06-20 18:00:00+00'
  ),
  private.match_features_open_at(timestamptz '2099-06-20 18:00:00+00'),
  'sans suivi sportif, le prono s’ouvre à J-6 à 12 h'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9e100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  format(
    'select public.save_match_prediction(%L::uuid, 2, 1)',
    current_setting('test.early_now')
  ),
  'le prono est accepté dès l’ouverture anticipée des disponibilités'
);

select throws_ok(
  format(
    'select public.save_match_prediction(%L::uuid, 2, 1)',
    current_setting('test.far_automatic')
  ),
  '22023',
  'Ce match n’est pas ouvert aux pronostics.',
  'le prono reste fermé avant J-6 quand les disponibilités ne sont pas ouvertes'
);

select lives_ok(
  format(
    'select public.save_match_prediction(%L::uuid, 0, 0)',
    current_setting('test.late_custom')
  ),
  'le prono reste ouvert à partir de J-6 même si les disponibilités ouvrent plus tard'
);

reset role;

-- Le garde-fou de la table applique la même règle aux écritures du serveur.
select set_config('request.jwt.claims', '', true);

select lives_ok(
  format(
    'insert into public.match_predictions(match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse, is_filled)
     values (%L::uuid, %L::uuid, 1, 1, true)',
    current_setting('test.early_now'),
    '9e100000-0000-0000-0000-000000000001'
  ),
  'le garde-fou de la table accepte un prono après une ouverture anticipée'
);

select throws_ok(
  format(
    'insert into public.match_predictions(match_id, profile_id, predicted_score_as_grinta, predicted_score_adverse, is_filled)
     values (%L::uuid, %L::uuid, 1, 1, true)',
    current_setting('test.far_automatic'),
    '9e100000-0000-0000-0000-000000000001'
  ),
  '22023',
  'Les pronostics de ce match sont fermés.',
  'le garde-fou de la table refuse toujours un prono avant l’ouverture'
);

select * from finish();
rollback;
