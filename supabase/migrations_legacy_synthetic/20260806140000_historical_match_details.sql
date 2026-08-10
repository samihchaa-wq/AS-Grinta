-- Détail par match de l'historique importé (composition, buteurs, HDM),
-- en complément du score compact de historical_match_scores. Verrouillée
-- comme le reste de l'historique : accès uniquement via RPC.
create table public.historical_match_details (
  match_id uuid primary key references public.historical_match_scores(id) on delete cascade,
  formation text,
  field_players jsonb not null default '[]'::jsonb,
  bench_players jsonb not null default '[]'::jsonb,
  present_names jsonb not null default '[]'::jsonb,
  scorers jsonb not null default '[]'::jsonb,
  motm_names jsonb not null default '[]'::jsonb
);

alter table public.historical_match_details enable row level security;

create policy deny_client_access
  on public.historical_match_details
  as restrictive for all to anon, authenticated
  using (false)
  with check (false);

create policy active_authenticated_profile_only
  on public.historical_match_details
  as restrictive for all to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

comment on table public.historical_match_details is
  'Composition (facultative), buteurs et HDM importés par match historique ; lecture uniquement via get_historical_match_detail.';

grant all on table public.historical_match_details to service_role;

-- RPC de lecture, même durcissement (private + wrapper public) que le reste
-- de l'historique.

create function private.get_historical_match_detail(
  p_match_id uuid
)
returns table (
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  scorers jsonb,
  motm_names jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select d.formation, d.field_players, d.bench_players, d.present_names,
         d.scorers, d.motm_names
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$function$;

revoke all on function private.get_historical_match_detail(uuid) from public, anon;
grant execute on function private.get_historical_match_detail(uuid) to authenticated, service_role;

create function public.get_historical_match_detail(
  p_match_id uuid
)
returns table (
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  scorers jsonb,
  motm_names jsonb
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.get_historical_match_detail(p_match_id);
$function$;

revoke all on function public.get_historical_match_detail(uuid) from public, anon;
grant execute on function public.get_historical_match_detail(uuid) to authenticated, service_role;

comment on function public.get_historical_match_detail(uuid) is
  'Read-only historical match detail (composition/buteurs/HDM) for one match_id; authorization is enforced by a private helper.';
