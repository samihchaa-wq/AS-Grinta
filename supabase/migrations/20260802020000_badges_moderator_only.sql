do $patch$
declare
  v_function text;
  v_def text;
  v_old constant text :=
    'if not public.is_match_staff() then'
    || E'\n    raise exception ''Active administrator role required'' using errcode = ''42501'';';
  v_new constant text :=
    'if not public.is_moderator() then'
    || E'\n    raise exception ''Moderator role required'' using errcode = ''42501'';';
begin
  foreach v_function in array array[
    'public.staff_create_badge(text, text, text, text, text, text)',
    'public.staff_award_badge(uuid, text)',
    'public.staff_revoke_badge(uuid, text)'
  ]
  loop
    v_def := pg_get_functiondef(v_function::regprocedure);
    if position('public.is_moderator()' in v_def) > 0 then
      continue;
    end if;
    if position(v_old in v_def) = 0 then
      raise exception '%: garde attendue introuvable, correction manuelle requise', v_function;
    end if;
    execute replace(v_def, v_old, v_new);
  end loop;
end
$patch$;;
