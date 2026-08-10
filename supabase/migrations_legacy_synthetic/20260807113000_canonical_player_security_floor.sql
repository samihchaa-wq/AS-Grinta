-- Les tables d'identité canonique sont une couche métier interne. Aucun client
-- ne doit les lire ou les écrire directement : les futurs usages passent par
-- des vues/RPC explicites, avec le même plancher RLS que le reste du schéma.

do $security$
declare
  v_table text;
begin
  foreach v_table in array array[
    'players',
    'player_aliases',
    'historical_match_players',
    'historical_player_name_links'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from anon, authenticated', v_table);
    execute format('grant all on table public.%I to service_role', v_table);

    execute format('drop policy if exists deny_client_access on public.%I', v_table);
    execute format(
      'create policy deny_client_access on public.%I as restrictive for all to anon, authenticated using (false) with check (false)',
      v_table
    );

    execute format(
      'drop policy if exists active_authenticated_profile_only on public.%I',
      v_table
    );
    execute format(
      'create policy active_authenticated_profile_only on public.%I as restrictive for all to authenticated using ((select private.is_active_profile())) with check ((select private.is_active_profile()))',
      v_table
    );
  end loop;
end
$security$;
