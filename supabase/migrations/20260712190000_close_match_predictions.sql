-- Permet à l'admin de fermer manuellement les pronostics d'un match (avant
-- l'heure limite automatique de H-5).
alter table public.matches
  add column if not exists predictions_closed_at timestamptz;

-- Le garde-fou refuse aussi les pronos si la fermeture manuelle est passée.
create or replace function public.guard_match_prediction_window()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  kickoff timestamptz;
  match_status text;
  closed_at timestamptz;
begin
  select ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris'),
         m.status, m.predictions_closed_at
  into kickoff, match_status, closed_at
  from public.matches m
  where m.id = new.match_id;

  if kickoff is null
     or match_status <> 'a_venir'
     or now() >= kickoff - interval '5 minutes'
     or (closed_at is not null and now() >= closed_at) then
    raise exception 'Pronostic fermé';
  end if;

  if auth.uid() is not null and pg_trigger_depth() <= 1 then
    new.profile_id := auth.uid();
  end if;

  return new;
end;
$function$;

-- Ferme les pronostics d'un match (réservé au staff).
create or replace function public.close_match_predictions(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Staff role required';
  end if;
  update public.matches
    set predictions_closed_at = now(), updated_at = now()
    where id = p_match_id and status = 'a_venir' and predictions_closed_at is null;
  return found;
end;
$$;

revoke execute on function public.close_match_predictions(uuid) from public, anon;
grant execute on function public.close_match_predictions(uuid) to authenticated;
