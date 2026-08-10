-- Passe sécurité P0 : fermer les surfaces de lecture privilégiée et les RPC
-- redevenues publiques après des CREATE OR REPLACE ultérieurs.
--
-- Les vues restent lisibles par authenticated, mais appliquent désormais les
-- privilèges et politiques RLS de l'appelant.
alter view public.v_season_prediction_points
  set (security_invoker = true);

alter view public.v_season_prediction_bonus
  set (security_invoker = true);

alter view public.v_statistics_players
  set (security_invoker = true);

-- Ces deux fonctions ne nécessitent pas de contourner la RLS. Les exécuter avec
-- les droits de l'appelant supprime une élévation inutile tout en conservant
-- leur API pour les utilisateurs connectés.
alter function public.featured_badges() security invoker;
alter function public.profile_badge_stars(uuid) security invoker;

revoke execute on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges()
  to authenticated, service_role;

revoke execute on function public.profile_badge_stars(uuid) from public, anon;
grant execute on function public.profile_badge_stars(uuid)
  to authenticated, service_role;

-- Les RPC staff doivent rester SECURITY DEFINER : elles effectuent des actions
-- administratives et revérifient is_match_staff() dans leur corps. Elles ne
-- doivent toutefois jamais être accessibles sans authentification.
revoke execute on function public.staff_list_historical_players()
  from public, anon;
grant execute on function public.staff_list_historical_players()
  to authenticated, service_role;

revoke execute on function public.staff_set_historical_profile(uuid, bigint)
  from public, anon;
grant execute on function public.staff_set_historical_profile(uuid, bigint)
  to authenticated, service_role;

-- Une fonction de trigger n'est pas une RPC applicative. Le moteur PostgreSQL
-- peut continuer à l'exécuter via le trigger sans droit EXECUTE côté client.
revoke execute on function public.trg_badges_on_historical_link()
  from public, anon, authenticated;
revoke execute on function public.trg_badges_on_roster_change()
  from public, anon, authenticated;

-- Invariants : échouer immédiatement si une migration ultérieure ou un état de
-- base inattendu empêche le durcissement demandé.
do $security_assertions$
declare
  v_bad_view_count integer;
  v_bad_definer_count integer;
begin
  select count(*)
    into v_bad_view_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'v_season_prediction_points',
      'v_season_prediction_bonus',
      'v_statistics_players'
    )
    and not coalesce(c.reloptions, '{}'::text[])
      @> array['security_invoker=true'];

  if v_bad_view_count <> 0 then
    raise exception
      'security_invoker assertion failed for % view(s)',
      v_bad_view_count;
  end if;

  select count(*)
    into v_bad_definer_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('featured_badges', 'profile_badge_stars')
    and p.prosecdef;

  if v_bad_definer_count <> 0 then
    raise exception
      'security invoker assertion failed for % badge function(s)',
      v_bad_definer_count;
  end if;

  if has_function_privilege(
       'anon', 'public.featured_badges()', 'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.profile_badge_stars(uuid)', 'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.staff_list_historical_players()', 'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.staff_set_historical_profile(uuid,bigint)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.trg_badges_on_historical_link()', 'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.trg_badges_on_roster_change()', 'EXECUTE'
     ) then
    raise exception
      'anonymous EXECUTE privilege remains on a hardened function';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.featured_badges()', 'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.profile_badge_stars(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.staff_list_historical_players()',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.staff_set_historical_profile(uuid,bigint)',
       'EXECUTE'
     ) then
    raise exception
      'authenticated EXECUTE privilege missing on an application RPC';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.trg_badges_on_historical_link()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.trg_badges_on_roster_change()',
       'EXECUTE'
     ) then
    raise exception
      'trigger function remains directly executable by authenticated';
  end if;
end;
$security_assertions$;
