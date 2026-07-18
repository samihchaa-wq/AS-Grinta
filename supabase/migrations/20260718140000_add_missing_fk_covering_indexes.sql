-- Index couvrant les clés étrangères non indexées (signalées par l'advisor
-- performance Supabase). Évite les scans séquentiels sur ces jointures et sur
-- les suppressions en cascade.
create index if not exists profile_badges_awarded_by_idx
  on public.profile_badges (awarded_by);
create index if not exists profile_badges_badge_id_idx
  on public.profile_badges (badge_id);
create index if not exists season_awards_profile_id_idx
  on public.season_awards (profile_id);
