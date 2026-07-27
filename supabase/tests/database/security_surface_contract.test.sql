begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity
      and not exists (
        select 1
        from pg_depend dependency
        where dependency.classid = 'pg_class'::regclass
          and dependency.objid = c.oid
          and dependency.deptype = 'e'
      )
  ),
  0::bigint,
  'toutes les tables applicatives publiques ont la RLS active'
);

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm', 'S')
      and (
        has_table_privilege('anon', c.oid, 'SELECT')
        or has_table_privilege('anon', c.oid, 'INSERT')
        or has_table_privilege('anon', c.oid, 'UPDATE')
        or has_table_privilege('anon', c.oid, 'DELETE')
      )
  ),
  0::bigint,
  'le rôle anon ne possède aucun droit de données dans public'
);

select diag(
  'fonctions encore exposées dans le schéma isolé: ' || coalesce(
    (
      select string_agg(
        format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)),
        ', ' order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
      )
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      left join pg_depend dependency
        on dependency.classid = 'pg_proc'::regclass
       and dependency.objid = p.oid
       and dependency.deptype = 'e'
      left join pg_extension extension
        on extension.oid = dependency.refobjid
      cross join lateral aclexplode(
        coalesce(p.proacl, acldefault('f', p.proowner))
      ) acl
      where n.nspname in ('public', 'private')
        and coalesce(extension.extname, '') <> 'pgtap'
        and p.oid is distinct from to_regprocedure('public.like(text,text,text)')
        and acl.privilege_type = 'EXECUTE'
        and (
          acl.grantee = 0
          or acl.grantee = (select oid from pg_roles where rolname = 'anon')
        )
    ),
    '<aucune>'
  )
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    left join pg_depend dependency
      on dependency.classid = 'pg_proc'::regclass
     and dependency.objid = p.oid
     and dependency.deptype = 'e'
    left join pg_extension extension
      on extension.oid = dependency.refobjid
    cross join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) acl
    where n.nspname in ('public', 'private')
      and coalesce(extension.extname, '') <> 'pgtap'
      and p.oid is distinct from to_regprocedure('public.like(text,text,text)')
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0
        or acl.grantee = (select oid from pg_roles where rolname = 'anon')
      )
  ),
  0::bigint,
  'aucune fonction applicative n’est exécutable par PUBLIC ou anon'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'le schéma private reste invisible au rôle anon'
);

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and not coalesce(c.reloptions, '{}'::text[]) @> array['security_invoker=true']
  ),
  0::bigint,
  'toutes les vues publiques utilisent les droits de l’appelant'
);

select is(
  (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not exists (
        select 1
        from pg_depend dependency
        where dependency.classid = 'pg_class'::regclass
          and dependency.objid = c.oid
          and dependency.deptype = 'e'
      )
  ),
  (
    select count(distinct policy.tablename)
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.policyname = 'active_authenticated_profile_only'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'ALL'
      and policy.roles = array['authenticated']::name[]
  ),
  'chaque table applicative publique exige un profil authentifié actif'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'la RPC effectif est accordée explicitement aux seuls rôles attendus'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'private.save_match_effectif(uuid,integer,jsonb,text)',
    'EXECUTE'
  ),
  'le relais privé effectif n’hérite plus d’un droit PUBLIC'
);

select is(
  (
    select file_size_limit
    from storage.buckets
    where id = 'profile-photos'
  ),
  5242880::bigint,
  'les photos de profil sont limitées à 5 Mo côté Storage'
);

select is(
  (
    select file_size_limit
    from storage.buckets
    where id = 'badge-images'
  ),
  5242880::bigint,
  'les images de badge sont limitées à 5 Mo côté Storage'
);

select ok(
  (
    select allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']
      and cardinality(allowed_mime_types) = 3
    from storage.buckets
    where id = 'profile-photos'
  )
  and (
    select allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']
      and cardinality(allowed_mime_types) = 3
    from storage.buckets
    where id = 'badge-images'
  ),
  'les deux buckets n’acceptent que JPEG, PNG et WebP'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile_photos_owner_insert'
      and with_check ~ 'private\.is_active_profile'
      and with_check ~ 'owner_id'
      and with_check ~ 'foldername'
  ),
  'l’upload de profil vérifie activité, propriétaire et dossier'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'badge_images_admin_insert'
      and with_check ~ 'private\.is_match_staff'
  ),
  'l’écriture des badges reste réservée au staff actif'
);

select * from finish();
rollback;
