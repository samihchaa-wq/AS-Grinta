-- Evite qu'une inscription crée une seconde identité joueur quand un seul
-- joueur canonique non rattaché à un compte porte déjà ce nom.
--
-- Important : les homonymes restent autorisés. On ne réutilise une identité
-- que si le nom normalisé correspond à exactement un player_id et que ce
-- player_id n'est encore lié à aucun profil.
--
-- Le verrou transactionnel sérialise les inscriptions concurrentes portant le
-- même nom : la première peut réclamer/créer l'identité, la suivante verra
-- ensuite qu'elle est déjà rattachée à un profil et créera sa propre identité.

begin;

create or replace function private.find_reusable_profile_player_identity(
  p_display_name text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_normalized text := private.normalize_player_name(p_display_name);
  v_candidate uuid;
  v_candidate_count integer;
begin
  if v_normalized is null or v_normalized = '' then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_normalized, 0)
  );

  select count(*)::integer
    into v_candidate_count
  from (
    select distinct pa.player_id
    from public.player_aliases pa
    where private.normalize_player_name(pa.alias) = v_normalized
  ) matches;

  if v_candidate_count <> 1 then
    return null;
  end if;

  select pa.player_id
    into v_candidate
  from public.player_aliases pa
  where private.normalize_player_name(pa.alias) = v_normalized
  group by pa.player_id
  limit 1;

  if exists (
    select 1
    from public.profiles p
    where p.player_id = v_candidate
  ) then
    return null;
  end if;

  return v_candidate;
end;
$function$;

revoke all on function private.find_reusable_profile_player_identity(text)
  from public, anon, authenticated;
grant execute on function private.find_reusable_profile_player_identity(text)
  to service_role;

create or replace function private.ensure_profile_player_identity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_alias text;
begin
  if coalesce(new.email, '') = 'historique@as-grinta.invalid' then
    return new;
  end if;

  v_alias := coalesce(
    nullif(btrim(concat_ws(' ', new.first_name, nullif(new.last_name, ''))), ''),
    nullif(btrim(new.username), ''),
    'Joueur'
  );

  if new.player_id is null then
    new.player_id := private.find_reusable_profile_player_identity(v_alias);

    if new.player_id is null then
      new.player_id := private.create_player_identity(v_alias);
    else
      insert into public.player_aliases(alias, player_id)
      values (v_alias, new.player_id)
      on conflict do nothing;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.ensure_profile_player_identity()
  from public, anon, authenticated;
grant execute on function private.ensure_profile_player_identity()
  to service_role;

commit;
