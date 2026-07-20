begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('private.app_feature_flags') is not null,
  'la table privée des feature flags existe'
);
select ok(
  to_regclass('private.app_feature_flag_audit') is not null,
  'la table privée d’audit des transitions existe'
);

select is(
  (
    select enabled
    from private.app_feature_flags
    where key = 'sports_management'
  ),
  false,
  'le module de gestion sportive est désactivé par défaut'
);
select is(
  (
    select config ->> 'timezone'
    from private.app_feature_flags
    where key = 'sports_management'
  ),
  'Europe/Paris',
  'le fuseau horaire officiel est conservé côté serveur'
);
select is(
  (
    select (config ->> 'availability_open_hours_before')::integer
    from private.app_feature_flags
    where key = 'sports_management'
  ),
  144,
  'l’ouverture des disponibilités est configurée à 144 heures'
);
select is(
  (
    select (config ->> 'usual_squad_size')::integer
    from private.app_feature_flags
    where key = 'sports_management'
  ),
  14,
  'la taille habituelle de convocation est configurée à 14'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.app_feature_flags'::regclass
  ),
  'RLS est activée sur la table privée des flags'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.app_feature_flag_audit'::regclass
  ),
  'RLS est activée sur la table privée d’audit'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.app_feature_flags',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.app_feature_flags',
    'UPDATE'
  ),
  'les utilisateurs authentifiés ne peuvent ni lire ni modifier directement les flags'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'private.app_feature_flag_audit',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.app_feature_flag_audit',
    'INSERT'
  ),
  'les utilisateurs authentifiés ne peuvent pas accéder directement à l’audit'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_public_feature_flags()',
    'EXECUTE'
  ),
  'la lecture publique sûre est disponible aux utilisateurs connectés'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.set_sports_management_enabled(boolean,text)',
    'EXECUTE'
  ),
  'le point d’entrée d’administration est disponible aux utilisateurs connectés'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_feature_flags()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.set_sports_management_enabled(boolean,text)',
    'EXECUTE'
  ),
  'aucune RPC du feature flag n’est exposée au rôle anonyme'
);

select ok(
  not (
    select p.prosecdef
    from pg_proc p
    where p.oid = 'public.get_public_feature_flags()'::regprocedure
  )
  and not (
    select p.prosecdef
    from pg_proc p
    where p.oid =
      'public.set_sports_management_enabled(boolean,text)'::regprocedure
  ),
  'les RPC publiques restent SECURITY INVOKER'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    where p.oid = 'private.is_feature_enabled(text)'::regprocedure
  )
  and (
    select p.prosecdef
    from pg_proc p
    where p.oid = 'private.get_public_feature_flags()'::regprocedure
  )
  and (
    select p.prosecdef
    from pg_proc p
    where p.oid =
      'private.set_sports_management_enabled(boolean,text)'::regprocedure
  ),
  'les accès privilégiés sont isolés dans le schéma privé'
);

select is(
  (
    select count(*)
    from unnest(array[
      'private.is_feature_enabled(text)',
      'private.get_public_feature_flags()',
      'private.set_sports_management_enabled(boolean,text)',
      'public.get_public_feature_flags()',
      'public.set_sports_management_enabled(boolean,text)'
    ]::text[]) as expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    where not coalesce(p.proconfig, '{}'::text[])
      @> array['search_path=""']
  ),
  0::bigint,
  'toutes les fonctions du feature flag utilisent un search_path vide'
);

select is(
  (
    public.get_public_feature_flags()
      #>> '{sports_management,enabled}'
  )::boolean,
  false,
  'la RPC de lecture renvoie la valeur serveur désactivée'
);

select * from finish();
rollback;
