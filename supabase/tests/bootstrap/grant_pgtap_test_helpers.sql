-- La baseline CI omet volontairement certaines anciennes migrations devenues
-- trop larges pour être rejouées en fin de chaîne. On restaure ici uniquement
-- le schéma minimal de composition interne requis par le durcissement courant.
\ir internal_composition_schema.sql

-- La migration historique ci-dessous complète la baseline minimale avec les
-- contrats notifications/HDM attendus par le reste des tests. La règle de cycle
-- de vie courante est rejouée juste après afin qu'elle reste, comme en production,
-- la définition finale du scrutin HDM.
\ir ../../migrations/20260803183000_harden_notifications_motm_and_hot_paths.sql
\ir ../../migrations/20260804183000_anchor_motm_to_validation.sql

-- Les tests changent volontairement de rôle en cours de transaction. Le verrou
-- applicatif ne doit pas empêcher l’exécution des assertions pgTAP dans la base
-- éphémère de CI. Production ne possède pas cette extension.
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

-- Certains scénarios créent une fonction pg_temp avant de basculer vers le rôle
-- authenticated. Le droit par défaut est rétabli uniquement dans cette base de
-- test éphémère ; la migration de production conserve le défaut sécurisé.
alter default privileges grant execute on functions to authenticated;

-- Selon la version de l’image locale, certaines aides peuvent rester dans public.
-- On accorde uniquement les noms d’assertions pgTAP réellement utilisés.
do $block$
declare
  helper record;
begin
  for helper in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'extensions')
      and p.proname in (
        'plan', 'no_plan', 'finish', 'ok', 'is', 'isnt', 'pass', 'fail',
        'throws_ok', 'throws_like', 'throws_ilike', 'lives_ok', 'like',
        'unlike', 'cmp_ok', 'is_empty', 'isnt_empty', 'results_eq',
        'set_eq', 'bag_eq', 'row_eq', 'has_function', 'has_table',
        'has_column', 'has_policy', 'has_trigger', 'is_definer',
        'isnt_definer', 'function_privs_are', 'table_privs_are',
        'schema_privs_are', 'policies_are', 'col_type_is'
      )
  loop
    execute format(
      'grant execute on function %s to anon, authenticated',
      helper.signature
    );
  end loop;
end;
$block$;

-- Échec immédiat et explicite si l’image locale expose encore une surcharge de
-- throws_ok non exécutable par le rôle anon utilisé dans les tests RLS.
do $block$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'extensions')
      and p.proname = 'throws_ok'
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) then
    raise exception 'pgTAP throws_ok is not executable by anon in test database';
  end if;
end;
$block$;
