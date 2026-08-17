begin;

alter table private.profile_badge_audit_log
  add column if not exists source text not null default 'manual',
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists state_before jsonb,
  add column if not exists state_after jsonb;

do $do$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'private.profile_badge_audit_log'::regclass
      and conname = 'profile_badge_audit_log_source_check'
  ) then
    alter table private.profile_badge_audit_log
      add constraint profile_badge_audit_log_source_check
      check (source in ('manual', 'auto'));
  end if;
end;
$do$;

comment on table private.profile_badge_audit_log is
  'Journal append-only des attributions et retraits de badges, manuels ou automatiques.';
comment on column private.profile_badge_audit_log.source is
  'Origine de la mutation auditée : manual ou auto.';
comment on column private.profile_badge_audit_log.metadata is
  'Contexte non sensible de la mutation (raison, métrique, seuil et valeur lorsque disponible).';
comment on column private.profile_badge_audit_log.state_before is
  'État courant du badge avant la mutation, null pour une attribution initiale.';
comment on column private.profile_badge_audit_log.state_after is
  'État courant du badge après la mutation, null pour un retrait.';

-- Une attribution manuelle déjà manuelle est idempotente : elle ne réécrit ni
-- l'horodatage ni le journal. Une attribution automatique existante peut en
-- revanche être convertie explicitement en attribution manuelle.
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
  v_before jsonb;
  v_after jsonb;
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
  on conflict (profile_id, badge_id)
  do update set
    source = 'manual',
    awarded_by = auth.uid(),
    awarded_at = v_occurred_at
  returning jsonb_build_object(
    'profile_id', profile_id,
    'badge_id', badge_id,
    'source', source,
    'awarded_by', awarded_by,
    'awarded_at', awarded_at
  ) into v_after;

  insert into private.profile_badge_audit_log (
    event_type, profile_id, badge_id, badge_code, badge_name,
    actor_profile_id, occurred_at, source, metadata,
    state_before, state_after
  )
  values (
    'award', p_profile_id, v_badge_id, p_badge_code, v_badge_name,
    auth.uid(), v_occurred_at, 'manual',
    jsonb_build_object(
      'reason', case when v_before is null then 'manual_award' else 'manual_override' end
    ),
    v_before, v_after
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
  v_before jsonb;
  v_removed_source text;
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
    insert into private.profile_badge_audit_log (
      event_type, profile_id, badge_id, badge_code, badge_name,
      actor_profile_id, occurred_at, source, metadata,
      state_before, state_after
    )
    values (
      'revoke', p_profile_id, v_badge_id, p_badge_code, v_badge_name,
      auth.uid(), v_occurred_at, v_removed_source,
      jsonb_build_object('reason', 'manual_revoke'),
      v_before, null
    );
  end if;

  perform public.recalculate_profile_badges(p_profile_id);
  return true;
end;
$function$;

-- Les badges automatiques sont permanents une fois acquis. Le recalcul ne
-- journalise donc que les nouvelles attributions réellement insérées et reste
-- silencieux lorsqu'un recalcul identique ne change rien.
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
  v_after jsonb;
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
    select id, code, name, metric, threshold
    from public.badges
    where auto
      and kind = 'tier'
      and metric is not null
      and threshold is not null
  loop
    val := coalesce((v ->> b.metric)::int, 0);

    if val >= b.threshold then
      v_after := null;

      insert into public.profile_badges(profile_id, badge_id, source)
      values (p_profile_id, b.id, 'auto')
      on conflict (profile_id, badge_id) do nothing
      returning jsonb_build_object(
        'profile_id', profile_id,
        'badge_id', badge_id,
        'source', source,
        'awarded_by', awarded_by,
        'awarded_at', awarded_at
      ) into v_after;

      if v_after is not null then
        insert into private.profile_badge_audit_log (
          event_type, profile_id, badge_id, badge_code, badge_name,
          actor_profile_id, occurred_at, source, metadata,
          state_before, state_after
        )
        values (
          'award', p_profile_id, b.id, b.code, b.name,
          null, now(), 'auto',
          jsonb_build_object(
            'reason', 'metric_threshold_met',
            'metric', b.metric,
            'threshold', b.threshold,
            'value', val
          ),
          null, v_after
        );
      end if;
    end if;
  end loop;
end;
$function$;

commit;
