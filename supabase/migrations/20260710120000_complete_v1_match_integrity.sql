create or replace function public.assert_match_live_editable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status text;
begin
  select m.status::text
  into current_status
  from public.matches m
  where m.id = new.match_id;

  if current_status is null then
    raise exception 'Match introuvable';
  end if;

  if current_status not in ('a_venir', 'en_cours') then
    raise exception 'Le Tableau du coach est verrouillé pour un match terminé';
  end if;

  return new;
end;
$$;

revoke all on function public.assert_match_live_editable() from public, anon;
grant execute on function public.assert_match_live_editable() to authenticated;

drop trigger if exists coach_match_sessions_match_open_guard
  on public.coach_match_sessions;
create trigger coach_match_sessions_match_open_guard
before insert or update on public.coach_match_sessions
for each row execute function public.assert_match_live_editable();

drop trigger if exists coach_match_events_match_open_guard
  on public.coach_match_events;
create trigger coach_match_events_match_open_guard
before insert or update on public.coach_match_events
for each row execute function public.assert_match_live_editable();

create or replace function public.recalculate_match_score_from_goals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_match_id uuid;
  grinta_score integer;
  opponent_score integer;
begin
  target_match_id := coalesce(new.match_id, old.match_id);

  select
    count(*) filter (where g.team::text = 'as_grinta'),
    count(*) filter (where g.team::text <> 'as_grinta')
  into grinta_score, opponent_score
  from public.goals g
  where g.match_id = target_match_id;

  update public.matches
  set score_as_grinta = coalesce(grinta_score, 0),
      score_adverse = coalesce(opponent_score, 0),
      updated_at = now()
  where id = target_match_id;

  return coalesce(new, old);
end;
$$;

revoke all on function public.recalculate_match_score_from_goals()
  from public, anon;
grant execute on function public.recalculate_match_score_from_goals()
  to authenticated;

drop trigger if exists goals_recalculate_match_score on public.goals;
create trigger goals_recalculate_match_score
after insert or update or delete on public.goals
for each row execute function public.recalculate_match_score_from_goals();

do $$
declare
  match_row record;
begin
  for match_row in select id from public.matches loop
    update public.matches m
    set score_as_grinta = (
          select count(*) from public.goals g
          where g.match_id = match_row.id and g.team::text = 'as_grinta'
        ),
        score_adverse = (
          select count(*) from public.goals g
          where g.match_id = match_row.id and g.team::text <> 'as_grinta'
        ),
        updated_at = now()
    where m.id = match_row.id;
  end loop;
end;
$$;
