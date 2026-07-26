begin;

-- Supprimer un joueur de l'effectif doit aussi nettoyer les données techniques
-- du module sportif qui le référencent. Les données fonctionnelles historiques
-- classiques (buts, présences, HDM et pronostics de saison) sont déjà en cascade.

alter table public.match_composition_entries
  drop constraint if exists match_composition_entries_participant_id_match_id_fkey;
alter table public.match_composition_entries
  add constraint match_composition_entries_participant_id_match_id_fkey
  foreign key (participant_id, match_id)
  references public.match_sport_participants(id, match_id)
  on delete cascade;

alter table public.match_sport_motm_results
  drop constraint if exists match_sport_motm_results_participant_id_match_id_fkey;
alter table public.match_sport_motm_results
  add constraint match_sport_motm_results_participant_id_match_id_fkey
  foreign key (participant_id, match_id)
  references public.match_sport_participants(id, match_id)
  on delete cascade;

alter table public.match_sport_motm_votes
  drop constraint if exists match_sport_motm_votes_candidate_participant_id_match_id_fkey;
alter table public.match_sport_motm_votes
  add constraint match_sport_motm_votes_candidate_participant_id_match_id_fkey
  foreign key (candidate_participant_id, match_id)
  references public.match_sport_participants(id, match_id)
  on delete cascade;

alter table public.match_sport_participant_events
  drop constraint if exists match_sport_participant_events_participant_id_match_id_fkey;
alter table public.match_sport_participant_events
  add constraint match_sport_participant_events_participant_id_match_id_fkey
  foreign key (participant_id, match_id)
  references public.match_sport_participants(id, match_id)
  on delete cascade;

alter table public.sport_availability_notification_events
  drop constraint if exists sport_availability_notification_ev_participant_id_match_id_fkey;
alter table public.sport_availability_notification_events
  add constraint sport_availability_notification_ev_participant_id_match_id_fkey
  foreign key (participant_id, match_id)
  references public.match_sport_participants(id, match_id)
  on delete cascade;

-- Une promotion vers un autre participant ne doit pas supprimer ce dernier :
-- on retire seulement le lien vers le participant supprimé.
alter table public.match_sport_participants
  drop constraint if exists match_sport_participants_promoted_from_participant_id_fkey;
alter table public.match_sport_participants
  add constraint match_sport_participants_promoted_from_participant_id_fkey
  foreign key (promoted_from_participant_id)
  references public.match_sport_participants(id)
  on delete set null;

alter table public.match_sport_participants
  drop constraint if exists match_sport_participants_season_player_id_fkey;
alter table public.match_sport_participants
  add constraint match_sport_participants_season_player_id_fkey
  foreign key (season_player_id)
  references public.season_players(id)
  on delete cascade;

alter table public.sport_waitlist_entries
  drop constraint if exists sport_waitlist_entries_season_player_id_season_id_fkey;
alter table public.sport_waitlist_entries
  add constraint sport_waitlist_entries_season_player_id_season_id_fkey
  foreign key (season_player_id, season_id)
  references public.season_players(id, season_id)
  on delete cascade;

commit;
