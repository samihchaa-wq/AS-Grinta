-- Surnoms sur les matchs archivés
--
-- Dans le Calendrier, un joueur est toujours appelé par son surnom (à défaut
-- son prénom). Les matchs archivés faisaient exception : leur nom venait de la
-- vieille feuille de match importée, où l'un a été noté « Olivier Millet » et
-- l'autre « Julio Vignard ». L'écran affichait donc « Olivier » pour un joueur
-- surnommé Poulain.
--
-- La lecture d'un match archivé renvoie désormais, à côté de la carte des
-- photos, une carte « nom de la feuille de match -> identité du club » :
-- surnom sinon prénom, plus l'initiale du nom de famille pour la pastille des
-- joueurs sans photo. L'application s'en sert quand le joueur de l'archive est
-- rattaché à un joueur connu, et garde l'ancien repli sinon.
--
-- La signature de la fonction change (une colonne de plus) : elle doit donc
-- être supprimée puis recréée, d'abord côté public qui en dépend. Le corps est
-- repris à l'identique de la production, à ce seul ajout près, et les droits
-- sont rétablis tels quels.

drop function if exists public.get_historical_match_detail(uuid);
drop function if exists private.get_historical_match_detail(uuid);

create function private.get_historical_match_detail(p_match_id uuid)
returns table(
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  scorers jsonb,
  motm_names jsonb,
  photo_urls jsonb,
  display_names jsonb
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  return query
  select
    d.formation, d.field_players, d.bench_players, d.present_names,
    d.scorers, d.motm_names,
    coalesce(
      (
        select jsonb_object_agg(
          hmp.source_name,
          coalesce(pr.photo_url, sp.photo_url)
        )
        from public.historical_match_players hmp
        left join public.profiles pr on pr.player_id = hmp.player_id
        left join lateral (
          select season_players.photo_url
          from public.season_players
          where season_players.player_id = hmp.player_id
            and season_players.photo_url is not null
          order by season_players.joined_at desc
          limit 1
        ) sp on true
        where hmp.match_id = d.match_id
          and coalesce(pr.photo_url, sp.photo_url) is not null
      ),
      '{}'::jsonb
    ) as photo_urls,
    coalesce(
      (
        select jsonb_object_agg(
          hmp.source_name,
          jsonb_build_object(
            'name', identity.display_name,
            'last_initial', identity.last_initial
          )
        )
        from public.historical_match_players hmp
        left join public.profiles pr on pr.player_id = hmp.player_id
        left join lateral (
          select season_players.first_name, season_players.last_name
          from public.season_players
          where season_players.player_id = hmp.player_id
          order by season_players.joined_at desc
          limit 1
        ) sp on true
        cross join lateral (
          select
            coalesce(
              nullif(btrim(pr.surnom), ''),
              nullif(btrim(pr.first_name), ''),
              nullif(btrim(sp.first_name), '')
            ) as display_name,
            nullif(upper(left(coalesce(
              nullif(btrim(pr.last_name), ''),
              nullif(btrim(sp.last_name), ''),
              ''
            ), 1)), '') as last_initial
        ) identity
        where hmp.match_id = d.match_id
          and identity.display_name is not null
      ),
      '{}'::jsonb
    ) as display_names
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$function$;

alter function private.get_historical_match_detail(uuid) owner to postgres;

comment on function private.get_historical_match_detail(uuid) is
  'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map and a source-name -> club identity map (nickname or first name, plus last-name initial), falling back from the account to the season roster, same as the live composition snapshot.';

revoke all on function private.get_historical_match_detail(uuid) from public;
grant all on function private.get_historical_match_detail(uuid) to authenticated;
grant all on function private.get_historical_match_detail(uuid) to service_role;

create function public.get_historical_match_detail(p_match_id uuid)
returns table(
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  scorers jsonb,
  motm_names jsonb,
  photo_urls jsonb,
  display_names jsonb
)
language sql
stable
set search_path to ''
as $function$
  select * from private.get_historical_match_detail(p_match_id);
$function$;

alter function public.get_historical_match_detail(uuid) owner to postgres;

comment on function public.get_historical_match_detail(uuid) is
  'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map and a source-name -> club identity map for identified players; authorization is enforced by a private helper.';

revoke all on function public.get_historical_match_detail(uuid) from public;
grant all on function public.get_historical_match_detail(uuid) to authenticated;
grant all on function public.get_historical_match_detail(uuid) to service_role;
