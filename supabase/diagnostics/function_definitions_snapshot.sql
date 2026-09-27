-- Instantané, en lecture seule, des fonctions des schémas `public` et `private`.
--
-- Utilisé par `.github/workflows/function_definition_drift.yml` : la même
-- requête est lancée sur la base reconstruite depuis le dépôt et sur la
-- production, puis `tool/compare_function_definitions.py` compare les deux
-- résultats. Les fonctions installées par une extension (pgTAP, etc.) sont
-- exclues : elles ne viennent pas des migrations du projet.
--
-- Aucune donnée métier n'est lue : uniquement le catalogue de PostgreSQL.

select coalesce(json_agg(f order by f.signature), '[]'::json) as snapshot
from (
  select
    n.nspname || '.' || p.proname
      || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
      as signature,
    pg_catalog.pg_get_userbyid(p.proowner) as owner,
    p.prokind::text as kind,
    l.lanname as language,
    p.prosecdef as security_definer,
    p.provolatile::text as volatility,
    coalesce(p.proconfig, '{}'::text[]) as config,
    pg_catalog.pg_get_function_arguments(p.oid) as arguments,
    pg_catalog.pg_get_function_result(p.oid) as result,
    p.prosrc as body,
    (
      select coalesce(json_agg(grants.item order by grants.item), '[]'::json)
      from (
        select distinct
          case
            when acl.grantee = 0 then 'PUBLIC'
            else pg_catalog.pg_get_userbyid(acl.grantee)
          end
          || ':' || acl.privilege_type
          || case when acl.is_grantable then ' WITH GRANT OPTION' else '' end
            as item
        from pg_catalog.aclexplode(
          coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) acl
      ) grants
    ) as grants
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  join pg_catalog.pg_language l on l.oid = p.prolang
  where n.nspname in ('public', 'private')
    and not exists (
      select 1
      from pg_catalog.pg_depend d
      where d.classid = 'pg_catalog.pg_proc'::regclass
        and d.objid = p.oid
        and d.deptype = 'e'
    )
) f;
