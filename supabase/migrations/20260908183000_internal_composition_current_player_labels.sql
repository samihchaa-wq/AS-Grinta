-- « Compo > Sur papier » doit pouvoir relier le libellé court affiché dans
-- l'effectif (surnom ou prénom) au profil de poste archivé, sans deuxième
-- requête réseau et sans rapprochement approximatif par nom.
--
-- On enrichit donc la RPC de résolution existante avec un bloc réservé
-- `__display_names_by_player_id`. Les anciennes versions de l'application
-- continuent à lire les couples nom -> player_id de premier niveau et ignorent
-- ce bloc supplémentaire : le changement est rétrocompatible.

create or replace function public.resolve_player_identities(p_names text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_display_names jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if p_names is null or array_length(p_names, 1) is null then
    return jsonb_build_object(
      '__display_names_by_player_id',
      '{}'::jsonb
    );
  end if;

  with demande as (
    select distinct private.normalize_player_name(nom) as nom_normalise
    from unnest(p_names) as nom
    where nullif(btrim(nom), '') is not null
  ),
  connu as (
    select alias.player_id, alias.alias as nom
    from public.player_aliases alias
    union
    select joueur.id, joueur.display_name
    from public.players joueur
    where nullif(btrim(joueur.display_name), '') is not null
  ),
  candidat as (
    select
      demande.nom_normalise,
      connu.player_id,
      (
        select count(*)
        from public.historical_match_players archive
        where archive.player_id = connu.player_id
      ) as archives
    from demande
    join connu
      on private.normalize_player_name(connu.nom) = demande.nom_normalise
    group by demande.nom_normalise, connu.player_id
  ),
  meilleur as (
    select nom_normalise, max(archives) as archives_max
    from candidat
    group by nom_normalise
  ),
  retenu as (
    select
      candidat.nom_normalise,
      min(candidat.player_id::text) as player_id,
      count(*) as ex_aequo
    from candidat
    join meilleur
      on meilleur.nom_normalise = candidat.nom_normalise
     and meilleur.archives_max = candidat.archives
    group by candidat.nom_normalise
  ),
  resolu as (
    select
      retenu.nom_normalise,
      retenu.player_id,
      coalesce(
        (
          select min(
            coalesce(
              nullif(btrim(profile.surnom), ''),
              nullif(btrim(profile.first_name), '')
            )
          )
          from public.profiles profile
          where profile.player_id = retenu.player_id::uuid
            and profile.status = 'active'
        ),
        (
          select min(nullif(btrim(season_player.first_name), ''))
          from public.season_players season_player
          where season_player.player_id = retenu.player_id::uuid
            and season_player.is_active
        )
      ) as display_name
    from retenu
    where retenu.ex_aequo = 1
  )
  select
    coalesce(
      jsonb_object_agg(resolu.nom_normalise, resolu.player_id),
      '{}'::jsonb
    ),
    coalesce(
      jsonb_object_agg(resolu.player_id, resolu.display_name)
        filter (where resolu.display_name is not null),
      '{}'::jsonb
    )
  into v_result, v_display_names
  from resolu;

  return v_result || jsonb_build_object(
    '__display_names_by_player_id',
    v_display_names
  );
end;
$function$;

revoke all on function public.resolve_player_identities(text[])
  from public, anon;
grant execute on function public.resolve_player_identities(text[])
  to authenticated, service_role;

comment on function public.resolve_player_identities(text[]) is
  'Maps supplied club-archive player names to current canonical player IDs. '
  'Also returns current display labels only for those resolved identities, '
  'under __display_names_by_player_id, so nickname-based composition UI can '
  'stay identity-safe without an additional query.';
