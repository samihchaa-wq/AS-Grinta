create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select least(
    match.kickoff_at + interval '2 hours',
    greatest(
      match.kickoff_at,
      coalesce((
        select min(version.created_at)
        from public.match_sport_finalization_versions version
        where version.match_id = p_match_id
      ), 'infinity'::timestamptz)
    )
  )
  from public.matches match
  where match.id = p_match_id;
$function$;

update public.match_sport_motm_elections election
set opens_at = private.match_motm_opens_at(election.match_id),
    updated_at = now()
where election.state = 'draft';
