-- Annulation de la règle de rôle : tout le monde a droit à tous les badges.
-- On retire le filtre gardien/joueur de champ de l'attribution automatique, puis
-- on recalcule les badges de tous les profils pour ré-attribuer ceux qui avaient
-- été retirés (ré-insertion seulement, jamais de retrait).
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

-- Recalcule pour tous les profils (restaure les badges éventuellement retirés).
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.recalculate_profile_badges(r.id);
  end loop;
end $$;
