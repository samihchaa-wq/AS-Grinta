-- Couleur du carré (emblème) de chaque badge.
alter table public.badges add column if not exists color text;

-- Couleurs par défaut par famille.
update public.badges set color = case
  when metric in ('matches_played','matches_played_season') then '#2E6BE6'
  when metric in ('goals','goals_season')                   then '#2E9E63'
  when metric in ('wins','wins_season')                     then '#D9A400'
  when metric in ('clean_sheets','clean_sheets_season')     then '#17A6A0'
  when metric = 'doubles'                                    then '#7C3CFF'
  when metric = 'mvp'                                        then '#FF9D2E'
  when metric = 'max_match_goals'                            then '#FF4FCB'
  when metric = 'pred_good_result'                           then '#1DCBFF'
  when metric = 'pred_exact_score'                           then '#E0457B'
  when metric = 'seasons_complete' or metric like 'title_%'  then '#E8B923'
  else color
end
where kind='tier';

update public.badges set color = case
  when code in ('role_president','role_coach') then '#B8860B'
  else '#C0455B'
end
where kind='custom';

-- featured_badges() renvoie maintenant la couleur, le seuil et la métrique
-- pour dessiner l'emblème (carré coloré + seuil) à côté du prénom.
drop function if exists public.featured_badges();
create function public.featured_badges()
returns table(profile_id uuid, code text, emoji text, image_url text,
              color text, metric text, threshold int, sort_order integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select pb.profile_id, b.code, b.emoji, b.image_url, b.color, b.metric,
         b.threshold, b.sort_order
  from public.profile_badges pb
  join public.badges b on b.id = pb.badge_id
  where pb.featured
  order by pb.profile_id, b.sort_order;
$$;
revoke all on function public.featured_badges() from public, anon;
grant execute on function public.featured_badges() to authenticated;

-- Création d'un badge custom : on peut désormais choisir sa couleur.
drop function if exists public.staff_create_badge(text, text, text, text, text);
create function public.staff_create_badge(
  p_code text, p_name text, p_emoji text default '🏅',
  p_description text default '', p_image_url text default null,
  p_color text default '#C0455B')
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_code is null or p_code = '' or p_name is null or p_name = '' then
    raise exception 'code and name are required' using errcode = '22023';
  end if;
  insert into public.badges(code, name, description, emoji, image_url, color,
                            family, auto, kind, category, metric, threshold, sort_order)
  values (p_code, p_name, coalesce(p_description, ''),
          coalesce(nullif(p_emoji, ''), '🏅'), p_image_url,
          coalesce(nullif(p_color, ''), '#C0455B'),
          'joueur', false, 'custom', 'faits_de_jeu', null, null, 900)
  on conflict (code) do update
    set name = excluded.name, emoji = excluded.emoji,
        description = excluded.description, image_url = excluded.image_url,
        color = excluded.color;
  return true;
end;
$$;
revoke all on function public.staff_create_badge(text, text, text, text, text, text) from public, anon;
grant execute on function public.staff_create_badge(text, text, text, text, text, text) to authenticated;
