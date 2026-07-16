-- On réduit le nombre de badges arborables de 3 à 2 (pour pouvoir les
-- afficher plus gros à côté du prénom).
create or replace function public.set_badge_featured(
  p_badge_code text, p_featured boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_badge uuid;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Connexion requise.' using errcode = '42501';
  end if;
  select id into v_badge from public.badges where code = p_badge_code;
  if v_badge is null then
    raise exception 'Badge introuvable.' using errcode = '22023';
  end if;
  if p_featured then
    select count(*) into v_count from public.profile_badges
    where profile_id = v_uid and featured and badge_id <> v_badge;
    if v_count >= 2 then
      raise exception 'Tu peux arborer 2 badges maximum.' using errcode = '23514';
    end if;
  end if;
  update public.profile_badges set featured = p_featured
  where profile_id = v_uid and badge_id = v_badge;
  if not found then
    raise exception 'Tu ne possèdes pas ce badge.' using errcode = '42501';
  end if;
end;
$$;

-- Rétablit la cohérence : si quelqu'un arborait déjà 3 badges, on ne garde
-- que les 2 premiers (par sort_order), les autres sont retirés.
with ranked as (
  select pb.profile_id, pb.badge_id,
         row_number() over (
           partition by pb.profile_id order by b.sort_order, b.code
         ) as rn
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  where pb.featured
)
update public.profile_badges pb
set featured = false
from ranked r
where pb.profile_id = r.profile_id
  and pb.badge_id = r.badge_id
  and r.rn > 2;
