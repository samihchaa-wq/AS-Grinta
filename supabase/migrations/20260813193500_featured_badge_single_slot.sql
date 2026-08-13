-- Un seul badge arboré par personne, au lieu de deux.
--
-- L'emplacement devient unique : arborer un badge libère automatiquement le
-- précédent, plutôt que de refuser le choix une fois le quota atteint. Sans
-- ça, quelqu'un qui arbore déjà son maximum devrait d'abord retirer un badge
-- avant d'en poser un autre.

create or replace function public.set_badge_featured(
  p_badge_code text,
  p_featured boolean
) returns void
    language plpgsql
    security definer
    set search_path to ''
    as $$
declare
  v_uid uuid := auth.uid();
  v_badge uuid;
begin
  if v_uid is null then
    raise exception 'Connexion requise.' using errcode = '42501';
  end if;

  select id into v_badge from public.badges where code = p_badge_code;
  if v_badge is null then
    raise exception 'Badge introuvable.' using errcode = '22023';
  end if;

  update public.profile_badges set featured = p_featured
  where profile_id = v_uid and badge_id = v_badge;
  if not found then
    raise exception 'Tu ne possèdes pas ce badge.' using errcode = '42501';
  end if;

  if p_featured then
    update public.profile_badges set featured = false
    where profile_id = v_uid and badge_id <> v_badge and featured;
  end if;
end;
$$;

comment on function public.set_badge_featured(text, boolean) is
  'Arbore un badge : l''emplacement est unique, le badge précédent est libéré.';

-- Ramène les profils qui arboraient deux badges à un seul. On garde celui qui
-- s'affichait en premier, c'est-à-dire le sort_order le plus bas : c'est
-- exactement l'ordre de featured_badges(), donc le badge déjà visible à côté
-- du prénom ne change pas.
with ranked as (
  select
    profile_badge.profile_id,
    profile_badge.badge_id,
    row_number() over (
      partition by profile_badge.profile_id
      order by badge.sort_order, badge.code
    ) as position
  from public.profile_badges profile_badge
  join public.badges badge on badge.id = profile_badge.badge_id
  where profile_badge.featured
)
update public.profile_badges profile_badge
set featured = false
from ranked
where ranked.profile_id = profile_badge.profile_id
  and ranked.badge_id = profile_badge.badge_id
  and ranked.position > 1;
