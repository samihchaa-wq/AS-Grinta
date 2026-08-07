-- Philippe Couzin apparaît dans les JSON d'archives comme présent/HDM mais
-- n'a jamais été un joueur de l'effectif. Le JSON importé reste la source
-- historique intacte ; seule sa projection vers le registre de joueurs est
-- volontairement exclue.

create or replace function private.is_known_non_player_archive_name(p_name text)
returns boolean
language sql
immutable
strict
set search_path to ''
as $function$
  select private.normalize_player_name(p_name)
    = private.normalize_player_name('Philippe Couzin');
$function$;

revoke all on function private.is_known_non_player_archive_name(text)
  from public, anon, authenticated;

-- Les deux premières migrations de la série ont pu créer une identité
-- transitoire à partir des archives existantes. On retire uniquement la
-- projection normalisée ; les JSON de historical_match_details ne sont pas
-- modifiés.
delete from public.historical_match_players hmp
where private.is_known_non_player_archive_name(hmp.source_name);

delete from public.historical_player_name_links link
where private.is_known_non_player_archive_name(link.source_name)
   or link.normalized_name = private.normalize_player_name('Philippe Couzin');

-- Supprime l'identité créée uniquement depuis ce libellé d'archive, sans
-- jamais toucher une éventuelle vraie identité joueur qui aurait un lien
-- explicite vers un compte, un effectif, un invité, des statistiques, un
-- match normalisé ou un autre alias.
delete from public.players p
where private.normalize_player_name(p.display_name)
    = private.normalize_player_name('Philippe Couzin')
  and not exists (
    select 1 from public.profiles pr where pr.player_id = p.id
  )
  and not exists (
    select 1 from public.season_players sp where sp.player_id = p.id
  )
  and not exists (
    select 1 from public.guest_players gp where gp.player_id = p.id
  )
  and not exists (
    select 1
    from public.historical_player_statistics hs
    where hs.player_id = p.id
  )
  and not exists (
    select 1
    from public.historical_match_players hmp
    where hmp.player_id = p.id
  )
  and not exists (
    select 1
    from public.historical_player_name_links link
    where link.player_id = p.id
  )
  and not exists (
    select 1
    from public.player_aliases a
    where a.player_id = p.id
      and private.normalize_player_name(a.alias)
        <> private.normalize_player_name('Philippe Couzin')
  );

-- Toute nouvelle réécriture d'une archive doit conserver le même contrat :
-- le staff connu ne reçoit jamais d'identité de joueur.
create or replace function private.resolve_historical_player_name(p_name text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text := nullif(btrim(p_name), '');
  v_normalized_name text;
  v_player_id uuid;
  v_identity_count integer;
begin
  if v_name is null then
    return null;
  end if;

  v_normalized_name := private.normalize_player_name(v_name);
  if v_normalized_name = private.normalize_player_name('Poste laissé vide')
     or private.is_known_non_player_archive_name(v_name) then
    return null;
  end if;

  select link.player_id
  into v_player_id
  from public.historical_player_name_links link
  where link.normalized_name = v_normalized_name;

  if found then
    return v_player_id;
  end if;

  select
    count(distinct alias.player_id)::integer,
    min(alias.player_id::text)::uuid
  into v_identity_count, v_player_id
  from public.player_aliases alias
  where private.normalize_player_name(alias.alias) = v_normalized_name;

  -- 0 correspondance ou plusieurs homonymes : on ne devine pas. Une
  -- identité d'archive distincte est créée et restera stable pour ce libellé.
  if v_identity_count <> 1 then
    v_player_id := private.create_player_identity(v_name);
  end if;

  insert into public.historical_player_name_links(
    normalized_name,
    source_name,
    player_id
  )
  values (v_normalized_name, v_name, v_player_id)
  on conflict (normalized_name) do update
  set updated_at = now()
  returning player_id into v_player_id;

  return v_player_id;
end;
$function$;

revoke all on function private.resolve_historical_player_name(text)
  from public, anon, authenticated;

-- Reprojette les archives existantes avec la règle corrigée. Cette opération
-- ne touche qu'à historical_match_players ; les JSON sources restent intacts.
do $refresh$
declare
  v_match_id uuid;
begin
  for v_match_id in
    select h.match_id from public.historical_match_details h
  loop
    perform private.refresh_historical_match_players(v_match_id);
  end loop;
end
$refresh$;
