alter table public.coach_match_events
  add column if not exists scorer_guest_name text,
  add column if not exists assist_guest_name text;

alter table public.coach_match_events
  drop constraint if exists coach_match_events_scorer_guest_name_not_blank,
  drop constraint if exists coach_match_events_assist_guest_name_not_blank;

alter table public.coach_match_events
  add constraint coach_match_events_scorer_guest_name_not_blank
    check (scorer_guest_name is null or btrim(scorer_guest_name) <> ''),
  add constraint coach_match_events_assist_guest_name_not_blank
    check (assist_guest_name is null or btrim(assist_guest_name) <> '');

comment on column public.coach_match_events.scorer_guest_name is
  'Nom affiché du buteur invité. Aucun profil ni statistique permanente n’est créé.';
comment on column public.coach_match_events.assist_guest_name is
  'Nom affiché du passeur invité. Aucun profil ni statistique permanente n’est créé.';
