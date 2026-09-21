begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users(id, email, raw_user_meta_data)
values
  ('b6100000-0000-0000-0000-000000000001', 'season-space-admin@example.invalid', '{"first_name":"Admin"}'::jsonb),
  ('b6100000-0000-0000-0000-000000000002', 'season-space-one@example.invalid', '{"first_name":"Joueur Un"}'::jsonb),
  ('b6100000-0000-0000-0000-000000000003', 'season-space-two@example.invalid', '{"first_name":"Joueur Deux"}'::jsonb);

update public.profiles
set role = case
      when id = 'b6100000-0000-0000-0000-000000000001' then 'admin'
      else 'pronostiqueur'
    end,
    status = 'active',
    updated_at = now()
where id between
  'b6100000-0000-0000-0000-000000000001'
  and 'b6100000-0000-0000-0000-000000000003';

insert into public.seasons(id, name, status)
values
  ('b6200000-0000-0000-0000-000000000001', '2090-2091', 'open'),
  ('b6200000-0000-0000-0000-000000000002', '2089-2090', 'terminee'),
  ('b6200000-0000-0000-0000-000000000003', '2088-2089', 'archived');

insert into public.season_players(
  id, season_id, first_name, last_name, is_goalkeeper,
  is_active, position, profile_id
)
values
  (
    'b6300000-0000-0000-0000-000000000001',
    'b6200000-0000-0000-0000-000000000001',
    'Buteur', 'Saison', false, true, 1,
    'b6100000-0000-0000-0000-000000000002'
  ),
  (
    'b6300000-0000-0000-0000-000000000002',
    'b6200000-0000-0000-0000-000000000001',
    'Gardien', 'Saison', true, true, 2,
    'b6100000-0000-0000-0000-000000000003'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"b6100000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

create temporary table pg_temp.season_name_state_space(
  case_number integer primary key,
  proposed_name text,
  expected_success boolean not null,
  observed_success boolean not null,
  returned_name text,
  returned_status text,
  open_count integer not null,
  sqlstate text,
  message text,
  mismatch boolean not null
) on commit drop;
grant select, insert, update, delete
on pg_temp.season_name_state_space to authenticated;

do $state_space$
declare
  v_case integer := 0;
  v_name text;
  v_expected boolean;
  v_id uuid;
  v_ok boolean;
  v_state text;
  v_message text;
  v_returned_name text;
  v_returned_status text;
  v_open_count integer;
  v_mismatch boolean;
begin
  for v_name, v_expected in
    select * from (values
      ('2000-2001'::text, true),
      ('2099-2100'::text, true),
      ('2100-2101'::text, true),
      (' 2050-2051 '::text, true),
      ('2090-2091'::text, true),
      (null::text, false),
      (''::text, false),
      ('   '::text, false),
      ('1999-2000'::text, false),
      ('2101-2102'::text, false),
      ('2026-2028'::text, false),
      ('2026/2027'::text, false),
      ('abcd-efgh'::text, false)
    ) cases(name, expected_success)
  loop
    v_case := v_case + 1;
    v_id := null;
    v_ok := true;
    v_state := null;
    v_message := null;
    v_returned_name := null;
    v_returned_status := null;

    update public.seasons
    set status = 'archived'
    where id in (
      'b6200000-0000-0000-0000-000000000001',
      'b6200000-0000-0000-0000-000000000002',
      'b6200000-0000-0000-0000-000000000003'
    );
    update public.seasons
    set status = 'open'
    where id = 'b6200000-0000-0000-0000-000000000001';

    begin
      v_id := public.open_or_create_season(v_name);
    exception when others then
      v_ok := false;
      v_state := sqlstate;
      v_message := sqlerrm;
    end;

    if v_id is not null then
      select name, status
      into v_returned_name, v_returned_status
      from public.seasons where id = v_id;
    end if;
    select count(*)::integer into v_open_count
    from public.seasons where status = 'open';

    v_mismatch := v_ok is distinct from v_expected
      or (
        v_expected and (
          v_returned_name is distinct from btrim(v_name)
          or v_returned_status is distinct from 'open'
          or v_open_count is distinct from 1
        )
      );

    insert into pg_temp.season_name_state_space values (
      v_case, v_name, v_expected, v_ok,
      v_returned_name, v_returned_status, v_open_count,
      v_state, v_message, v_mismatch
    );

    if v_id is not null
       and v_id <> 'b6200000-0000-0000-0000-000000000001'::uuid then
      delete from public.seasons where id = v_id;
    end if;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE season_name case=%s name=%s expected=%s observed=%s returned=%s status=%s open=%s sqlstate=%s message=%s',
  case_number, coalesce(quote_nullable(proposed_name), 'NULL'),
  expected_success, observed_success, coalesce(returned_name, '-'),
  coalesce(returned_status, '-'), open_count,
  coalesce(sqlstate, '-'), coalesce(message, '-')
))
from pg_temp.season_name_state_space order by case_number;

select is((select count(*) from pg_temp.season_name_state_space), 13::bigint,
  '13 formats et frontières de nom sont exécutés');
select is((select count(*) from pg_temp.season_name_state_space where expected_success), 5::bigint,
  'cinq noms de saison sont valides');
select is((select count(*) from pg_temp.season_name_state_space where mismatch), 0::bigint,
  'format, bornes, réouverture et unicité sont respectés');

create temporary table pg_temp.season_status_state_space(
  current_status text not null,
  proposed_status text,
  expected_success boolean not null,
  observed_success boolean not null,
  expected_target text not null,
  observed_target text not null,
  expected_other text not null,
  observed_other text not null,
  expected_open_count integer not null,
  observed_open_count integer not null,
  sqlstate text,
  message text,
  mismatch boolean not null
) on commit drop;
grant select, insert, update, delete
on pg_temp.season_status_state_space to authenticated;

do $state_space$
declare
  v_current text;
  v_target text;
  v_expected boolean;
  v_ok boolean;
  v_state text;
  v_message text;
  v_expected_target text;
  v_expected_other text;
  v_expected_open integer;
  v_observed_target text;
  v_observed_other text;
  v_observed_open integer;
  v_mismatch boolean;
begin
  foreach v_current in array array['open', 'terminee', 'archived'] loop
    foreach v_target in array array['open', 'terminee', 'archived', 'invalid', null] loop
      update public.seasons set status = 'archived'
      where id in (
        'b6200000-0000-0000-0000-000000000001',
        'b6200000-0000-0000-0000-000000000002',
        'b6200000-0000-0000-0000-000000000003'
      );
      if v_current = 'open' then
        update public.seasons set status = 'open'
        where id = 'b6200000-0000-0000-0000-000000000001';
      else
        update public.seasons set status = 'open'
        where id = 'b6200000-0000-0000-0000-000000000002';
        update public.seasons set status = v_current
        where id = 'b6200000-0000-0000-0000-000000000001';
      end if;

      v_expected := coalesce(
        v_target = any(array['open', 'terminee', 'archived']::text[]),
        false
      );
      v_ok := true;
      v_state := null;
      v_message := null;
      begin
        perform public.set_season_status(
          'b6200000-0000-0000-0000-000000000001'::uuid,
          v_target
        );
      exception when others then
        v_ok := false;
        v_state := sqlstate;
        v_message := sqlerrm;
      end;

      v_expected_target := case when v_expected then v_target else v_current end;
      v_expected_other := case
        when v_expected and v_target = 'open' then 'archived'
        when v_current = 'open' then 'archived'
        else 'open'
      end;
      v_expected_open :=
        (case when v_expected_target = 'open' then 1 else 0 end)
        + (case when v_expected_other = 'open' then 1 else 0 end);

      select status into v_observed_target from public.seasons
      where id = 'b6200000-0000-0000-0000-000000000001';
      select status into v_observed_other from public.seasons
      where id = 'b6200000-0000-0000-0000-000000000002';
      select count(*)::integer into v_observed_open from public.seasons
      where status = 'open';

      v_mismatch := v_ok is distinct from v_expected
        or v_observed_target is distinct from v_expected_target
        or v_observed_other is distinct from v_expected_other
        or v_observed_open is distinct from v_expected_open;

      insert into pg_temp.season_status_state_space values (
        v_current, v_target, v_expected, v_ok,
        v_expected_target, v_observed_target,
        v_expected_other, v_observed_other,
        v_expected_open, v_observed_open,
        v_state, v_message, v_mismatch
      );
    end loop;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE season_status current=%s proposed=%s expected=%s observed=%s target=%s/%s other=%s/%s open=%s/%s sqlstate=%s message=%s',
  current_status, coalesce(proposed_status, 'NULL'),
  expected_success, observed_success,
  expected_target, observed_target, expected_other, observed_other,
  expected_open_count, observed_open_count,
  coalesce(sqlstate, '-'), coalesce(message, '-')
))
from pg_temp.season_status_state_space
order by current_status, proposed_status nulls last;

select is((select count(*) from pg_temp.season_status_state_space), 15::bigint,
  '15 transitions administratives de statut sont exécutées');
select is((select count(*) from pg_temp.season_status_state_space where mismatch), 0::bigint,
  'les transitions conservent au plus une saison ouverte');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"b6100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.open_or_create_season('2070-2071')$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas ouvrir une saison'
);
select throws_ok(
  $$select public.set_season_status(
    'b6200000-0000-0000-0000-000000000001'::uuid, 'open'
  )$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas modifier le statut d’une saison'
);
reset role;
select * from finish();
rollback;
