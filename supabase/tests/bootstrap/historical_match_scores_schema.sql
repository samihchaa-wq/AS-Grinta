-- Pré-requis minimal pour les politiques RLS explicites et leur matrice de test.

create table if not exists public.historical_match_scores (
  id uuid primary key,
  opponent_id uuid not null references public.opponents(id) on delete restrict,
  match_date date not null,
  score_as_grinta smallint not null check (score_as_grinta between 0 and 99),
  score_adverse smallint not null check (score_adverse between 0 and 99)
);

revoke all on public.historical_match_scores from anon, authenticated;
grant all on public.historical_match_scores to service_role;
