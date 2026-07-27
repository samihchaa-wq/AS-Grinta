-- Les tests changent volontairement de rôle en cours de transaction. Le verrou
-- applicatif retire les droits PUBLIC/anon de toutes les fonctions de public ; on
-- réaccorde ici, uniquement dans la base éphémère de CI, les fonctions appartenant
-- à l’extension pgTAP nécessaires pour exécuter les assertions sous ces rôles.
do $block$
declare
  helper record;
begin
  for helper in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_depend dependency
      on dependency.classid = 'pg_proc'::regclass
     and dependency.objid = p.oid
     and dependency.deptype = 'e'
    join pg_extension extension
      on extension.oid = dependency.refobjid
    where extension.extname = 'pgtap'
  loop
    execute format(
      'grant execute on function %s to anon, authenticated',
      helper.signature
    );
  end loop;
end;
$block$;

grant execute on function public.like(text, text, text)
  to anon, authenticated;
