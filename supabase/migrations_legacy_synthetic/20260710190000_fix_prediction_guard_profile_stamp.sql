-- Le tampon profile_id := auth.uid() ne doit s'appliquer qu'aux écritures
-- directes des utilisateurs, pas aux lignes seedées par trigger (sinon les
-- pronostics seedés pour d'autres profils sont écrasés vers le créateur du
-- match puis perdus par on conflict do nothing).
create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  kickoff timestamptz;
  match_status text;
begin
  select ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris'), m.status
  into kickoff, match_status
  from public.matches m
  where m.id = new.match_id;

  if kickoff is null or match_status <> 'a_venir' or now() >= kickoff - interval '5 minutes' then
    raise exception 'Pronostic fermé';
  end if;

  if auth.uid() is not null and pg_trigger_depth() <= 1 then
    new.profile_id := auth.uid();
  end if;

  return new;
end;
$$;
