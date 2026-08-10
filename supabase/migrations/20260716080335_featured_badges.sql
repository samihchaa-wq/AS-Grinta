-- « Arborer » un badge : le joueur met en avant jusqu'à 3 badges obtenus, qui
-- s'affichent à côté de son prénom partout dans l'app.
alter table public.profile_badges
  add column if not exists featured boolean not null default false;

create index if not exists idx_profile_badges_featured
  on public.profile_badges (profile_id) where featured;

-- Lecture des badges arborés de tout le monde (pour l'affichage à côté des noms).
create or replace function public.featured_badges()
returns table(profile_id uuid, code text, emoji text, image_url text, sort_order integer)
language sql
security definer
set search_path to 'public'
stable
as $$
  select pb.profile_id, b.code, b.emoji, b.image_url, b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  where pb.featured
  order by pb.profile_id, b.sort_order;
$$;
revoke all on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated;

-- Arborer / retirer un badge (max 3) pour la personne connectée.
create or replace function public.set_badge_featured(p_badge_code text, p_featured boolean)
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
    if v_count >= 3 then
      raise exception 'Tu peux arborer 3 badges maximum.' using errcode = '23514';
    end if;
  end if;
  update public.profile_badges set featured = p_featured
  where profile_id = v_uid and badge_id = v_badge;
  if not found then
    raise exception 'Tu ne possèdes pas ce badge.' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.set_badge_featured(text, boolean) from public, anon;
grant execute on function public.set_badge_featured(text, boolean) to authenticated;;
