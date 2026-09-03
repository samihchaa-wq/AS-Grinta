-- Quatre cles etrangeres n'ont aucun index qui les couvre. Postgres n'impose
-- pas d'index cote enfant : a chaque suppression d'une ligne parente il doit
-- parcourir toute la table enfant pour verifier qu'aucune ligne n'y renvoie.
-- Sur les volumes actuels c'est indolore, mais ces quatre tables grossissent
-- avec l'usage, pas avec l'effectif.
--
-- Aucune donnee n'est touchee : un index est une structure de lecture, ajoutee
-- a cote des lignes. Les tables sont assez petites pour que la creation soit
-- instantanee, donc pas besoin de CREATE INDEX CONCURRENTLY — qui serait de
-- toute facon refuse ici, une migration s'executant dans une transaction.

-- private.client_incident_log(profile_id)
--
-- Index compose plutot que sur la seule colonne de la cle : chaque ecriture
-- d'incident commence par compter les incidents du meme profil sur la derniere
-- minute, pour se limiter a vingt. Cette lecture-la est la seule requete
-- chaude de la table, et c'est aussi celle qui coute le plus cher a mesure que
-- le journal s'allonge. profile_id en tete couvre la cle etrangere.
create index if not exists client_incident_log_profile_created_idx
  on private.client_incident_log (profile_id, created_at desc);

-- private.match_live_score_commands(match_id)
--
-- La cle primaire est (actor_id, operation_id) : elle sert a rejeter un ordre
-- deja recu, pas a retrouver les ordres d'un match. Supprimer un match devait
-- donc parcourir tout le journal des ordres du direct.
create index if not exists match_live_score_commands_match_idx
  on private.match_live_score_commands (match_id);

-- public.season_prediction_roster_members(season_player_id)
-- public.season_wrapped(season_player_id)
--
-- Les deux tables ont season_player_id en deuxieme position de leur cle
-- primaire (season_id, season_player_id). Un index compose ne sert a retrouver
-- une ligne que si l'on connait sa premiere colonne : ici on cherche par
-- joueur sans connaitre la saison, donc la cle primaire n'aide pas.
create index if not exists season_prediction_roster_members_player_idx
  on public.season_prediction_roster_members (season_player_id);

create index if not exists season_wrapped_season_player_idx
  on public.season_wrapped (season_player_id);
