begin;

set local search_path = public, storage, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    '89f24276-dac0-4046-87a3-6c28e48fef3a',
    'badge-authorized@example.invalid',
    '{"first_name":"Badge","last_name":"Authorized"}'::jsonb
  ),
  (
    'ba6e0000-0000-0000-0000-000000000001',
    'badge-other-admin@example.invalid',
    '{"first_name":"Badge","last_name":"OtherAdmin"}'::jsonb
  );

update public.profiles
set role = 'admin',
    status = 'active',
    updated_at = now()
where id in (
  '89f24276-dac0-4046-87a3-6c28e48fef3a',
  'ba6e0000-0000-0000-0000-000000000001'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"89f24276-dac0-4046-87a3-6c28e48fef3a","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$select public.staff_create_badge(
    'badge_access_allowed_test',
    'Badge access allowed',
    '🏅',
    '',
    null,
    '#F97316'
  )$$,
  'un gestionnaire autorisé peut créer un badge'
);

select lives_ok(
  $$select public.staff_update_badge_text(
    'badge_access_allowed_test',
    '  Nom corrigé  ',
    '  Descriptif corrigé  '
  )$$,
  'un gestionnaire autorisé peut renommer un badge'
);

select is(
  (
    select name || '|' || description
    from public.badges
    where code = 'badge_access_allowed_test'
  ),
  'Nom corrigé|Descriptif corrigé',
  'le nom et le descriptif sont enregistrés sans espaces superflus'
);

select throws_ok(
  $$select public.staff_update_badge_text(
    'badge_access_allowed_test',
    '   ',
    ''
  )$$,
  '22023',
  'un badge ne peut pas recevoir un nom vide'
);

select throws_ok(
  $$select public.staff_update_badge_text('badge_inconnu_test', 'Nom', '')$$,
  'P0002',
  'un badge inconnu est signalé'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"ba6e0000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.staff_create_badge(
    'badge_access_denied_test',
    'Badge access denied',
    '🏅',
    '',
    null,
    '#F97316'
  )$$,
  '42501',
  'un autre administrateur ne peut pas créer de badge'
);

select throws_ok(
  $$select public.staff_update_badge_text(
    'badge_access_allowed_test',
    'Nom interdit',
    ''
  )$$,
  '42501',
  'un autre administrateur ne peut pas renommer un badge'
);

select throws_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'ba6e1000-0000-0000-0000-000000000001',
      'badge-images',
      'forbidden.webp',
      'ba6e0000-0000-0000-0000-000000000001',
      'ba6e0000-0000-0000-0000-000000000001',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  '42501',
  'un autre administrateur ne peut pas téléverser une image de badge'
);

reset role;
select * from finish();
rollback;
