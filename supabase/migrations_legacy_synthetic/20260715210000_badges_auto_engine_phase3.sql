-- Phase 3 : le moteur d'attribution automatique des paliers.
-- Décerne (une fois, définitivement) chaque badge de palier dès que la métrique
-- correspondante atteint le seuil. Les métriques étant monotones (max sur une
-- saison / cumul carrière), un badge acquis reste acquis : on n'en retire jamais.
-- Les triggers existants (trg_badges_on_*) appellent déjà ces fonctions.
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
begin
  if p_profile_id is null then
    return;
  end if;
  select to_jsonb(t) into v from public.profile_badge_metrics(p_profile_id) t;
  if v is null then
    return;
  end if;
  for b in
    select id, metric, threshold from public.badges
    where auto and kind = 'tier' and metric is not null and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);
    if val >= b.threshold then
      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing;
    end if;
  end loop;
end;
$function$;

create or replace function public.recalculate_all_badges()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
begin
  for r in select id from public.profiles loop
    perform public.recalculate_profile_badges(r.id);
  end loop;
end;
$function$;

-- Backfill de l'existant.
select public.recalculate_all_badges();
