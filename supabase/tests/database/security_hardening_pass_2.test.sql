begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  not has_function_privilege(
    'authenticated',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)',
    'EXECUTE'
  ),
  'la finalisation interne historique n’est plus une RPC client'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.staff_set_match_attendance(uuid,uuid[])',
    'EXECUTE'
  ),
  'la présence est modifiée uniquement par la finalisation atomique'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.staff_set_match_mvp(uuid,uuid[])',
    'EXECUTE'
  ),
  'le MVP est modifié uniquement par la finalisation atomique'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.set_match_odds(uuid,numeric,numeric,numeric)',
    'EXECUTE'
  ),
  'l’ancienne RPC de cotes n’est plus directement exposée'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)',
    'EXECUTE'
  ),
  'le service interne conserve la finalisation historique'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.staff_set_match_attendance(uuid,uuid[])',
    'EXECUTE'
  ),
  'le service interne conserve la gestion des présences'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.staff_set_match_mvp(uuid,uuid[])',
    'EXECUTE'
  ),
  'le service interne conserve la gestion du MVP'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.set_match_odds(uuid,numeric,numeric,numeric)',
    'EXECUTE'
  ),
  'le service interne conserve l’ancienne RPC de cotes'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.finalize_match_postgame_with_lineup(uuid,integer,jsonb,uuid,integer,uuid[],uuid)',
    'EXECUTE'
  ),
  'la finalisation atomique reste disponible aux administrateurs connectés'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_match_with_odds(uuid,uuid,date,time without time zone,text,numeric,numeric,numeric)',
    'EXECUTE'
  ),
  'la création atomique match et cotes reste disponible'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.update_match_with_odds(uuid,uuid,uuid,date,time without time zone,text,text,numeric,numeric,numeric)',
    'EXECUTE'
  ),
  'la modification atomique match et cotes reste disponible'
);

select is(
  (
    select count(*)
    from unnest(array[
      'public.profile_badge_metrics(uuid)',
      'public.set_badge_featured(text,boolean)',
      'public.staff_award_badge(uuid,text)',
      'public.staff_create_badge(text,text,text,text,text,text)',
      'public.staff_list_historical_players()',
      'public.staff_revoke_badge(uuid,text)',
      'public.staff_set_historical_profile(uuid,bigint)',
      'public.staff_set_match_attendance(uuid,uuid[])',
      'public.staff_set_match_mvp(uuid,uuid[])'
    ]::text[]) as expected(signature)
    join pg_proc p on p.oid = to_regprocedure(expected.signature)
    where not coalesce(p.proconfig, '{}'::text[])
      @> array['search_path=""']
  ),
  0::bigint,
  'toutes les fonctions auditées présentes utilisent un search_path vide'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and policyname = 'push_delivery_log_deny_client_roles'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles @> array['anon', 'authenticated']::name[]
  ),
  1::bigint,
  'push_delivery_log possède une politique restrictive pour les clients'
);
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and policyname = 'season_awards_deny_client_roles'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
      and roles @> array['anon', 'authenticated']::name[]
  ),
  1::bigint,
  'season_awards possède une politique restrictive pour les clients'
);

select ok(
  not has_schema_privilege('public', 'public', 'CREATE')
    and not has_schema_privilege('anon', 'public', 'CREATE')
    and not has_schema_privilege('authenticated', 'public', 'CREATE'),
  'aucun rôle client ne peut créer un objet dans le schéma public'
);

select * from finish();
rollback;
