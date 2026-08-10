-- Badges : catalogue + attributions, rattachés au profil (l'identité unifiée
-- joueur = pronostiqueur). + suivi des présences sur match_player_stats.

-- 1) Suivi des présences : qui a joué le match (pas seulement les buteurs).
alter table public.match_player_stats
  add column if not exists played boolean not null default true;

-- 2) Catalogue des badges.
create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  description text not null,
  emoji text not null,
  family text not null check (family in ('joueur', 'pronostiqueur')),
  auto boolean not null default true,
  -- metric : base de calcul automatique (null = badge manuel).
  --   goals | clean_sheets | appearances | match_goals
  --   predictions | exact_scores | good_bets
  metric text,
  threshold integer,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- 3) Attributions : une personne (profil) reçoit un badge.
create table if not exists public.profile_badges (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  source text not null default 'auto' check (source in ('auto', 'manual')),
  awarded_at timestamptz not null default now(),
  awarded_by uuid references public.profiles(id) on delete set null,
  primary key (profile_id, badge_id)
);

create index if not exists profile_badges_profile_idx
  on public.profile_badges(profile_id);

-- 4) RLS : lecture pour les membres connectés ; écriture réservée aux
--    fonctions security definer (aucune policy d'écriture directe).
alter table public.badges enable row level security;
alter table public.profile_badges enable row level security;

drop policy if exists badges_read on public.badges;
create policy badges_read on public.badges
  for select to authenticated using (true);

drop policy if exists profile_badges_read on public.profile_badges;
create policy profile_badges_read on public.profile_badges
  for select to authenticated using (true);

grant select on public.badges to authenticated;
grant select on public.profile_badges to authenticated;

-- 5) Catalogue initial.
insert into public.badges (code, name, description, emoji, family, auto, metric, threshold, sort_order) values
  -- Joueur (automatiques)
  ('first_goal',  'Premier but',     'Marquer son premier but.',                       '⚽',  'joueur', true, 'goals',        1,   10),
  ('scorer_10',   'Buteur',          'Marquer 10 buts.',                               '🎯', 'joueur', true, 'goals',        10,  11),
  ('scorer_50',   'Machine à buts',  'Marquer 50 buts.',                               '💥', 'joueur', true, 'goals',        50,  12),
  ('hattrick',    'Triplé',          'Marquer 3 buts dans un même match.',             '🎩', 'joueur', true, 'match_goals',  3,   13),
  ('keeper_5',    'Rempart',         'Réaliser 5 clean sheets.',                       '🧤', 'joueur', true, 'clean_sheets', 5,   14),
  ('keeper_15',   'Mur',             'Réaliser 15 clean sheets.',                      '🧱', 'joueur', true, 'clean_sheets', 15,  15),
  ('caps_10',     'Fidèle',          'Disputer 10 matchs.',                            '👕', 'joueur', true, 'appearances',  10,  16),
  ('caps_50',     'Pilier',          'Disputer 50 matchs.',                            '🏛️', 'joueur', true, 'appearances',  50,  17),
  ('caps_100',    'Centurion',       'Disputer 100 matchs.',                           '💯', 'joueur', true, 'appearances',  100, 18),
  -- Pronostiqueur (automatiques)
  ('first_prono', 'Premier prono',   'Valider son premier pronostic.',                 '🔮', 'pronostiqueur', true, 'predictions',  1,  30),
  ('lynx_5',      'Œil de lynx',     'Trouver 5 scores exacts.',                       '🔭', 'pronostiqueur', true, 'exact_scores', 5,  31),
  ('devin_20',    'Devin',           'Trouver 20 scores exacts.',                      '🧠', 'pronostiqueur', true, 'exact_scores', 20, 32),
  ('bettor_25',   'Parieur avisé',   'Réussir 25 bons paris (bon vainqueur).',         '✅', 'pronostiqueur', true, 'good_bets',    25, 33),
  -- Manuels (admin)
  ('man_of_match','Homme du match',  'Désigné homme du match par l''admin.',           '🏆', 'joueur', false, null, null, 50),
  ('captain',     'Capitaine',       'Capitaine de l''équipe.',                        '🎖️', 'joueur', false, null, null, 51),
  ('legend',      'Légende du club', 'Légende de l''AS Grinta.',                        '🐐', 'joueur', false, null, null, 52)
on conflict (code) do nothing;
