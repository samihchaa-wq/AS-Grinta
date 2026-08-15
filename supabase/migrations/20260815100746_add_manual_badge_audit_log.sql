begin;

create table if not exists private.profile_badge_audit_log (
  id bigint generated always as identity primary key,
  event_type text not null
    check (event_type in ('award', 'revoke')),
  profile_id uuid not null,
  badge_id uuid,
  badge_code text not null,
  badge_name text not null,
  actor_profile_id uuid,
  occurred_at timestamptz not null default now(),
  is_backfill boolean not null default false
);

comment on table private.profile_badge_audit_log is
  'Journal append-only des attributions et retraits manuels de badges.';
comment on column private.profile_badge_audit_log.is_backfill is
  'True uniquement pour la reprise des badges manuels déjà présents lors de la création du journal.';

alter table private.profile_badge_audit_log enable row level security;
revoke all on table private.profile_badge_audit_log from public, anon, authenticated;
grant select on table private.profile_badge_audit_log to service_role;

create or replace function private.reject_profile_badge_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception 'profile_badge_audit_log is append-only'
    using errcode = '55000';
end;
$function$;

revoke all on function private.reject_profile_badge_audit_mutation()
  from public, anon, authenticated;

create trigger trg_profile_badge_audit_immutable
before update or delete on private.profile_badge_audit_log
for each row execute function private.reject_profile_badge_audit_mutation();

insert into private.profile_badge_audit_log (
  event_type,
  profile_id,
  badge_id,
  badge_code,
  badge_name,
  actor_profile_id,
  occurred_at,
  is_backfill
)
select
  'award',
  pb.profile_id,
  b.id,
  b.code,
  b.name,
  pb.awarded_by,
  pb.awarded_at,
  true
from public.profile_badges pb
join public.badges b on b.id = pb.badge_id
where pb.source = 'manual'
  and not exists (
    select 1
    from private.profile_badge_audit_log audit
    where audit.event_type = 'award'
      and audit.profile_id = pb.profile_id
      and audit.badge_id = pb.badge_id
      and audit.occurred_at = pb.awarded_at
      and audit.is_backfill
  );

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
  v_badge_name text;
  v_occurred_at timestamptz := now();
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;

  select id, name
  into v_badge_id, v_badge_name
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

  insert into public.profile_badges(
    profile_id,
    badge_id,
    source,
    awarded_by,
    awarded_at
  )
  values (
    p_profile_id,
    v_badge_id,
    'manual',
    auth.uid(),
    v_occurred_at
  )
  on conflict (profile_id, badge_id)
  do update set
    source = 'manual',
    awarded_by = auth.uid(),
    awarded_at = v_occurred_at;

  insert into private.profile_badge_audit_log (
    event_type,
    profile_id,
    badge_id,
    badge_code,
    badge_name,
    actor_profile_id,
    occurred_at
  )
  values (
    'award',
    p_profile_id,
    v_badge_id,
    p_badge_code,
    v_badge_name,
    auth.uid(),
    v_occurred_at
  );

  return true;
end;
$function$;

create or replace function public.staff_revoke_badge(
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
  v_badge_name text;
  v_removed boolean := false;
  v_occurred_at timestamptz := now();
begin
  if not public.is_moderator() then
    raise exception 'Moderator role required' using errcode = '42501';
  end if;

  select id, name
  into v_badge_id, v_badge_name
  from public.badges
  where code = p_badge_code;

  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;

  delete from public.profile_badges
  where profile_id = p_profile_id
    and badge_id = v_badge_id
  returning true into v_removed;

  if coalesce(v_removed, false) then
    insert into private.profile_badge_audit_log (
      event_type,
      profile_id,
      badge_id,
      badge_code,
      badge_name,
      actor_profile_id,
      occurred_at
    )
    values (
      'revoke',
      p_profile_id,
      v_badge_id,
      p_badge_code,
      v_badge_name,
      auth.uid(),
      v_occurred_at
    );
  end if;

  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$function$;

commit;
