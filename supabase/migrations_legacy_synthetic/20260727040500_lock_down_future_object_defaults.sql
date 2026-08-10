begin;

-- Le droit EXECUTE de PUBLIC est un défaut global PostgreSQL : une règle limitée
-- à un schéma ne peut pas le soustraire. Il doit donc être retiré au niveau global
-- pour le rôle qui exécute les migrations.
alter default privileges
  revoke execute on functions from public;

-- Supabase ajoute aussi des privilèges client explicites dans public. On retire
-- uniquement anon ; authenticated et service_role restent accordés lorsque la
-- plateforme ou une migration les déclare explicitement.
alter default privileges in schema public
  revoke execute on functions from anon;
alter default privileges in schema private
  revoke execute on functions from anon;
alter default privileges in schema public
  revoke all on tables from anon;
alter default privileges in schema public
  revoke all on sequences from anon;

-- Sonde transactionnelle : une nouvelle fonction applicative ne doit plus
-- recevoir EXECUTE pour PUBLIC ou anon sans GRANT explicite.
create function public.__security_default_acl_probe()
returns integer
language sql
set search_path to ''
as $function$
  select 1;
$function$;

do $block$
begin
  if exists (
    select 1
    from pg_proc p
    cross join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) acl
    where p.oid = 'public.__security_default_acl_probe()'::regprocedure
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0
        or acl.grantee = (select oid from pg_roles where rolname = 'anon')
      )
  ) then
    raise exception 'Unsafe function default privileges remain active';
  end if;
end;
$block$;

drop function public.__security_default_acl_probe();

commit;
