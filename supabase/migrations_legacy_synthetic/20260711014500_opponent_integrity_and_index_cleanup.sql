begin;

alter table public.opponents
  drop constraint if exists opponents_name_not_blank;
alter table public.opponents
  add constraint opponents_name_not_blank
  check (nullif(btrim(name),'') is not null);

create unique index if not exists opponents_normalized_name_idx
  on public.opponents (lower(btrim(name)));

drop index if exists public.seasons_single_open_idx;

create or replace function public.get_or_create_opponent(p_name text)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  normalized_name text := btrim(coalesce(p_name,''));
  opponent_id uuid;
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;

  if length(normalized_name) < 2 then
    raise exception 'Opponent name must contain at least 2 characters';
  end if;

  select id into opponent_id
  from public.opponents
  where lower(btrim(name))=lower(normalized_name)
  limit 1;

  if opponent_id is not null then
    return opponent_id;
  end if;

  insert into public.opponents(name)
  values(normalized_name)
  on conflict do nothing
  returning id into opponent_id;

  if opponent_id is null then
    select id into opponent_id
    from public.opponents
    where lower(btrim(name))=lower(normalized_name)
    limit 1;
  end if;

  if opponent_id is null then
    raise exception 'Opponent could not be created';
  end if;

  return opponent_id;
end;
$$;

revoke all on function public.get_or_create_opponent(text) from public,anon;
grant execute on function public.get_or_create_opponent(text) to authenticated;

revoke insert on public.opponents from authenticated;

commit;
