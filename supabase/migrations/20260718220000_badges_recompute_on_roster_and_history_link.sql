-- Correctif : un joueur fraîchement ajouté (ou rattaché à son historique) ne
-- recevait pas ses badges avant le prochain match/archivage de saison, car le
-- moteur ne se recalculait que sur changement de match ou clôture de saison.
-- On recalcule désormais les badges d'un profil dès qu'il rejoint un effectif
-- ou qu'on lie une ligne d'historique à son profil.

-- 1) Ajout / rattachement dans un effectif de saison.
create or replace function public.trg_badges_on_roster_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;
  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_roster on public.season_players;
create trigger trg_badges_roster
  after insert or update of profile_id, first_name, last_name, season_id
  on public.season_players
  for each row execute function public.trg_badges_on_roster_change();

-- 2) Rattachement d'une ligne d'historique à un profil.
create or replace function public.trg_badges_on_historical_link()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.profile_id is not null then
    perform public.recalculate_profile_badges(new.profile_id);
  end if;
  if tg_op = 'UPDATE'
     and old.profile_id is not null
     and old.profile_id is distinct from new.profile_id then
    perform public.recalculate_profile_badges(old.profile_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_badges_historical_link on public.historical_player_statistics;
create trigger trg_badges_historical_link
  after insert or update of profile_id
  on public.historical_player_statistics
  for each row execute function public.trg_badges_on_historical_link();

-- 3) Rattrapage immédiat pour tous les profils existants (dont les joueurs
--    récemment ajoutés qui n'avaient pas encore leurs badges).
select public.recalculate_all_badges();
