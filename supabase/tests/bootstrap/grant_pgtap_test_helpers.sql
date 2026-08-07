-- Le rejeu CI installe un schéma métier compact puis les migrations récentes
-- explicitement. Ces migrations de la PR doivent être présentes avant le
-- lancement des fichiers pgTAP. Elles sont rejouées dans une transaction,
-- comme une migration Supabase, afin que les tables temporaires ON COMMIT DROP
-- restent disponibles jusqu'à la fin du lot.
begin;
\ir ../../migrations/20260807110000_canonical_player_identity.sql
\ir ../../migrations/20260807111000_canonical_historical_player_links.sql
\ir ../../migrations/20260807112000_exclude_archive_staff_from_players.sql
\ir ../../migrations/20260807113000_canonical_player_security_floor.sql
-- Le bootstrap minimal embarque d'anciennes versions des RPC présence/HDM :
-- on conserve leur comportement de test en qualifiant les identifiants devenus
-- ambigus avec season_players.player_id.
\ir current_match_result_player_rpcs.sql
-- Les tests de charge désactivent volontairement les triggers. Ces defaults ne
-- s'activent qu'en mode replica et n'existent donc jamais en production.
\ir canonical_player_direct_fixture_defaults.sql
commit;

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
