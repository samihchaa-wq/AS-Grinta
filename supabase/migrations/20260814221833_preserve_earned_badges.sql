-- Audit 15/08/2026 : un badge de palier déjà gagné doit rester acquis à vie.
--
-- recalculate_profile_badges() était redevenue destructive depuis
-- 20260721130455_fix_season_points_target_and_badge_revocation : lorsqu'une
-- métrique repassait sous un seuil, la fonction supprimait le badge auto.
-- Le recalcul redevient strictement additif : il peut attribuer de nouveaux
-- badges, mais le retrait reste une action explicite (staff / suppression du
-- catalogue), jamais une conséquence d'un recalcul de statistiques.

begin;

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

  select to_jsonb(t)
  into v
  from private.profile_badge_metrics(p_profile_id) t;

  if v is null then
    return;
  end if;

  for b in
    select id, metric, threshold
    from public.badges
    where auto
      and kind = 'tier'
      and metric is not null
      and threshold is not null
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

comment on function public.recalculate_profile_badges(uuid) is
  'Recalcule les badges automatiques de façon additive : un badge gagné n’est jamais retiré automatiquement.';

commit;
