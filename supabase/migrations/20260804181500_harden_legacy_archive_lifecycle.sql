begin;

-- Legacy compatibility RPC: archiving is a post-finalization action only.
-- Keep the RPC available for older clients, but prevent it from being used
-- as an intermediate state to bypass the post-game finalization guard.
create or replace function public.archive_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'Admin role required' using errcode = '42501';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found then
    return false;
  end if;

  if v_status = 'archive' then
    return false;
  end if;

  if v_status <> 'termine' then
    raise exception 'Only a finished match can be archived'
      using errcode = '22023';
  end if;

  update public.matches
  set status = 'archive',
      updated_at = now()
  where id = p_match_id;

  return true;
end;
$$;

grant execute on function public.archive_match(uuid) to authenticated;

-- Defense in depth for direct table updates and older RPCs: a match may only
-- enter the archive state after it has genuinely been finalized.
create or replace function private.guard_match_archive_transition()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if new.status = 'archive'
     and old.status is distinct from 'archive'
     and old.status <> 'termine' then
    raise exception 'Only a finished match can be archived'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_match_archive_transition on public.matches;
create trigger trg_guard_match_archive_transition
before update of status on public.matches
for each row
execute function private.guard_match_archive_transition();

commit;
