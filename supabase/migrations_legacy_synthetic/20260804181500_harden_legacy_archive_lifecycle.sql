begin;

-- Legacy compatibility RPC: archiving is a post-finalization action only.
-- Keep the existing staff/grant/error contract, but prevent archive from being
-- used as an intermediate state to bypass the post-game finalization guard.
create or replace function public.archive_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  select m.status
  into v_status
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found or v_status = 'archive' then
    raise exception 'Non-archived match not found' using errcode = 'P0002';
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

revoke execute on function public.archive_match(uuid) from public, anon;
grant execute on function public.archive_match(uuid) to authenticated, service_role;

-- Defense in depth for direct table updates and older RPCs: a match may only
-- enter the archive state after it has genuinely been finalized.
create or replace function private.guard_match_archive_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
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
