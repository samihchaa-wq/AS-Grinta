alter table public.coach_match_events
  add column if not exists scorer_guest_id text,
  add column if not exists assist_guest_id text,
  add column if not exists player_in_guest_id text,
  add column if not exists player_in_guest_name text,
  add column if not exists player_out_guest_id text,
  add column if not exists player_out_guest_name text;

alter table public.coach_match_events
  drop constraint if exists coach_match_events_scorer_guest_id_not_blank,
  drop constraint if exists coach_match_events_assist_guest_id_not_blank,
  drop constraint if exists coach_match_events_player_in_guest_id_not_blank,
  drop constraint if exists coach_match_events_player_out_guest_id_not_blank,
  drop constraint if exists coach_match_events_player_in_guest_name_not_blank,
  drop constraint if exists coach_match_events_player_out_guest_name_not_blank;

alter table public.coach_match_events
  add constraint coach_match_events_scorer_guest_id_not_blank
    check (scorer_guest_id is null or btrim(scorer_guest_id) <> ''),
  add constraint coach_match_events_assist_guest_id_not_blank
    check (assist_guest_id is null or btrim(assist_guest_id) <> ''),
  add constraint coach_match_events_player_in_guest_id_not_blank
    check (player_in_guest_id is null or btrim(player_in_guest_id) <> ''),
  add constraint coach_match_events_player_out_guest_id_not_blank
    check (player_out_guest_id is null or btrim(player_out_guest_id) <> ''),
  add constraint coach_match_events_player_in_guest_name_not_blank
    check (player_in_guest_name is null or btrim(player_in_guest_name) <> ''),
  add constraint coach_match_events_player_out_guest_name_not_blank
    check (player_out_guest_name is null or btrim(player_out_guest_name) <> '');

comment on column public.coach_match_events.scorer_guest_id is
  'Identifiant temporaire unique du buteur invité, limité au match.';
comment on column public.coach_match_events.assist_guest_id is
  'Identifiant temporaire unique du passeur invité, limité au match.';
comment on column public.coach_match_events.player_in_guest_id is
  'Identifiant temporaire unique de l’invité entrant.';
comment on column public.coach_match_events.player_out_guest_id is
  'Identifiant temporaire unique de l’invité sortant.';
