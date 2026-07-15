-- Refonte du catalogue de badges autour de 3 mécaniques :
--   * tier  : paliers cumulatifs (carrière) sur une stat, échelle 1..1000
--   * title : titres décernés à la clôture d'une saison (cumulables)
--   * custom: badges créés et décernés à la main par l'admin
-- + colonne `category` pour le regroupement d'affichage.

alter table public.badges add column if not exists kind text not null default 'tier';
alter table public.badges add column if not exists category text not null default 'all_time';

-- Titres décernés par saison (cumulables sur plusieurs saisons).
create table if not exists public.profile_titles (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  season_name text,
  awarded_at timestamptz not null default now(),
  primary key (profile_id, badge_id, season_id)
);
create index if not exists profile_titles_profile_idx on public.profile_titles(profile_id);
alter table public.profile_titles enable row level security;
drop policy if exists profile_titles_read on public.profile_titles;
create policy profile_titles_read on public.profile_titles
  for select to authenticated using (true);
grant select on public.profile_titles to authenticated;

-- On repart d'un catalogue propre (les anciennes attributions cascade).
delete from public.badges;

-- 1) Paliers, échelle 1..1000, pour chaque stat.
with metrics(metric, emoji, label, family, category, base) as (values
  ('goals',        '⚽',  'buts',          'joueur',        'all_time',     100),
  ('appearances',  '👕',  'matchs',        'joueur',        'all_time',     200),
  ('clean_sheets', '🧤',  'clean sheets',  'joueur',        'all_time',     300),
  ('mvp',          '🏆',  'HDM',           'joueur',        'faits_de_jeu', 400),
  ('exact_scores', '🎯',  'scores exacts', 'pronostiqueur', 'pronos',       500),
  ('good_bets',    '✅',  'bons paris',    'pronostiqueur', 'pronos',       600)
), ladder(threshold, ord) as (
  select t, row_number() over ()
  from unnest(array[1,5,10,20,50,100,200,300,400,500,600,700,800,900,1000]) as t
)
insert into public.badges(code, name, description, emoji, family, auto, kind, category, metric, threshold, sort_order)
select m.metric || '_' || l.threshold,
       l.threshold || ' ' || m.label,
       'Atteindre ' || l.threshold || ' ' || m.label || '.',
       m.emoji,
       m.family,
       true,
       'tier',
       m.category,
       m.metric,
       l.threshold,
       m.base + l.ord::int
from metrics m cross join ladder l;

-- 2) Titres de saison (décernés à la clôture). metric = classement utilisé,
--    threshold = rang cible (1/2/3).
insert into public.badges(code, name, description, emoji, family, auto, kind, category, metric, threshold, sort_order) values
  ('title_top_scorer_1', 'Meilleur buteur',            'Meilleur buteur de la saison.',                      '🥇', 'joueur',        false, 'title', 'saison', 'season_goals',        1, 700),
  ('title_top_scorer_2', '2e meilleur buteur',         'Deuxième meilleur buteur de la saison.',             '🥈', 'joueur',        false, 'title', 'saison', 'season_goals',        2, 701),
  ('title_top_scorer_3', '3e meilleur buteur',         'Troisième meilleur buteur de la saison.',            '🥉', 'joueur',        false, 'title', 'saison', 'season_goals',        3, 702),
  ('title_most_mvp',     'Plus d''HDM',                'Le plus d''homme du match sur la saison.',           '🏆', 'joueur',        false, 'title', 'saison', 'season_mvp',          1, 703),
  ('title_best_winrate', 'Meilleur taux de victoire',  'Meilleur taux de victoire (≥ 50 % des matchs joués).', '📈', 'joueur',        false, 'title', 'saison', 'season_winrate',      1, 704),
  ('title_prono_match',  'Meilleur pronostiqueur — matchs',  'Premier du classement matchs de la saison.',   '🎯', 'pronostiqueur', false, 'title', 'pronos', 'season_prono_match',  1, 710),
  ('title_prono_season', 'Meilleur pronostiqueur — saison',  'Premier du classement saison.',                '📅', 'pronostiqueur', false, 'title', 'pronos', 'season_prono_season', 1, 711),
  ('title_general_1',    'Top 1 pronostiqueur',        'Premier du classement général de la saison.',        '🏆', 'pronostiqueur', false, 'title', 'pronos', 'season_prono_general', 1, 712),
  ('title_general_2',    'Top 2 pronostiqueur',        'Deuxième du classement général de la saison.',       '🥈', 'pronostiqueur', false, 'title', 'pronos', 'season_prono_general', 2, 713),
  ('title_general_3',    'Top 3 pronostiqueur',        'Troisième du classement général de la saison.',      '🥉', 'pronostiqueur', false, 'title', 'pronos', 'season_prono_general', 3, 714);

-- Repeuple les paliers automatiques avec le nouveau catalogue.
select public.recalculate_all_badges();
