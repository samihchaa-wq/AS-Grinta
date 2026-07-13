begin;

create temporary table critical_test_context on commit drop as
select
  actor.id as actor_id,
  other_profile.id as other_profile_id,
  open_prediction.match_id as open_match_id,
  closed_prediction.match_id as closed_match_id
from lateral (
  select p.id
  from public.profiles p
  where p.status = 'active'
    and p.role = 'pronostiqueur'
  order by p.created_at
  limit 1
) actor
cross join lateral (
  select p.id
  from public.profiles p
  where p.status = 'active'
    and p.role = 'pronostiqueur'
    and p.id <> actor.id
  order by p.created_at
  limit 1
) other_profile
cross join lateral (
  select mp.match_id
  from public.match_predictions mp
  join public.matches m on m.id = mp.match_id
  where mp.profile_id = actor.id
    and m.status = 'a_venir'
    and now() < (
      m.match_date::timestamp + m.match_time - interval '5 minutes'
    )
    and (
      m.predictions_closed_at is null
      or now() < m.predictions_closed_at
    )
  order by m.match_date, m.match_time
  limit 1
) open_prediction
cross join lateral (
  select mp.match_id
  from public.match_predictions mp
  join public.matches m on m.id = mp.match_id
  where mp.profile_id = actor.id
    and (
      m.status <> 'a_venir'
      or now() >= (
        m.match_date::timestamp + m.match_time - interval '5 minutes'
      )
      or (
        m.predictions_closed_at is not null
        and now() >= m.predictions_closed_at
      )
    )
  order by m.match_date desc, m.match_time desc
  limit 1
) closed_prediction;

DO $$
begin
  if (select count(*) from critical_test_context) <> 1 then
    raise exception 'Critical invariant fixtures are incomplete';
  end if;
end
$$;

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', actor_id,
    'role', 'authenticated'
  )::text,
  true
)
from critical_test_context;

set local role authenticated;

DO $$
declare
  context_row record;
  affected integer;
  rejected boolean;
  original_role text;
begin
  select * into strict context_row from critical_test_context;

  update public.match_predictions
  set predicted_score_as_grinta = 2,
      predicted_score_adverse = 1,
      is_filled = true
  where match_id = context_row.open_match_id
    and profile_id = context_row.actor_id;
  get diagnostics affected = row_count;
  if affected <> 1 then
    raise exception 'Own open prediction update affected % rows', affected;
  end if;

  update public.match_predictions
  set predicted_score_as_grinta = 9
  where match_id = context_row.open_match_id
    and profile_id = context_row.other_profile_id;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'RLS allowed another profile prediction update';
  end if;

  rejected := false;
  begin
    update public.match_predictions
    set predicted_score_as_grinta = 9
    where match_id = context_row.closed_match_id
      and profile_id = context_row.actor_id;
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'Closed prediction update was not rejected';
  end if;

  select role into strict original_role
  from public.profiles
  where id = context_row.actor_id;

  rejected := false;
  begin
    update public.profiles
    set role = 'admin'
    where id = context_row.actor_id;
  exception when others then
    rejected := true;
  end;

  if not rejected then
    select role into strict original_role
    from public.profiles
    where id = context_row.actor_id;
    if original_role = 'admin' then
      raise exception 'A regular user promoted their own profile';
    end if;
  end if;

  update public.profiles
  set first_name = first_name
  where id = context_row.other_profile_id;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'RLS allowed another profile update';
  end if;
end
$$;

rollback;
