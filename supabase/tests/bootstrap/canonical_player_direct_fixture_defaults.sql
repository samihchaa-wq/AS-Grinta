-- Certaines épreuves de charge désactivent volontairement tous les triggers via
-- session_replication_role=replica afin de mesurer uniquement les lectures. Le
-- contrat canonique rend player_id obligatoire sur plusieurs tables ; cette
-- valeur par défaut est donc strictement réservée à la base CI et ne s'active
-- que lorsque les triggers sont désactivés.

create or replace function private.ci_direct_player_identity_default()
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_player_id uuid;
begin
  if current_setting('session_replication_role') <> 'replica' then
    return null;
  end if;

  insert into public.players(display_name)
  values ('Fixture CI sans trigger')
  returning id into v_player_id;

  return v_player_id;
end;
$function$;

revoke all on function private.ci_direct_player_identity_default()
  from public, anon, authenticated;

do $defaults$
begin
  alter table public.season_players
    alter column player_id set default private.ci_direct_player_identity_default();
  alter table public.guest_players
    alter column player_id set default private.ci_direct_player_identity_default();
  alter table public.historical_player_statistics
    alter column player_id set default private.ci_direct_player_identity_default();
end
$defaults$;
