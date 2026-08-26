begin;

-- Opponent names are labels, not identifiers. Staff may intentionally create
-- two distinct opponent records with the exact same display name.
alter table public.opponents
  drop constraint if exists opponents_name_key;

drop index if exists public.opponents_normalized_name_idx;
create index if not exists opponents_normalized_name_idx
  on public.opponents (lower(btrim(name)));

-- Keep the existing RPC signature used by the Flutter client, but make the
-- action match its UI meaning: creating an opponent always creates a distinct
-- opponent row. The UI warns on an exact duplicate name and requires an
-- explicit "Créer quand même" confirmation before calling this RPC.
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

  insert into public.opponents(name)
  values(normalized_name)
  returning id into opponent_id;

  return opponent_id;
end;
$$;

revoke all on function public.get_or_create_opponent(text) from public, anon;
grant execute on function public.get_or_create_opponent(text) to authenticated;

commit;
