begin;

create or replace function private.finish_due_internal_matches(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_finished integer := 0;
begin
  update public.matches match
  set status = 'termine',
      updated_at = p_now
  where match.match_type = 'entre_nous'
    and match.status = 'a_venir'
    and match.kickoff_at is not null
    and match.kickoff_at <= p_now;

  get diagnostics v_finished = row_count;
  return v_finished;
end;
$function$;

comment on function private.finish_due_internal_matches(timestamptz) is
  'Marque automatiquement termine tout Match entre nous des que son heure de coup d envoi est atteinte.';

revoke all on function private.finish_due_internal_matches(timestamptz)
  from public, anon, authenticated;

select cron.schedule(
  'finish-due-internal-matches',
  '* * * * *',
  'select private.finish_due_internal_matches(now());'
);

select private.finish_due_internal_matches(now());

commit;
