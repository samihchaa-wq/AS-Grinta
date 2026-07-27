-- Le schéma isolé n’installe pas l’intégralité de l’historique sportif. Ces
-- stubs reproduisent uniquement les signatures et la chaîne d’appel présentes en
-- production afin de vérifier leurs ACL dans le verrou global.
do $block$
begin
  if to_regprocedure(
    'private.save_match_effectif(uuid,integer,jsonb,text)'
  ) is null then
    execute $sql$
      create function private.save_match_effectif(
        p_match_id uuid,
        p_squad_size_limit integer,
        p_decisions jsonb,
        p_reason text default null
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path to ''
      as $function$
      begin
        if not private.is_admin() then
          raise exception 'Active administrator role required'
            using errcode = '42501';
        end if;
        return jsonb_build_object('match_id', p_match_id);
      end;
      $function$
    $sql$;
  end if;

  if to_regprocedure(
    'public.admin_save_match_effectif(uuid,integer,jsonb,text)'
  ) is null then
    execute $sql$
      create function public.admin_save_match_effectif(
        p_match_id uuid,
        p_squad_size_limit integer,
        p_decisions jsonb,
        p_reason text default null
      )
      returns jsonb
      language sql
      set search_path to ''
      as $function$
        select private.save_match_effectif(
          p_match_id,
          p_squad_size_limit,
          p_decisions,
          p_reason
        );
      $function$
    $sql$;
  end if;
end;
$block$;
