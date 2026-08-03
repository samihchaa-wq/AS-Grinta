begin;

-- The coach may finalize only through the explicit Live recap export path.
-- A transaction-local flag keeps the generic admin finalization RPC admin-only.
do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.publish_match_live_recap(uuid,integer,integer,jsonb,text)'::regprocedure
  ) into v_def;

  if position('as_grinta.allow_coach_live_finalize' in v_def) = 0 then
    v_new := replace(
      v_def,
      $old$
  v_finalize_result := private.finalize_match_sport_postgame(
$old$,
      $new$
  perform set_config('as_grinta.allow_coach_live_finalize', 'on', true);

  v_finalize_result := private.finalize_match_sport_postgame(
$new$
    );
    if v_new = v_def then
      raise exception 'Unable to patch publish_match_live_recap coach context';
    end if;
    execute v_new;
  end if;
end
$do$;

do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(
    'private.finalize_match_sport_postgame(uuid,integer,integer,jsonb,text)'::regprocedure
  ) into v_def;

  if position('as_grinta.allow_coach_live_finalize' in v_def) = 0 then
    v_new := replace(
      v_def,
      $old$
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
$old$,
      $new$
  if not private.is_admin()
     and not (
       current_setting('as_grinta.allow_coach_live_finalize', true) = 'on'
       and private.is_match_coach_or_admin(p_match_id)
     ) then
    raise exception 'Active administrator role or validated Live coach context required'
      using errcode = '42501';
  end if;
$new$
    );
    if v_new = v_def then
      raise exception 'Unable to patch finalize_match_sport_postgame authorization';
    end if;
    execute v_new;
  end if;
end
$do$;

commit;
