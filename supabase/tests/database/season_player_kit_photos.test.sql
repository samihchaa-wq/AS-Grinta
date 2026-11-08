begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regclass('public.season_player_kit_photos') is not null,
  'les photos Brésil et Pays-Bas ont leurs propres emplacements'
);

select ok(
  not has_table_privilege('anon', 'public.season_player_kit_photos', 'SELECT')
  and not has_table_privilege('anon', 'public.season_player_kit_photos', 'INSERT')
  and not has_table_privilege('anon', 'public.season_player_kit_photos', 'UPDATE'),
  'les photos alternatives ne sont pas accessibles aux anonymes'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'season_player_kit_photos'
      and policyname = 'active_authenticated_profile_only'
      and permissive = 'RESTRICTIVE'
      and cmd = 'ALL'
  ),
  'chaque acces est conditionne a un profil actif'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'season_player_kit_photos'
      and policyname = 'admin_insert_kit_photos'
      and with_check like '%is_admin%'
  ) and exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'season_player_kit_photos'
      and policyname = 'admin_update_kit_photos'
      and qual like '%is_admin%'
  ),
  'seuls les administrateurs peuvent modifier les portraits alternatifs'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.season_player_kit_photos'::regclass
      and tgname = 'cleanup_player_kit_photo_files'
      and not tgisinternal
  ),
  'les anciennes photos alternatives sont nettoyees au remplacement'
);

select * from finish();
rollback;
