-- Add a dedicated manual-only goalkeeper role badge.
insert into public.badges (
  code,
  name,
  description,
  emoji,
  image_url,
  family,
  auto,
  kind,
  category,
  metric,
  threshold,
  sort_order,
  color,
  has_star,
  standalone,
  secret
)
values (
  'role_goalkeeper',
  'Gardien',
  'Exercer officiellement la fonction de gardien du club.',
  '🧤',
  null,
  'joueur',
  false,
  'custom',
  'palmares',
  null,
  null,
  911,
  '#1C1C24',
  false,
  false,
  false
)
on conflict (code) do update
set
  name = excluded.name,
  description = excluded.description,
  emoji = excluded.emoji,
  family = excluded.family,
  auto = false,
  kind = 'custom',
  category = 'palmares',
  metric = null,
  threshold = null,
  sort_order = excluded.sort_order,
  color = excluded.color,
  has_star = false,
  standalone = false,
  secret = false;

create or replace function public.staff_award_badge(
  p_profile_id uuid,
  p_badge_code text
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_badge_id uuid;
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;

  select id
  into v_badge_id
  from public.badges
  where code = p_badge_code;

  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_profile_id
  ) then
    raise exception 'Unknown profile' using errcode = '22023';
  end if;

  if p_badge_code = 'role_goalkeeper'
     and not exists (
       select 1
       from public.profiles p
       where p.id = p_profile_id
         and p.is_goalkeeper is true
     ) then
    raise exception 'Goalkeeper badge can only be awarded to a goalkeeper'
      using errcode = '22023';
  end if;

  insert into public.profile_badges(profile_id, badge_id, source, awarded_by)
  values (p_profile_id, v_badge_id, 'manual', auth.uid())
  on conflict (profile_id, badge_id)
  do update set
    source = 'manual',
    awarded_by = auth.uid(),
    awarded_at = now();

  return true;
end;
$function$;

revoke all on function public.staff_award_badge(uuid, text) from public, anon;
grant execute on function public.staff_award_badge(uuid, text) to authenticated, service_role;
