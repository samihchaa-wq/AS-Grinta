-- Les tests changent volontairement de rôle en cours de transaction. Le verrou
-- applicatif ne doit pas empêcher l’exécution des assertions pgTAP dans la base
-- éphémère de CI. Production ne possède pas cette extension.
grant usage on schema extensions to anon, authenticated;
grant execute on all functions in schema extensions to anon, authenticated;

-- Selon la version de l’image locale, certaines aides peuvent rester dans public.
-- On accorde uniquement les noms d’assertions pgTAP réellement utilisés et on les
-- marque pour que le contrat ACL puisse les distinguer des fonctions applicatives.
do $block$
declare
  helper record;
begin
  for helper in
    select p.oid::regprocedure as signature, n.nspname as schema_name
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
    execute format(
      'comment on function %s is %L',
      helper.signature,
      'test-only pgtap role assertion helper'
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
