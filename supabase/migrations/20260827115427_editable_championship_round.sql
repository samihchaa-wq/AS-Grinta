-- La journée de championnat appartient au calendrier de la ligue, pas à
-- l'application : elle ne peut pas être déduite de l'ordre des matchs.
--
-- Le club joue rarement toutes les journées d'une saison (2025-2026 :
-- 19 rencontres jusqu'à la J26). Numéroter automatiquement dans l'ordre de
-- création ou de date produit donc des journées fausses dès qu'une journée
-- est sautée, et rien ne permettait de les corriger.
--
-- Cette migration :
--   1. rend la journée modifiable par un administrateur ;
--   2. garantit qu'une journée saisie n'est plus jamais réécrite par le
--      serveur, y compris quand le match est reporté à une date ultérieure.
--
-- Le numéro automatique reste le comportement par défaut à la création
-- (journée suivante de la saison), simplement il n'est plus imposé.

alter table public.matches
  drop constraint if exists matches_championship_round_check;

alter table public.matches
  add constraint matches_championship_round_check
  check (championship_round is null or championship_round > 0);

comment on column public.matches.championship_round is
  'Journée du championnat, telle que fixée par la ligue. Attribuée '
  'automatiquement à la création puis maintenue ; un administrateur peut la '
  'corriger via admin_set_match_championship_round.';

-- Attribution : automatique seulement en l'absence de valeur connue.
--
-- Remplace la règle de report « une rencontre repoussée devient J+1 de la
-- plus haute autre journée ». Cette règle écrasait la journée réelle de la
-- ligue à chaque changement de date ; la journée saisie est désormais
-- conservée telle quelle.
create or replace function private.assign_match_championship_round()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_next integer;
begin
  if new.match_type <> 'championnat' then
    new.championship_round := null;
    return new;
  end if;

  -- Sérialise la numérotation par saison. La ligne de saison sert de verrou
  -- naturel pour que deux créations simultanées ne reçoivent pas le même
  -- numéro de journée.
  perform 1
  from public.seasons s
  where s.id = new.season_id
  for update;

  -- Sur une modification, une journée déjà connue est conservée : seule la
  -- ligue peut la changer, et l'administrateur la saisit explicitement.
  if tg_op = 'UPDATE' and new.championship_round is null then
    new.championship_round := old.championship_round;
  end if;

  if new.championship_round is null then
    select coalesce(max(m.championship_round), 0) + 1
    into v_next
    from public.matches m
    where m.season_id = new.season_id
      and m.match_type = 'championnat'
      and m.id <> new.id;
    new.championship_round := v_next;
  end if;

  return new;
end;
$function$;

revoke all on function private.assign_match_championship_round()
  from public, anon, authenticated;

-- Correction manuelle de la journée par un administrateur.
--
-- p_championship_round null rend la main au numéro automatique (journée
-- suivante de la saison), via le déclencheur ci-dessus.
create or replace function public.admin_set_match_championship_round(
  p_match_id uuid,
  p_championship_round integer
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required' using errcode = '22023';
  end if;
  if p_championship_round is not null and p_championship_round <= 0 then
    raise exception 'La journée doit être un nombre positif.'
      using errcode = '22023';
  end if;

  select match.match_type
  into v_match_type
  from public.matches match
  where match.id = p_match_id
  for update;

  if not found then
    raise exception 'Match not found' using errcode = 'P0002';
  end if;
  if v_match_type is distinct from 'championnat' then
    raise exception 'Seul un match de championnat porte une journée.'
      using errcode = '22023';
  end if;

  update public.matches
  set championship_round = p_championship_round,
      updated_at = now()
  where id = p_match_id;
end;
$function$;

revoke all on function public.admin_set_match_championship_round(uuid, integer)
  from public, anon;
grant execute on function public.admin_set_match_championship_round(uuid, integer)
  to authenticated, service_role;
