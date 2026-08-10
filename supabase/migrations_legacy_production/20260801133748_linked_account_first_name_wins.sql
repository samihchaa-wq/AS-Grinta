do $patch$
declare
  v_signature text;
  v_oid regprocedure;
  v_def text;
  v_new text;
  v_marker constant text := '.surnom), ''''), nullif(btrim(';
begin
  foreach v_signature in array array[
    'private.composition_snapshot(uuid)',
    'private.get_match_availability_board(uuid)',
    'private.get_match_convocations(uuid)',
    'private.get_match_motm_vote(uuid)',
    'private.get_published_match_composition(uuid)',
    'private.get_sport_waitlist(uuid)',
    'private.get_sport_waitlist_readonly(uuid)',
    'private.match_live_snapshot(uuid)',
    'private.match_sport_finalization_snapshot(uuid)',
    'public.admin_get_internal_composition(uuid)'
  ]
  loop
    v_oid := to_regprocedure(v_signature);
    if v_oid is null then
      continue;
    end if;

    v_def := pg_get_functiondef(v_oid);
    if position(v_marker in v_def) > 0 then
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      'nullif\(btrim\((\w+)\.surnom\), ''''\)',
      'nullif(btrim(\1.surnom), ''''), nullif(btrim(\1.first_name), '''')',
      'g'
    );

    v_new := replace(
      v_new,
      'lower(coalesce(profile.surnom, player.first_name',
      'lower(coalesce(profile.surnom, profile.first_name, player.first_name'
    );

    if v_new = v_def then
      raise exception '%: motif de nom introuvable, correction manuelle requise',
        v_signature;
    end if;

    execute v_new;
  end loop;
end
$patch$;;
