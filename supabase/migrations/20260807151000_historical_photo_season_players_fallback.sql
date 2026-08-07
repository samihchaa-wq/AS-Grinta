-- get_historical_match_detail() ne résolvait la photo d'un joueur archivé
-- que via profiles.photo_url (photo de compte), sans jamais retomber sur
-- season_players.photo_url (photo d'effectif de saison) comme le fait le
-- système Live (private.composition_snapshot : coalesce(profile.photo_url,
-- player.photo_url, guest.photo_url)). Un joueur dont seule la fiche
-- d'effectif porte une photo restait donc sans avatar sur une fiche de
-- match archivé, contrairement à une fiche de match courant.

create or replace function private.get_historical_match_detail(
  p_match_id uuid
)
returns table (
  formation text,
  field_players jsonb,
  bench_players jsonb,
  present_names jsonb,
  scorers jsonb,
  motm_names jsonb,
  photo_urls jsonb
)
language plpgsql
stable
security definer
set search_path = ''
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
    ) as photo_urls
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$function$;

comment on function private.get_historical_match_detail(uuid) is
  'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map falling back from the account photo to the season-roster photo, same as the live composition snapshot.';
