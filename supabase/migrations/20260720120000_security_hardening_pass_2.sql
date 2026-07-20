-- Passe sécurité 2 : réduire les RPC directement exposées, durcir les
-- search_path restants et documenter explicitement les tables internes.
--
-- Cette migration est préparée pour revue et tests locaux. Elle ne doit pas être
-- appliquée à la production sans autorisation distincte.

-- Ces fonctions restent nécessaires au flux transactionnel moderne, mais elles
-- ne sont plus des points d'entrée directs de l'application :
-- - finalize_match_postgame_with_lineup() les appelle avec les droits du
--   propriétaire de la fonction ;
-- - create_match_with_odds() et update_match_with_odds() ont remplacé
--   set_match_odds() côté Flutter.
revoke execute on function public.finalize_match_postgame(
  uuid, integer, jsonb, uuid, integer
) from public, anon, authenticated;
grant execute on function public.finalize_match_postgame(
  uuid, integer, jsonb, uuid, integer
) to service_role;

revoke execute on function public.staff_set_match_attendance(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.staff_set_match_attendance(uuid, uuid[])
  to service_role;

revoke execute on function public.staff_set_match_mvp(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.staff_set_match_mvp(uuid, uuid[])
  to service_role;

revoke execute on function public.set_match_odds(
  uuid, numeric, numeric, numeric
) from public, anon, authenticated;
grant execute on function public.set_match_odds(
  uuid, numeric, numeric, numeric
) to service_role;

-- Toutes les relations utilisées par ces fonctions sont déjà qualifiées avec
-- leur schéma. Un search_path vide évite qu'un objet homonyme soit résolu dans
-- un schéma inattendu. Les fonctions absentes d'une base locale minimale sont
-- ignorées, mais elles sont présentes sur le schéma de production audité.
do $search_path_hardening$
declare
  v_signature text;
  v_function regprocedure;
begin
  foreach v_signature in array array[
    'public.profile_badge_metrics(uuid)',
    'public.set_badge_featured(text,boolean)',
    'public.staff_award_badge(uuid,text)',
    'public.staff_create_badge(text,text,text,text,text,text)',
    'public.staff_list_historical_players()',
    'public.staff_revoke_badge(uuid,text)',
    'public.staff_set_historical_profile(uuid,bigint)',
    'public.staff_set_match_attendance(uuid,uuid[])',
    'public.staff_set_match_mvp(uuid,uuid[])'
  ]
  loop
    v_function := to_regprocedure(v_signature);
    if v_function is not null then
      execute format(
        'alter function %s set search_path to %L',
        v_function,
        ''
      );
    end if;
  end loop;
end;
$search_path_hardening$;

-- Ces tables sont exclusivement alimentées par des fonctions privilégiées.
-- Une politique restrictive explicite documente l'intention et empêche une
-- future politique permissive de les exposer accidentellement aux clients.
alter table public.push_delivery_log enable row level security;
drop policy if exists push_delivery_log_deny_client_roles
  on public.push_delivery_log;
create policy push_delivery_log_deny_client_roles
on public.push_delivery_log
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

alter table public.season_awards enable row level security;
drop policy if exists season_awards_deny_client_roles
  on public.season_awards;
create policy season_awards_deny_client_roles
on public.season_awards
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

-- Invariants de migration : toute dérive doit interrompre l'application avant
-- qu'un état partiellement durci puisse être conservé.
do $security_assertions$
declare
  v_bad_search_path bigint;
  v_policy_count bigint;
begin
  if has_function_privilege(
       'authenticated',
       'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.staff_set_match_attendance(uuid,uuid[])',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.staff_set_match_mvp(uuid,uuid[])',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.set_match_odds(uuid,numeric,numeric,numeric)',
       'EXECUTE'
     ) then
    raise exception 'an internal RPC remains executable by authenticated';
  end if;

  if not has_function_privilege(
       'service_role',
       'public.finalize_match_postgame(uuid,integer,jsonb,uuid,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.staff_set_match_attendance(uuid,uuid[])',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.staff_set_match_mvp(uuid,uuid[])',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.set_match_odds(uuid,numeric,numeric,numeric)',
       'EXECUTE'
     ) then
    raise exception 'service_role lost an internal RPC privilege';
  end if;

  select count(*)
    into v_bad_search_path
  from unnest(array[
    'public.profile_badge_metrics(uuid)',
    'public.set_badge_featured(text,boolean)',
    'public.staff_award_badge(uuid,text)',
    'public.staff_create_badge(text,text,text,text,text,text)',
    'public.staff_list_historical_players()',
    'public.staff_revoke_badge(uuid,text)',
    'public.staff_set_historical_profile(uuid,bigint)',
    'public.staff_set_match_attendance(uuid,uuid[])',
    'public.staff_set_match_mvp(uuid,uuid[])'
  ]::text[]) as expected(signature)
  join pg_catalog.pg_proc p
    on p.oid = pg_catalog.to_regprocedure(expected.signature)
  where not coalesce(p.proconfig, '{}'::text[])
    @> array['search_path=""'];

  if v_bad_search_path <> 0 then
    raise exception
      'empty search_path assertion failed for % function(s)',
      v_bad_search_path;
  end if;

  select count(*)
    into v_policy_count
  from pg_catalog.pg_policies
  where schemaname = 'public'
    and policyname in (
      'push_delivery_log_deny_client_roles',
      'season_awards_deny_client_roles'
    )
    and permissive = 'RESTRICTIVE'
    and cmd = 'ALL'
    and roles @> array['anon', 'authenticated']::name[];

  if v_policy_count <> 2 then
    raise exception
      'internal table deny-policy assertion failed: %/2',
      v_policy_count;
  end if;

  if has_schema_privilege('public', 'public', 'CREATE')
     or has_schema_privilege('anon', 'public', 'CREATE')
     or has_schema_privilege('authenticated', 'public', 'CREATE') then
    raise exception 'a client role can still create objects in public';
  end if;
end;
$security_assertions$;
