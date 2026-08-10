do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'finalize_match_sport_postgame';

  if v_def is null then
    raise exception 'private.finalize_match_sport_postgame introuvable';
  end if;

  if position('live_session.state' in v_def) > 0 then
    return;
  end if;

  v_new := replace(
    v_def,
    'if now() < v_kickoff_at then',
    'if now() < v_kickoff_at and not exists (
    select 1
    from public.match_live_sessions live_session
    where live_session.match_id = p_match_id
      and live_session.state = ''finished''
  ) then'
  );

  if v_new = v_def then
    raise exception
      'Garde-fou kickoff introuvable dans finalize_match_sport_postgame';
  end if;

  execute v_new;
end
$do$;;
