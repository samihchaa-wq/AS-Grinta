begin;

-- Trois droits techniques retirés aux rôles `anon` et `authenticated` sur les
-- tables et vues du schéma `public` : TRUNCATE (vider une table en ignorant
-- les règles d'accès), TRIGGER (y attacher un déclencheur) et REFERENCES (y
-- faire pointer une clé étrangère). L'application ne s'en sert jamais : elle
-- passe par l'API de Supabase, qui n'expose aucune de ces opérations, et par
-- des fonctions serveur.
--
-- La base reconstruite depuis le dépôt les accordait encore largement. Au
-- 27 septembre 2026, la production les avait déjà retirés sur la plupart des
-- tables, mais les accordait toujours à `authenticated` sur 18 tables et vues
-- (badges, club_events, club_settings, historical_match_details,
-- match_attendance, match_internal_composition_entries,
-- match_internal_compositions, match_man_of_match, match_player_stats,
-- match_sport_goal_actions, profile_badge_seen, profile_badges, season_awards,
-- v_player_season_stats, v_scorer_standings, v_season_match_count,
-- v_statistics_team, v_statistics_team_with_recent_results). La migration
-- les retire partout.
--
-- Les privilèges par défaut sont ajustés de la même façon pour les tables
-- que les prochaines migrations créeront. Aucun autre droit ne change.

revoke truncate, trigger, references
  on all tables in schema public
  from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from anon, authenticated;

commit;
