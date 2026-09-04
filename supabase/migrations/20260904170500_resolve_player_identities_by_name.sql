-- Les postes de référence de l'application sont un fichier généré depuis
-- l'archive du club, rangé par identité canonique (public.players.id). Cette
-- clé ne survit pas à une fusion d'identités : merge_player_identities déplace
-- l'historique sur l'identité gagnante puis supprime la perdante. Le fichier
-- pointe alors dans le vide et le joueur perd silencieusement son poste.
--
-- Ce qui survit à une fusion, en revanche, c'est le nom : la fusion recolle
-- tous les alias de l'identité perdante sur l'identité gagnante. On expose
-- donc la résolution nom -> identité d'aujourd'hui, pour que l'application
-- puisse réancrer son archive à chaque chargement au lieu de dépendre d'un
-- relevé figé.
--
-- Deux règles de prudence :
--   - à nom égal, on retient l'identité qui porte le plus de matchs archivés,
--     c'est-à-dire celle sur laquelle la fusion a effectivement recollé
--     l'histoire ;
--   - en cas d'égalité stricte entre plusieurs identités, on ne retourne rien.
--     Mieux vaut un joueur sans poste de référence qu'un joueur rangé sous le
--     passé de quelqu'un d'autre.
--
-- La normalisation est celle de private.normalize_player_name, la même que
-- celle utilisée pour créer les identités : minuscules et espaces resserrés.
-- Elle ne retire pas les accents, mais les deux orthographes d'un même nom
-- cohabitent déjà comme deux alias de la même identité.

create or replace function public.resolve_player_identities(p_names text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if p_names is null or array_length(p_names, 1) is null then
    return '{}'::jsonb;
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
  )
  select coalesce(jsonb_object_agg(nom_normalise, player_id), '{}'::jsonb)
  into v_result
  from retenu
  where ex_aequo = 1;

  return v_result;
end;
$function$;

revoke all on function public.resolve_player_identities(text[])
  from public, anon;
grant execute on function public.resolve_player_identities(text[])
  to authenticated, service_role;

comment on function public.resolve_player_identities(text[]) is
  'Maps club-archive player names to the canonical player identity that '
  'currently carries their history. Readable by any active authenticated '
  'profile; returns identifiers only, never names it was not given.';
