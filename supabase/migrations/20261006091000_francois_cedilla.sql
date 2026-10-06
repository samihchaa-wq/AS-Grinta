begin;

-- « Francois » devient « François » partout où le nom est affiché.
--
-- Même démarche que 20260904121754 (Julien Vignard) : le nom officiel est
-- corrigé sur le profil, ses métadonnées de compte, chaque inscription à
-- l'effectif, l'identité canonique et les statistiques d'archives. Seul le mot
-- entier est remplacé, en gardant sa casse (Francois → François,
-- FRANCOIS → FRANÇOIS, francois → françois) : un « Franco » ou une autre
-- partie du nom ne bouge pas.
--
-- Ne changent pas :
-- * l'identifiant de connexion : profiles.username et l'adresse technique
--   auth.users.email restent tels quels, la personne se connecte comme avant ;
-- * les libellés des feuilles de match importées (historical_match_players,
--   historical_match_details, historical_player_name_links) : ce sont des clés
--   d'archive qui relient chaque libellé à son identité. Un match archivé
--   affiche déjà le prénom du profil rattaché, donc « François » ;
-- * les alias existants : les déclencheurs capture_*_player_alias ajoutent
--   l'orthographe corrigée, l'ancienne reste reconnue ;
-- * les journaux et notifications déjà envoyées, qui sont des archives.

create function pg_temp.with_cedilla(p_value text)
returns text
language sql
immutable
as $function$
  select regexp_replace(
    regexp_replace(
      regexp_replace(p_value, '\mFrancois\M', 'François', 'g'),
      '\mFRANCOIS\M', 'FRANÇOIS', 'g'
    ),
    '\mfrancois\M', 'françois', 'g'
  );
$function$;

create function pg_temp.needs_cedilla(p_value text)
returns boolean
language sql
immutable
as $function$
  select coalesce(p_value ~ '\m(Francois|FRANCOIS|francois)\M', false);
$function$;

-- Profils : prénom, nom et surnom affichés. Pas le username.
update public.profiles
set first_name = pg_temp.with_cedilla(first_name),
    last_name = pg_temp.with_cedilla(last_name),
    surnom = pg_temp.with_cedilla(surnom),
    updated_at = now()
where pg_temp.needs_cedilla(first_name)
   or pg_temp.needs_cedilla(last_name)
   or pg_temp.needs_cedilla(surnom);

-- Métadonnées du compte, relues par certains écrans d'inscription. Seules les
-- clés de nom sont réécrites ; l'adresse de connexion n'est pas touchée.
update auth.users
set raw_user_meta_data = raw_user_meta_data
      || jsonb_strip_nulls(jsonb_build_object(
        'first_name', pg_temp.with_cedilla(raw_user_meta_data ->> 'first_name'),
        'last_name', pg_temp.with_cedilla(raw_user_meta_data ->> 'last_name'),
        'surnom', pg_temp.with_cedilla(raw_user_meta_data ->> 'surnom')
      )),
    updated_at = now()
where pg_temp.needs_cedilla(raw_user_meta_data ->> 'first_name')
   or pg_temp.needs_cedilla(raw_user_meta_data ->> 'last_name')
   or pg_temp.needs_cedilla(raw_user_meta_data ->> 'surnom');

-- Inscriptions à l'effectif, toutes saisons.
update public.season_players
set first_name = pg_temp.with_cedilla(first_name),
    last_name = pg_temp.with_cedilla(last_name)
where pg_temp.needs_cedilla(first_name)
   or pg_temp.needs_cedilla(last_name);

-- Identité canonique.
update public.players
set display_name = pg_temp.with_cedilla(display_name),
    updated_at = now()
where pg_temp.needs_cedilla(display_name);

-- Invités de match.
update public.guest_players
set first_name = pg_temp.with_cedilla(first_name),
    last_name = pg_temp.with_cedilla(last_name)
where pg_temp.needs_cedilla(first_name)
   or pg_temp.needs_cedilla(last_name);

-- Statistiques d'archives : le nom y est rapproché de celui de l'effectif.
update public.historical_player_statistics
set player_name = pg_temp.with_cedilla(player_name),
    updated_at = now()
where pg_temp.needs_cedilla(player_name);

-- Badges dont le nom ou la description cite le prénom.
update public.badges
set name = pg_temp.with_cedilla(name),
    description = pg_temp.with_cedilla(description)
where pg_temp.needs_cedilla(name)
   or pg_temp.needs_cedilla(description);

do $verify$
begin
  if exists (
    select 1 from public.profiles
    where pg_temp.needs_cedilla(first_name)
       or pg_temp.needs_cedilla(last_name)
       or pg_temp.needs_cedilla(surnom)
  ) or exists (
    select 1 from public.season_players
    where pg_temp.needs_cedilla(first_name) or pg_temp.needs_cedilla(last_name)
  ) or exists (
    select 1 from public.players where pg_temp.needs_cedilla(display_name)
  ) or exists (
    select 1 from public.historical_player_statistics
    where pg_temp.needs_cedilla(player_name)
  ) then
    raise exception 'Francois spelling correction failed';
  end if;
end
$verify$;

commit;
