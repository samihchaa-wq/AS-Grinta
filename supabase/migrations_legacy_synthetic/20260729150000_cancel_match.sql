-- Permet à l'admin d'annuler un match sans le supprimer : le match reste
-- visible (les joueurs restent informés) mais n'est plus cliquable côté
-- client, contrairement à delete_match qui supprime tout définitivement.

alter table public.matches
  drop constraint matches_status_check;

alter table public.matches
  add constraint matches_status_check
  check (status = any (array['a_venir'::text, 'termine'::text, 'archive'::text, 'annule'::text]));

create or replace function public.cancel_match(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;

  update public.matches
  set status = 'annule'
  where id = p_match_id;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  return true;
end;
$$;

grant execute on function public.cancel_match(uuid) to authenticated;
