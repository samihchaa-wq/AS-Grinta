-- Règle de rôle pour les badges :
--   • un GARDIEN ne peut pas avoir les badges de buts
--     (goals, goals_season, doubles, max_match_goals) ;
--   • un JOUEUR DE CHAMP ne peut pas avoir les badges clean sheets
--     (clean_sheets, clean_sheets_season).
--
-- 1) L'attribution automatique respecte le rôle.
create or replace function public.recalculate_profile_badges(p_profile_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v jsonb;
  b record;
  val integer;
  v_is_keeper boolean;
begin
  if p_profile_id is null then
    return;
  end if;
  select is_goalkeeper into v_is_keeper from public.profiles where id = p_profile_id;
  select to_jsonb(t) into v from public.profile_badge_metrics(p_profile_id) t;
  if v is null then
    return;
  end if;
  for b in
    select id, metric, threshold from public.badges
    where auto and kind = 'tier' and metric is not null and threshold is not null
  loop
    -- Gardien : pas de badges de buts. Joueur de champ : pas de clean sheets.
    if coalesce(v_is_keeper, false)
       and b.metric in ('goals', 'goals_season', 'doubles', 'max_match_goals') then
      continue;
    end if;
    if not coalesce(v_is_keeper, false)
       and b.metric in ('clean_sheets', 'clean_sheets_season') then
      continue;
    end if;
    val := coalesce((v ->> b.metric)::int, 0);
    if val >= b.threshold then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    end if;
  end loop;
end;
$function$;

-- 2) Nettoyage : retirer les badges déjà attribués qui violent la règle de rôle.
delete from public.profile_badges pb
using public.badges b, public.profiles p
where pb.badge_id = b.id
  and pb.profile_id = p.id
  and (
    (p.is_goalkeeper
       and b.metric in ('goals', 'goals_season', 'doubles', 'max_match_goals'))
    or (not p.is_goalkeeper
       and b.metric in ('clean_sheets', 'clean_sheets_season'))
  );
