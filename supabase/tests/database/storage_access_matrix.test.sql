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
reset role;

-- Supabase Storage interdit volontairement les DELETE SQL directs, même au
-- propriétaire de la base. La suppression réelle passe par l’API Storage ; la CI
-- vérifie donc ici le contrat exact utilisé par cette API lors de l’évaluation RLS.
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile_photos_owner_delete'
      and cmd = 'DELETE'
      and qual ~ 'private\.is_active_profile'
      and qual ~ 'owner_id'
      and qual ~ 'auth\.uid'
  ),
  'un joueur actif ne supprime que les objets dont owner_id correspond à son JWT'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile_photos_admin_write'
      and cmd = 'ALL'
      and qual ~ 'private\.is_admin'
      and with_check ~ 'private\.is_admin'
  ),
  'le nettoyage transversal des photos reste réservé à un administrateur actif'
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

reset role;
select * from finish();
rollback;
