-- Le terrain d'un match archivé affichait systématiquement un avatar sans
-- photo (photoUrl codé en dur à null côté client) : rien ne reliait jamais
-- une composition importée à la photo de profil du joueur, même quand son
-- identité canonique était connue. On expose désormais, aux côtés du JSON
-- déjà stocké, la photo de chaque joueur du match dont l'identité canonique
-- a un compte actif avec une photo.

-- CREATE OR REPLACE ne permet pas d'ajouter une colonne à un type de retour
-- TABLE existant : les deux fonctions doivent être recréées.
drop function if exists public.get_historical_match_detail(uuid);
drop function if exists private.get_historical_match_detail(uuid);

create function private.get_historical_match_detail(
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
        select jsonb_object_agg(hmp.source_name, pr.photo_url)
        from public.historical_match_players hmp
        join public.profiles pr on pr.player_id = hmp.player_id
        where hmp.match_id = d.match_id
          and pr.photo_url is not null
      ),
      '{}'::jsonb
    ) as photo_urls
  from public.historical_match_details d
  where d.match_id = p_match_id;
end;
$function$;

revoke all on function private.get_historical_match_detail(uuid) from public, anon;
grant execute on function private.get_historical_match_detail(uuid) to authenticated, service_role;

create function public.get_historical_match_detail(
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
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.get_historical_match_detail(p_match_id);
$function$;

revoke all on function public.get_historical_match_detail(uuid) from public, anon;
grant execute on function public.get_historical_match_detail(uuid) to authenticated, service_role;

comment on function public.get_historical_match_detail(uuid) is
  'Read-only historical match detail (composition/buteurs/HDM) for one match_id, with a source-name -> photo_url map for identified players; authorization is enforced by a private helper.';
