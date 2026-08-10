begin;

-- Les compositions terminées restent immuables pour les modifications directes.
-- Une suppression administrative d'un joueur doit toutefois pouvoir nettoyer,
-- via les clés étrangères en cascade, les entrées techniques qui le référencent.
create or replace function private.guard_finished_match_composition_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_match_id uuid;
  v_status text;
  v_is_cascade_delete boolean := tg_op = 'DELETE' and pg_trigger_depth() > 1;
begin
  v_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;

  select match.status::text into v_status
  from public.matches match
  where match.id = v_match_id;

  if v_status in ('termine', 'archive')
     and not v_is_cascade_delete
     and coalesce(
       current_setting('as_grinta.allow_postmatch_composition_write', true),
       'off'
     ) <> 'on' then
    raise exception 'Finished match compositions are immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

commit;
