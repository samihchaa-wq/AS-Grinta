begin;

-- La gestion manuelle des badges est une responsabilité distincte de
-- l'administration générale. Les clients humains autorisés sont identifiés par
-- leur UUID de profil stable ; le service_role reste disponible pour la
-- maintenance serveur.
create or replace function private.can_manage_badges()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(auth.jwt() ->> 'role' = 'service_role', false)
    or exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.status = 'active'
        and p.role = 'admin'
        and p.id = any (
          array[
            '89f24276-dac0-4046-87a3-6c28e48fef3a'::uuid,
            '5c681291-ec75-47ed-8bee-1b538b69cefe'::uuid
          ]
        )
    );
$$;

revoke all on function private.can_manage_badges() from public, anon;
grant execute on function private.can_manage_badges() to authenticated, service_role;

create or replace function public.staff_create_badge(
  p_code text,
  p_name text,
  p_emoji text default '🏅',
  p_description text default '',
  p_image_url text default null,
  p_color text default '#C0455B'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_manage_badges() then
    raise exception 'Badge administration access required' using errcode = '42501';
  end if;

  if p_code is null or p_code = '' or p_name is null or p_name = '' then
    raise exception 'code and name are required' using errcode = '22023';
  end if;

  insert into public.badges(
    code, name, description, emoji, image_url, color,
    family, auto, kind, category, metric, threshold, sort_order
  )
  values (
    p_code,
    p_name,
    coalesce(p_description, ''),
    coalesce(nullif(p_emoji, ''), '🏅'),
    p_image_url,
    coalesce(nullif(p_color, ''), '#C0455B'),
    'joueur',
    false,
    'custom',
    'faits_de_jeu',
    null,
    null,
    900
  )
  on conflict (code) do update
  set name = excluded.name,
      emoji = excluded.emoji,
      description = excluded.description,
      image_url = excluded.image_url,
      color = excluded.color;

  return true;
end;
$$;

create or replace function public.staff_award_badge(
  p_profile_id uuid,
  p_badge_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_badge_id uuid;
  v_badge_name text;
  v_occurred_at timestamptz := now();
  v_before jsonb;
  v_after jsonb;
begin
  if not private.can_manage_badges() then
    raise exception 'Badge administration access required' using errcode = '42501';
  end if;

  select id, name
  into v_badge_id, v_badge_name
  from public.badges
  where code = p_badge_code;

  if not found then
    raise exception 'Unknown badge' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.profiles p where p.id = p_profile_id
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

  select jsonb_build_object(
    'profile_id', pb.profile_id,
    'badge_id', pb.badge_id,
    'source', pb.source,
    'awarded_by', pb.awarded_by,
    'awarded_at', pb.awarded_at
  )
  into v_before
  from public.profile_badges pb
  where pb.profile_id = p_profile_id
    and pb.badge_id = v_badge_id;

  if v_before is not null and v_before ->> 'source' = 'manual' then
    return true;
  end if;

  insert into public.profile_badges(
    profile_id, badge_id, source, awarded_by, awarded_at
  )
  values (
    p_profile_id, v_badge_id, 'manual', auth.uid(), v_occurred_at
  )
  on conflict (profile_id, badge_id) do update
  set source = 'manual',
      awarded_by = auth.uid(),
      awarded_at = v_occurred_at
  returning jsonb_build_object(
    'profile_id', profile_id,
    'badge_id', badge_id,
    'source', source,
    'awarded_by', awarded_by,
    'awarded_at', awarded_at
  )
  into v_after;

  insert into private.profile_badge_audit_log(
    event_type,
    profile_id,
    badge_id,
    badge_code,
    badge_name,
    actor_profile_id,
    occurred_at,
    source,
    metadata,
    state_before,
    state_after
  )
  values (
    'award',
    p_profile_id,
    v_badge_id,
    p_badge_code,
    v_badge_name,
    auth.uid(),
    v_occurred_at,
    'manual',
    jsonb_build_object(
      'reason',
      case when v_before is null then 'manual_award' else 'manual_override' end
    ),
    v_before,
    v_after
  );

  return true;
end;
$$;

create or replace function public.staff_revoke_badge(
  p_profile_id uuid,
  p_badge_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_badge_id uuid;
  v_badge_name text;
  v_before jsonb;
  v_removed_source text;
  v_occurred_at timestamptz := now();
begin
  if not private.can_manage_badges() then
    raise exception 'Badge administration access required' using errcode = '42501';
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
  returning
    source,
    jsonb_build_object(
      'profile_id', profile_id,
      'badge_id', badge_id,
      'source', source,
      'awarded_by', awarded_by,
      'awarded_at', awarded_at
    )
  into v_removed_source, v_before;

  if found then
    insert into private.profile_badge_audit_log(
      event_type,
      profile_id,
      badge_id,
      badge_code,
      badge_name,
      actor_profile_id,
      occurred_at,
      source,
      metadata,
      state_before,
      state_after
    )
    values (
      'revoke',
      p_profile_id,
      v_badge_id,
      p_badge_code,
      v_badge_name,
      auth.uid(),
      v_occurred_at,
      v_removed_source,
      jsonb_build_object('reason', 'manual_revoke'),
      v_before,
      null
    );
  end if;

  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$$;

create or replace function public.staff_update_badge_image(
  p_badge_code text,
  p_image_url text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_manage_badges() then
    raise exception 'Badge administration access required' using errcode = '42501';
  end if;

  if nullif(btrim(p_badge_code), '') is null then
    raise exception 'Badge code is required' using errcode = '22023';
  end if;

  if nullif(btrim(p_image_url), '') is null then
    raise exception 'Badge image URL is required' using errcode = '22023';
  end if;

  if position('/storage/v1/object/public/badge-images/' in p_image_url) = 0 then
    raise exception 'Badge image must come from badge-images storage'
      using errcode = '22023';
  end if;

  update public.badges
  set image_url = btrim(p_image_url)
  where code = btrim(p_badge_code);

  if not found then
    raise exception 'Badge not found' using errcode = 'P0002';
  end if;

  return true;
end;
$$;

drop policy if exists badge_images_admin_insert on storage.objects;
create policy badge_images_admin_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'badge-images'
  and (select private.can_manage_badges())
);

drop policy if exists badge_images_admin_update on storage.objects;
create policy badge_images_admin_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'badge-images'
  and (select private.can_manage_badges())
)
with check (
  bucket_id = 'badge-images'
  and (select private.can_manage_badges())
);

drop policy if exists badge_images_admin_delete on storage.objects;
create policy badge_images_admin_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'badge-images'
  and (select private.can_manage_badges())
);

commit;
