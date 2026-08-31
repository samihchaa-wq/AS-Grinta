create or replace function private.guard_internal_composition_t15()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_id uuid;
  v_match_type text;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  -- Preserve legitimate FK-cascade cleanup (match/player deletion) while guarding
  -- direct row mutations and the normal composition RPC write path.
  if pg_catalog.pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  select m.match_type
  into v_match_type
  from public.matches m
  where m.id = v_match_id;

  if not found then
    if tg_op = 'DELETE' then
      return old;
    end if;
    raise exception 'Match not found' using errcode = 'P0002';
  end if;

  if v_match_type is distinct from 'entre_nous' then
    raise exception 'La composition interne est réservée aux matchs entre nous.'
      using errcode = '22023';
  end if;

  perform private.assert_match_admin_edit_open(v_match_id);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_internal_composition_t15()
from public, anon, authenticated;
grant execute on function private.guard_internal_composition_t15()
to service_role;

drop trigger if exists trg_guard_internal_composition_t15
on public.match_internal_compositions;
create trigger trg_guard_internal_composition_t15
before insert or update or delete
on public.match_internal_compositions
for each row
execute function private.guard_internal_composition_t15();

drop trigger if exists trg_guard_internal_composition_entry_t15
on public.match_internal_composition_entries;
create trigger trg_guard_internal_composition_entry_t15
before insert or update or delete
on public.match_internal_composition_entries
for each row
execute function private.guard_internal_composition_t15();
