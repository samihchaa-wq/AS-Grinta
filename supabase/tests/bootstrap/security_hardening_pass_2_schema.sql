-- Objets internes nécessaires pour exercer localement la migration de sécurité.
-- Aucun contenu de production n'est copié.

create table if not exists public.push_delivery_log (
  id bigint primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  kind text not null check (
    kind in ('new_match', 'closing_soon', 'result_validated')
  ),
  profile_id uuid references public.profiles(id) on delete set null,
  endpoint_host text,
  success boolean not null,
  status_code integer,
  error_message text,
  created_at timestamptz not null default now()
);

create table if not exists public.season_awards (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  award_type text not null,
  created_at timestamptz not null default now(),
  unique (season_id, profile_id, award_type)
);

alter table public.push_delivery_log enable row level security;
alter table public.season_awards enable row level security;

-- RPC historique encore présente en production, mais volontairement absente du
-- baseline métier minimal. Elle est reproduite ici pour tester le retrait de son
-- droit EXECUTE au rôle authenticated.
create or replace function public.set_match_odds(
  p_match_id uuid,
  p_win numeric,
  p_draw numeric,
  p_loss numeric
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_win is null or p_draw is null or p_loss is null
     or p_win < 1.01 or p_draw < 1.01 or p_loss < 1.01
     or p_win > 100 or p_draw > 100 or p_loss > 100 then
    raise exception 'Invalid odds' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.status = 'a_venir'
  ) then
    raise exception 'Upcoming match not found' using errcode = 'P0002';
  end if;
  insert into public.match_odds(
    match_id,
    odds_victoire_as_grinta,
    odds_nul,
    odds_victoire_adverse,
    computed_at
  ) values (
    p_match_id,
    round(p_win, 2),
    round(p_draw, 2),
    round(p_loss, 2),
    now()
  )
  on conflict (match_id) do update
  set odds_victoire_as_grinta = excluded.odds_victoire_as_grinta,
      odds_nul = excluded.odds_nul,
      odds_victoire_adverse = excluded.odds_victoire_adverse,
      computed_at = now();
  return true;
end;
$function$;

revoke execute on function public.set_match_odds(
  uuid, numeric, numeric, numeric
) from public, anon;
grant execute on function public.set_match_odds(
  uuid, numeric, numeric, numeric
) to authenticated, service_role;
