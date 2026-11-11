-- Réglages du club : deux valeurs par défaut réellement lues par le serveur,
-- jusqu'ici modifiables seulement en base.
--
--   * taille habituelle du groupe (config du flag `sports_management`,
--     lue par private.resolve_match_squad_size_limit et à la création du
--     suivi sportif d'un match) ;
--   * adresse du terrain à domicile (public.club_settings.home_address).
--
-- Ces valeurs ne s'appliquent qu'aux prochains matchs créés : les matchs
-- existants gardent leur taille de groupe et leur adresse.

create or replace function public.admin_get_club_defaults()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_home_address text;
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select nullif(btrim(settings.home_address), '')
  into v_home_address
  from public.club_settings settings
  where settings.id;

  return jsonb_build_object(
    'usual_squad_size', private.resolve_match_squad_size_limit(null),
    'home_address', v_home_address
  );
end;
$$;

revoke all on function public.admin_get_club_defaults()
  from public, anon;
grant execute on function public.admin_get_club_defaults()
  to authenticated, service_role;

create or replace function public.admin_set_club_defaults(
  p_usual_squad_size integer,
  p_home_address text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_home_address text := nullif(btrim(p_home_address), '');
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  if p_usual_squad_size is null
     or p_usual_squad_size < 1
     or p_usual_squad_size > 30 then
    raise exception 'Squad size limit must be between 1 and 30'
      using errcode = '22023';
  end if;

  if v_home_address is not null and char_length(v_home_address) > 300 then
    raise exception 'Address cannot exceed 300 characters'
      using errcode = '22023';
  end if;

  update private.app_feature_flags flag
  set config = jsonb_set(
        flag.config,
        '{usual_squad_size}',
        to_jsonb(p_usual_squad_size)
      ),
      updated_at = now(),
      updated_by = (select auth.uid())
  where flag.key = 'sports_management'
    and flag.config -> 'usual_squad_size'
      is distinct from to_jsonb(p_usual_squad_size);

  insert into public.club_settings as settings (id, home_address)
  values (true, v_home_address)
  on conflict (id) do update
  set home_address = excluded.home_address
  where settings.home_address is distinct from excluded.home_address;

  return jsonb_build_object(
    'usual_squad_size', private.resolve_match_squad_size_limit(null),
    'home_address', v_home_address
  );
end;
$$;

revoke all on function public.admin_set_club_defaults(integer, text)
  from public, anon;
grant execute on function public.admin_set_club_defaults(integer, text)
  to authenticated, service_role;
