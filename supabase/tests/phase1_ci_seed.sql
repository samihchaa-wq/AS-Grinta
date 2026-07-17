\set ON_ERROR_STOP on

begin;

-- The first tracked profile-status trigger still calls the pre-named-roster
-- season_predictions contract. Production already had seeded profiles before
-- that transition; a clean replay does not. Disable only this obsolete trigger
-- while creating synthetic CI profiles, then restore it in the same transaction.
alter table public.profiles
  disable trigger trg_seed_predictions_for_new_active_profile;

update public.profiles
set role = 'admin', status = 'active', updated_at = now()
where email = 'ci-admin@example.invalid';

update public.profiles
set role = 'pronostiqueur', status = 'active', updated_at = now()
where email = 'ci-normal@example.invalid';

do $$
begin
  if not exists (select 1 from public.profiles where email = 'ci-admin@example.invalid') then
    raise exception 'CI admin profile was not created by local Auth';
  end if;
  if not exists (select 1 from public.profiles where email = 'ci-normal@example.invalid') then
    raise exception 'CI normal profile was not created by local Auth';
  end if;
end
$$;

insert into auth.users (id, email, raw_user_meta_data)
select
  gen_random_uuid(),
  format('ci-bulk-%s@example.invalid', n),
  jsonb_build_object('first_name', 'Bulk', 'last_name', 'Synthetic')
from generate_series(1, 118) as g(n)
where not exists (
  select 1
  from auth.users u
  where u.email = format('ci-bulk-%s@example.invalid', n)
);

alter table public.profiles
  enable trigger trg_seed_predictions_for_new_active_profile;

update public.seasons set status = 'archived' where status = 'open';

insert into public.seasons (name, status)
values ('2098-2099', 'open')
on conflict (name) do update set status = excluded.status;

with ids as (
  select
    (select id from public.seasons where name = '2098-2099') as season_id,
    (select id from public.profiles where email = 'ci-normal@example.invalid') as normal_id,
    (select id from public.profiles where email = 'ci-admin@example.invalid') as admin_id
)
insert into public.season_players (
  season_id, first_name, last_name, is_goalkeeper, is_active, profile_id, "position"
)
select season_id, 'Normal', 'Player', false, true, normal_id, 1 from ids
union all
select season_id, 'Admin', 'Keeper', true, true, admin_id, 2 from ids
on conflict do nothing;

insert into public.profile_badges (
  profile_id, badge_id, source, awarded_by, featured
)
select
  p.id,
  b.id,
  'manual',
  p.id,
  row_number() over (partition by p.id order by b.sort_order, b.id) = 1
from public.profiles p
cross join public.badges b
where p.email like 'ci-%@example.invalid'
on conflict (profile_id, badge_id) do update
set awarded_by = excluded.awarded_by,
    featured = excluded.featured;

insert into public.season_awards (season_id, profile_id, award_type)
select s.id, p.id, award_type
from public.seasons s
join public.profiles p on p.email like 'ci-%@example.invalid'
cross join unnest(array['season_complete', 'most_present', 'top_scorer']) as a(award_type)
where s.name = '2098-2099'
on conflict (season_id, profile_id, award_type) do nothing;

commit;

analyze public.profiles;
analyze public.badges;
analyze public.profile_badges;
analyze public.season_awards;
analyze public.season_players;
