-- V1 — Durcissement (point 4) : seuls les comptes VALIDÉS (status='active')
-- peuvent déposer des pronostics. Un inscrit « en attente » possède un JWT
-- valide mais ne doit rien pouvoir écrire tant que Samih ne l'a pas validé.
--
-- V1 — Pronostics de saison (point 5) : ils restent visibles par tous, mais
-- le staff peut les « fermer » manuellement quand il le décide (verrou porté
-- par la saison), à l'image de la clôture manuelle des matchs.

-- 1) Verrou des pronostics de saison, porté par la saison.
alter table public.seasons
  add column if not exists season_predictions_locked_at timestamptz;

-- 2) Le profil courant est-il actif (validé) ?
create or replace function public.is_active_profile()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and status = 'active'
  );
$$;

grant execute on function public.is_active_profile() to authenticated;

-- 3) Pronostics de match : compte validé requis (en plus de la fenêtre H-5).
drop policy if exists match_predictions_owner_insert on public.match_predictions;
create policy match_predictions_owner_insert on public.match_predictions
  for insert to authenticated
  with check (
    profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.matches m
      where m.id = match_predictions.match_id
        and m.status = 'a_venir'
        and now() < (
          ((m.match_date + coalesce(m.match_time, '00:00:00'::time))
            at time zone 'Europe/Paris') - interval '5 minutes'
        )
    )
  );

drop policy if exists match_predictions_owner_update_window
  on public.match_predictions;
create policy match_predictions_owner_update_window on public.match_predictions
  for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (
    profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.matches m
      where m.id = match_predictions.match_id
        and m.status = 'a_venir'
        and now() < (
          ((m.match_date + coalesce(m.match_time, '00:00:00'::time))
            at time zone 'Europe/Paris') - interval '5 minutes'
        )
    )
  );

-- 4) Pronostics de saison : compte validé + saison ouverte et non verrouillée.
drop policy if exists season_predictions_owner_insert on public.season_predictions;
create policy season_predictions_owner_insert on public.season_predictions
  for insert to authenticated
  with check (
    predictor_profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.seasons s
      where s.id = season_predictions.season_id
        and s.status = 'open'
        and s.season_predictions_locked_at is null
    )
  );

drop policy if exists season_predictions_owner_update on public.season_predictions;
create policy season_predictions_owner_update on public.season_predictions
  for update to authenticated
  using (predictor_profile_id = (select auth.uid()))
  with check (
    predictor_profile_id = (select auth.uid())
    and public.is_active_profile()
    and exists (
      select 1 from public.seasons s
      where s.id = season_predictions.season_id
        and s.status = 'open'
        and s.season_predictions_locked_at is null
    )
  );

-- 5) RPC staff : ouvrir / fermer les pronostics de saison.
create or replace function public.set_season_predictions_lock(
  p_season_id uuid,
  p_locked boolean
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;
  update public.seasons
    set season_predictions_locked_at =
      case when p_locked then now() else null end
  where id = p_season_id;
  return found;
end;
$$;

grant execute on function public.set_season_predictions_lock(uuid, boolean)
  to authenticated;
