begin;

set local search_path = public, storage, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  (
    'e5000000-0000-0000-0000-000000000001',
    'storage-admin@example.invalid',
    '{"first_name":"Storage","last_name":"Admin"}'::jsonb
  ),
  (
    'e5000000-0000-0000-0000-000000000002',
    'storage-player@example.invalid',
    '{"first_name":"Storage","last_name":"Player"}'::jsonb
  ),
  (
    'e5000000-0000-0000-0000-000000000003',
    'storage-other@example.invalid',
    '{"first_name":"Storage","last_name":"Other"}'::jsonb
  ),
  (
    'e5000000-0000-0000-0000-000000000004',
    'storage-pending@example.invalid',
    '{"first_name":"Storage","last_name":"Pending"}'::jsonb
  );

update public.profiles
set role = case
      when id = 'e5000000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = case
      when id = 'e5000000-0000-0000-0000-000000000004' then 'pending'
      else 'active'
    end,
    updated_at = now()
where id in (
  'e5000000-0000-0000-0000-000000000001',
  'e5000000-0000-0000-0000-000000000002',
  'e5000000-0000-0000-0000-000000000003',
  'e5000000-0000-0000-0000-000000000004'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e5000000-0000-0000-0000-000000000004","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000001',
      'profile-photos',
      'e5000000-0000-0000-0000-000000000004/avatar.webp',
      'e5000000-0000-0000-0000-000000000004',
      'e5000000-0000-0000-0000-000000000004',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  '42501',
  'un compte en attente ne téléverse aucune photo'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"e5000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000002',
      'profile-photos',
      'e5000000-0000-0000-0000-000000000002/avatar.webp',
      'e5000000-0000-0000-0000-000000000002',
      'e5000000-0000-0000-0000-000000000002',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  'un joueur actif téléverse dans son propre dossier'
);

select throws_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000003',
      'profile-photos',
      'e5000000-0000-0000-0000-000000000003/attaque.webp',
      'e5000000-0000-0000-0000-000000000002',
      'e5000000-0000-0000-0000-000000000002',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  '42501',
  'un joueur ne téléverse pas dans le dossier d’un autre compte'
);

select throws_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000004',
      'profile-photos',
      'e5000000-0000-0000-0000-000000000002/usurpation.webp',
      'e5000000-0000-0000-0000-000000000003',
      'e5000000-0000-0000-0000-000000000003',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  '42501',
  'un joueur ne falsifie pas le propriétaire d’un objet'
);

select throws_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000005',
      'badge-images',
      'attaque.webp',
      'e5000000-0000-0000-0000-000000000002',
      'e5000000-0000-0000-0000-000000000002',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  '42501',
  'un joueur ne crée pas une image de badge'
);

select lives_ok(
  $$delete from storage.objects
    where id = 'e5100000-0000-0000-0000-000000000099'$$,
  'une suppression sans objet autorisé ne provoque aucune erreur'
);
reset role;

insert into storage.objects(
  id, bucket_id, name, owner, owner_id, metadata
) values (
  'e5100000-0000-0000-0000-000000000006',
  'profile-photos',
  'e5000000-0000-0000-0000-000000000003/other.webp',
  'e5000000-0000-0000-0000-000000000003',
  'e5000000-0000-0000-0000-000000000003',
  '{"mimetype":"image/webp"}'::jsonb
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e5000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select lives_ok(
  $$delete from storage.objects
    where id = 'e5100000-0000-0000-0000-000000000006'$$,
  'la tentative de suppression croisée est filtrée par la RLS'
);
reset role;

select is(
  (
    select count(*)
    from storage.objects
    where id = 'e5100000-0000-0000-0000-000000000006'
  ),
  1::bigint,
  'un joueur ne supprime pas la photo d’un autre compte'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e5000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

select lives_ok(
  $$insert into storage.objects(
      id, bucket_id, name, owner, owner_id, metadata
    ) values (
      'e5100000-0000-0000-0000-000000000007',
      'badge-images',
      'badge-admin.webp',
      'e5000000-0000-0000-0000-000000000001',
      'e5000000-0000-0000-0000-000000000001',
      '{"mimetype":"image/webp"}'::jsonb
    )$$,
  'un administrateur actif gère les images de badge'
);

select lives_ok(
  $$delete from storage.objects
    where id = 'e5100000-0000-0000-0000-000000000006'$$,
  'un administrateur actif peut nettoyer la photo d’un autre compte'
);

reset role;
select * from finish();
rollback;
