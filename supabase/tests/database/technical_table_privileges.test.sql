begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Les rôles de l'application n'ont aucun droit technique TRUNCATE, TRIGGER ou
-- REFERENCES sur le schéma public, ni sur les tables existantes ni sur celles
-- que les prochaines migrations créeront.

select is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
    where n.nspname = 'public'
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
      and a.grantee in ('anon'::regrole, 'authenticated'::regrole)
      and a.privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
  ),
  0,
  'anon et authenticated n’ont ni TRUNCATE, ni TRIGGER, ni REFERENCES sur public'
);

select is(
  (
    select count(*)::int
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
    cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and n.nspname = 'public'
      and d.defaclobjtype = 'r'
      and a.grantee in ('anon'::regrole, 'authenticated'::regrole)
      and a.privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
  ),
  0,
  'les privilèges par défaut des futures tables ne les accordent plus'
);

create table public.technical_privileges_probe(id integer primary key);

select ok(
  not has_table_privilege('authenticated', 'public.technical_privileges_probe', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.technical_privileges_probe', 'TRIGGER')
  and not has_table_privilege('authenticated', 'public.technical_privileges_probe', 'REFERENCES')
  and not has_table_privilege('anon', 'public.technical_privileges_probe', 'TRUNCATE')
  and not has_table_privilege('anon', 'public.technical_privileges_probe', 'TRIGGER')
  and not has_table_privilege('anon', 'public.technical_privileges_probe', 'REFERENCES'),
  'une nouvelle table créée par une migration n’accorde pas ces droits'
);

select ok(
  has_table_privilege('authenticated', 'public.technical_privileges_probe', 'SELECT'),
  'les autres privilèges par défaut sont conservés'
);

select * from finish();
rollback;
