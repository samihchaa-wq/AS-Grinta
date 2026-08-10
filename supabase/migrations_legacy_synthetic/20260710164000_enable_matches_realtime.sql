do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;
end;
$$;

-- Corrige uniquement un match futur démarré par erreur sans temps écoulé.
update public.coach_match_sessions s
set is_running = false,
    elapsed_seconds = 0,
    updated_at = now()
from public.matches m
where s.match_id = m.id
  and m.match_date > current_date
  and m.status = 'en_cours'
  and s.elapsed_seconds = 0;

update public.matches m
set status = 'a_venir',
    updated_at = now()
where m.match_date > current_date
  and m.status = 'en_cours'
  and exists (
    select 1
    from public.coach_match_sessions s
    where s.match_id = m.id
      and s.elapsed_seconds = 0
      and s.is_running = false
  );
