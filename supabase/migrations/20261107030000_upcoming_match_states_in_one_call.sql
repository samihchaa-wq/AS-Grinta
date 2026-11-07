-- Calendrier : la disponibilité et la cloche des buts de tous les matchs à
-- venir en une seule demande.
--
-- Chaque carte de match à venir appelait séparément
-- `get_my_match_availability` et `get_match_live_notification_subscription` :
-- environ 26 requêtes à chaque affichage du calendrier (journaux d'API du
-- 7 novembre 2026), les pastilles apparaissant une par une.
--
-- Cette fonction ne contient aucune règle nouvelle : elle appelle les deux
-- fonctions existantes pour chaque match demandé, dans le contexte de
-- l'appelant (SECURITY INVOKER), donc avec exactement leurs contrôles. Une
-- erreur sur un match (match supprimé, profil inactif…) n'empêche pas les
-- autres : la part concernée est marquée `*_ok = false` et l'application
-- refait alors l'appel individuel, qui rend l'erreur d'origine.
--
-- Changement additif : aucune fonction existante n'est modifiée.

create or replace function public.get_my_upcoming_match_states(p_match_ids uuid[])
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_result jsonb := '{}'::jsonb;
  v_match_id uuid;
  v_availability jsonb;
  v_availability_ok boolean;
  v_live jsonb;
  v_live_ok boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if coalesce(cardinality(p_match_ids), 0) > 60 then
    raise exception 'Too many matches requested' using errcode = '22023';
  end if;

  for v_match_id in
    select distinct requested.match_id
    from unnest(coalesce(p_match_ids, '{}'::uuid[])) as requested(match_id)
    where requested.match_id is not null
  loop
    begin
      v_availability := public.get_my_match_availability(v_match_id);
      v_availability_ok := true;
    exception when others then
      v_availability := null;
      v_availability_ok := false;
    end;

    begin
      v_live := public.get_match_live_notification_subscription(v_match_id);
      v_live_ok := true;
    exception when others then
      v_live := null;
      v_live_ok := false;
    end;

    v_result := v_result || jsonb_build_object(
      v_match_id::text,
      jsonb_build_object(
        'availability_ok', v_availability_ok,
        'availability', v_availability,
        'live_notifications_ok', v_live_ok,
        'live_notifications', v_live
      )
    );
  end loop;

  return v_result;
end;
$function$;

comment on function public.get_my_upcoming_match_states(uuid[]) is
  'Disponibilité et cloche des buts de plusieurs matchs en un appel. '
  'Reprend get_my_match_availability et '
  'get_match_live_notification_subscription avec les droits de l''appelant.';

revoke all on function public.get_my_upcoming_match_states(uuid[])
  from public, anon;
grant execute on function public.get_my_upcoming_match_states(uuid[])
  to authenticated, service_role;
