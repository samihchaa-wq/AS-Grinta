-- Corrige les identites officielles sans effacer leurs alias historiques.
--
-- Regle d'affichage :
--   * prenom/nom officiels pour les statistiques et l'identite canonique ;
--   * surnom en priorite dans le reste de l'application ;
--   * libelles d'archives conserves comme alias de l'epoque.

update public.profiles
set first_name = 'Romain',
    last_name = 'Spigolon',
    updated_at = now()
where id = 'e0388de1-d60f-4643-950e-2e43e7005252'
  and (
    first_name is distinct from 'Romain'
    or last_name is distinct from 'Spigolon'
  );

update public.profiles
set first_name = 'Julien',
    last_name = 'Vignard',
    surnom = 'Julio',
    updated_at = now()
where id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
  and (
    first_name is distinct from 'Julien'
    or last_name is distinct from 'Vignard'
    or surnom is distinct from 'Julio'
  );

update auth.users
set raw_user_meta_data =
      coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object(
        'first_name', 'Romain',
        'last_name', 'Spigolon'
      ),
    updated_at = now()
where id = 'e0388de1-d60f-4643-950e-2e43e7005252'
  and (
    raw_user_meta_data ->> 'first_name' is distinct from 'Romain'
    or raw_user_meta_data ->> 'last_name' is distinct from 'Spigolon'
  );

update auth.users
set raw_user_meta_data =
      coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object(
        'first_name', 'Julien',
        'last_name', 'Vignard',
        'surnom', 'Julio'
      ),
    updated_at = now()
where id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
  and (
    raw_user_meta_data ->> 'first_name' is distinct from 'Julien'
    or raw_user_meta_data ->> 'last_name' is distinct from 'Vignard'
    or raw_user_meta_data ->> 'surnom' is distinct from 'Julio'
  );

update public.season_players sp
set first_name = 'Romain',
    last_name = 'Spigolon'
where (
    sp.profile_id = 'e0388de1-d60f-4643-950e-2e43e7005252'
    or sp.player_id = (
      select p.player_id
      from public.profiles p
      where p.id = 'e0388de1-d60f-4643-950e-2e43e7005252'
    )
  )
  and (
    sp.first_name is distinct from 'Romain'
    or sp.last_name is distinct from 'Spigolon'
  );

update public.season_players sp
set first_name = 'Julien',
    last_name = 'Vignard'
where (
    sp.profile_id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
    or sp.player_id = (
      select p.player_id
      from public.profiles p
      where p.id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
    )
  )
  and (
    sp.first_name is distinct from 'Julien'
    or sp.last_name is distinct from 'Vignard'
  );

update public.historical_player_statistics h
set player_name = 'Romain Spigolon'
where (
    h.profile_id = 'e0388de1-d60f-4643-950e-2e43e7005252'
    or h.player_id = (
      select p.player_id
      from public.profiles p
      where p.id = 'e0388de1-d60f-4643-950e-2e43e7005252'
    )
  )
  and h.player_name is distinct from 'Romain Spigolon';

update public.historical_player_statistics h
set player_name = 'Julien Vignard'
where (
    h.profile_id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
    or h.player_id = (
      select p.player_id
      from public.profiles p
      where p.id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
    )
  )
  and h.player_name is distinct from 'Julien Vignard';

update public.players
set display_name = 'Romain Spigolon',
    updated_at = now()
where lower(btrim(display_name)) = 'romain spigolon'
  and display_name is distinct from 'Romain Spigolon';

update public.players
set display_name = 'Julien Vignard',
    updated_at = now()
where lower(btrim(display_name)) in ('julio vignard', 'julien vignard')
  and display_name is distinct from 'Julien Vignard';

update public.player_aliases
set alias = 'Romain Spigolon'
where lower(btrim(alias)) = 'romain spigolon'
  and alias is distinct from 'Romain Spigolon';

insert into public.player_aliases(player_id, alias)
select p.player_id, alias_name
from public.profiles p
cross join (
  values ('Julien Vignard'::text), ('Julio Vignard'::text)
) aliases(alias_name)
where p.id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
  and p.player_id is not null
on conflict do nothing;

do $verify$
begin
  if exists (
    select 1
    from public.profiles
    where id = 'e0388de1-d60f-4643-950e-2e43e7005252'
  ) and not exists (
    select 1
    from public.profiles
    where id = 'e0388de1-d60f-4643-950e-2e43e7005252'
      and first_name = 'Romain'
      and last_name = 'Spigolon'
  ) then
    raise exception 'Romain profile identity correction failed';
  end if;

  if exists (
    select 1
    from public.profiles
    where id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
  ) and not exists (
    select 1
    from public.profiles
    where id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
      and first_name = 'Julien'
      and last_name = 'Vignard'
      and surnom = 'Julio'
  ) then
    raise exception 'Julien Vignard profile identity correction failed';
  end if;

  if exists (
    select 1
    from public.season_players
    where profile_id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
      and (first_name, last_name) is distinct from ('Julien', 'Vignard')
  ) then
    raise exception 'Julien Vignard roster identity correction failed';
  end if;

  if exists (
    select 1
    from public.historical_player_statistics
    where profile_id = '8b57326a-96ac-4ff0-9293-3e23f4c1cae9'
      and player_name is distinct from 'Julien Vignard'
  ) then
    raise exception 'Julien Vignard statistics identity correction failed';
  end if;
end
$verify$;
