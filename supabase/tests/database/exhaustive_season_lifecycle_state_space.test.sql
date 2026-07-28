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

insert into public.seasons(id, name, status, season_predictions_locked_at)
values
  ('b6200000-0000-0000-0000-000000000001', '2090-2091', 'open', null),
  ('b6200000-0000-0000-0000-000000000002', '2089-2090', 'terminee', null),
  ('b6200000-0000-0000-0000-000000000003', '2088-2089', 'archived', null);

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

select is(
  (
    select count(*)
    from public.season_predictions
    where season_id = 'b6200000-0000-0000-0000-000000000001'
      and predictor_profile_id in (
        'b6100000-0000-0000-0000-000000000001',
        'b6100000-0000-0000-0000-000000000002',
        'b6100000-0000-0000-0000-000000000003'
      )
  ),
  6::bigint,
  'les deux joueurs sont préremplis pour les trois profils actifs'
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
  lock_cleared boolean not null,
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
  v_lock_cleared boolean;
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
    v_lock_cleared := false;

    update public.seasons
    set status = 'archived', season_predictions_locked_at = null
    where id in (
      'b6200000-0000-0000-0000-000000000001',
      'b6200000-0000-0000-0000-000000000002',
      'b6200000-0000-0000-0000-000000000003'
    );
    update public.seasons
    set status = 'open', season_predictions_locked_at = now()
    where id = 'b6200000-0000-0000-0000-000000000001';

    begin
      v_id := public.open_or_create_season(v_name);
    exception when others then
      v_ok := false;
      v_state := sqlstate;
      v_message := sqlerrm;
    end;

    if v_id is not null then
      select name, status, season_predictions_locked_at is null
      into v_returned_name, v_returned_status, v_lock_cleared
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
          or not v_lock_cleared
        )
      );

    insert into pg_temp.season_name_state_space values (
      v_case, v_name, v_expected, v_ok,
      v_returned_name, v_returned_status, v_open_count,
      v_lock_cleared, v_state, v_message, v_mismatch
    );

    if v_id is not null
       and v_id <> 'b6200000-0000-0000-0000-000000000001'::uuid then
      delete from public.seasons where id = v_id;
    end if;
  end loop;
end;
$state_space$;

select diag(format(
  'STATE_SPACE season_name case=%s name=%s expected=%s observed=%s returned=%s status=%s open=%s lock_cleared=%s sqlstate=%s message=%s',
  case_number, coalesce(quote_nullable(proposed_name), 'NULL'),
  expected_success, observed_success, coalesce(returned_name, '-'),
  coalesce(returned_status, '-'), open_count, lock_cleared,
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

create temporary table pg_temp.season_lock_state_space(
  season_status text not null,
  lock_mode text not null,
  expected_success boolean not null,
  observed_success boolean not null,
  expected_locked boolean not null,
  observed_locked boolean not null,
  sqlstate text,
  message text,
  mismatch boolean not null
) on commit drop;
grant select, insert, update, delete
on pg_temp.season_lock_state_space to authenticated;

do $state_space$
declare
  v_status text;
  v_mode text;
  v_value boolean;
  v_expected boolean;
  v_ok boolean;
  v_state text;
  v_message text;
  v_expected_locked boolean;
  v_observed_locked boolean;
begin
  foreach v_status in array array['open', 'terminee', 'archived'] loop
    foreach v_mode in array array['unlock', 'lock', 'null'] loop
      update public.seasons
      set status = 'archived', season_predictions_locked_at = null
      where id in (
        'b6200000-0000-0000-0000-000000000001',
        'b6200000-0000-0000-0000-000000000002',
        'b6200000-0000-0000-0000-000000000003'
      );
      update public.seasons set status = v_status
      where id = 'b6200000-0000-0000-0000-000000000001';

      v_value := case v_mode
        when 'unlock' then false
        when 'lock' then true
        else null
      end;
      v_expected := v_status = 'open' and v_value is not null;
      v_expected_locked := v_expected and coalesce(v_value, false);
      v_ok := true;
      v_state := null;
      v_message := null;
      begin
        perform public.set_season_predictions_lock(
          'b6200000-0000-0000-0000-000000000001'::uuid,
          v_value
        );
      exception when others then
        v_ok := false;
        v_state := sqlstate;
        v_message := sqlerrm;
      end;

      select season_predictions_locked_at is not null
      into v_observed_locked
      from public.seasons
      where id = 'b6200000-0000-0000-0000-000000000001';

      insert into pg_temp.season_lock_state_space values (
        v_status, v_mode, v_expected, v_ok,
        v_expected_locked, v_observed_locked,
        v_state, v_message,
        v_ok is distinct from v_expected
          or v_observed_locked is distinct from v_expected_locked
      );
    end loop;
  end loop;
end;
$state_space$;

select is((select count(*) from pg_temp.season_lock_state_space), 9::bigint,
  'neuf combinaisons de statut et verrou sont exécutées');
select is((select count(*) from pg_temp.season_lock_state_space where mismatch), 0::bigint,
  'seule une saison ouverte accepte un verrou booléen explicite');

reset role;

create or replace function pg_temp.prepare_prediction_case(
  p_status text,
  p_locked boolean,
  p_predictor uuid,
  p_value integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  update public.seasons
  set status = 'archived', season_predictions_locked_at = null
  where id in (
    'b6200000-0000-0000-0000-000000000001',
    'b6200000-0000-0000-0000-000000000002',
    'b6200000-0000-0000-0000-000000000003'
  );
  update public.seasons
  set status = p_status,
      season_predictions_locked_at = case when p_locked then now() else null end
  where id = 'b6200000-0000-0000-0000-000000000001';

  update public.season_predictions
  set category = 'buts', predicted_value_30 = p_value, is_filled = true
  where season_id = 'b6200000-0000-0000-0000-000000000001'
    and predictor_profile_id = p_predictor
    and season_player_id = 'b6300000-0000-0000-0000-000000000001';
end;
$function$;
grant execute on function pg_temp.prepare_prediction_case(text, boolean, uuid, integer)
to authenticated;

create temporary table pg_temp.season_prediction_write_state_space(
  season_status text not null,
  locked boolean not null,
  proposed_value integer not null,
  expected_success boolean not null,
  observed_success boolean not null,
  expected_value integer not null,
  observed_value integer not null,
  sqlstate text,
  message text,
  mismatch boolean not null
) on commit drop;
grant select, insert, update, delete
on pg_temp.season_prediction_write_state_space to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"b6100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

do $state_space$
declare
  v_status text;
  v_locked boolean;
  v_value integer;
  v_expected boolean;
  v_ok boolean;
  v_state text;
  v_message text;
  v_observed integer;
  v_expected_value integer;
begin
  foreach v_status in array array['open', 'terminee', 'archived'] loop
    foreach v_locked in array array[false, true] loop
      foreach v_value in array array[-1, 0, 99, 100] loop
        perform pg_temp.prepare_prediction_case(
          v_status, v_locked,
          'b6100000-0000-0000-0000-000000000002', 7
        );
        v_expected := v_status = 'open'
          and not v_locked
          and v_value between 0 and 99;
        v_ok := true;
        v_state := null;
        v_message := null;
        begin
          update public.season_predictions
          set predicted_value_30 = v_value, is_filled = true
          where season_id = 'b6200000-0000-0000-0000-000000000001'
            and predictor_profile_id = 'b6100000-0000-0000-0000-000000000002'
            and season_player_id = 'b6300000-0000-0000-0000-000000000001';
          if not found then v_ok := false; end if;
        exception when others then
          v_ok := false;
          v_state := sqlstate;
          v_message := sqlerrm;
        end;

        select predicted_value_30 into v_observed
        from public.season_predictions
        where season_id = 'b6200000-0000-0000-0000-000000000001'
          and predictor_profile_id = 'b6100000-0000-0000-0000-000000000002'
          and season_player_id = 'b6300000-0000-0000-0000-000000000001';
        v_expected_value := case when v_expected then v_value else 7 end;

        insert into pg_temp.season_prediction_write_state_space values (
          v_status, v_locked, v_value, v_expected, v_ok,
          v_expected_value, v_observed, v_state, v_message,
          v_ok is distinct from v_expected
            or v_observed is distinct from v_expected_value
        );
      end loop;
    end loop;
  end loop;
end;
$state_space$;

reset role;
select diag(format(
  'STATE_SPACE season_write status=%s locked=%s value=%s expected=%s observed=%s persisted=%s/%s sqlstate=%s message=%s',
  season_status, locked, proposed_value, expected_success, observed_success,
  expected_value, observed_value, coalesce(sqlstate, '-'), coalesce(message, '-')
))
from pg_temp.season_prediction_write_state_space
order by season_status, locked, proposed_value;

select is((select count(*) from pg_temp.season_prediction_write_state_space), 24::bigint,
  '24 écritures de pronostic saisonnier sont exécutées sous RLS');
select is((select count(*) from pg_temp.season_prediction_write_state_space where expected_success), 2::bigint,
  'seules deux valeurs passent sur une saison ouverte et déverrouillée');
select is((select count(*) from pg_temp.season_prediction_write_state_space where mismatch), 0::bigint,
  'statut, verrou, propriété et bornes protègent les écritures');

create temporary table pg_temp.season_prediction_validator_state_space(
  player_kind text not null,
  proposed_category text not null,
  proposed_value integer not null,
  expected_success boolean not null,
  observed_success boolean not null,
  sqlstate text,
  message text,
  mismatch boolean not null
) on commit drop;

do $state_space$
declare
  v_kind text;
  v_category text;
  v_value integer;
  v_player uuid;
  v_baseline text;
  v_expected boolean;
  v_ok boolean;
  v_state text;
  v_message text;
begin
  foreach v_kind in array array['field', 'goalkeeper'] loop
    foreach v_category in array array['buts', 'clean_sheets'] loop
      foreach v_value in array array[-1, 0, 30, 31, 99, 100] loop
        v_player := case v_kind
          when 'field' then 'b6300000-0000-0000-0000-000000000001'::uuid
          else 'b6300000-0000-0000-0000-000000000002'::uuid
        end;
        v_baseline := case v_kind when 'field' then 'buts' else 'clean_sheets' end;
        update public.season_predictions
        set category = v_baseline, predicted_value_30 = 0, is_filled = false
        where season_id = 'b6200000-0000-0000-0000-000000000001'
          and predictor_profile_id = 'b6100000-0000-0000-0000-000000000002'
          and season_player_id = v_player;

        v_expected := case v_kind
          when 'field' then v_category = 'buts' and v_value between 0 and 99
          else v_category = 'clean_sheets' and v_value between 0 and 30
        end;
        v_ok := true;
        v_state := null;
        v_message := null;
        begin
          update public.season_predictions
          set category = v_category, predicted_value_30 = v_value
          where season_id = 'b6200000-0000-0000-0000-000000000001'
            and predictor_profile_id = 'b6100000-0000-0000-0000-000000000002'
            and season_player_id = v_player;
        exception when others then
          v_ok := false;
          v_state := sqlstate;
          v_message := sqlerrm;
        end;

        insert into pg_temp.season_prediction_validator_state_space values (
          v_kind, v_category, v_value, v_expected, v_ok,
          v_state, v_message, v_ok is distinct from v_expected
        );
      end loop;
    end loop;
  end loop;
end;
$state_space$;

select is((select count(*) from pg_temp.season_prediction_validator_state_space), 24::bigint,
  '24 combinaisons joueur, catégorie et valeur sont exécutées');
select is((select count(*) from pg_temp.season_prediction_validator_state_space where expected_success), 6::bigint,
  'six combinaisons catégorie et bornes sont valides');
select is((select count(*) from pg_temp.season_prediction_validator_state_space where mismatch), 0::bigint,
  'joueurs de champ et gardiens respectent leurs catégories et plafonds');

create temporary table pg_temp.season_prediction_read_state_space(
  season_status text not null,
  locked boolean not null,
  expected_visible boolean not null,
  observed_visible boolean not null,
  mismatch boolean not null
) on commit drop;
grant select, insert, update, delete
on pg_temp.season_prediction_read_state_space to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"b6100000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;

do $state_space$
declare
  v_status text;
  v_locked boolean;
  v_expected boolean;
  v_visible boolean;
begin
  foreach v_status in array array['open', 'terminee', 'archived'] loop
    foreach v_locked in array array[false, true] loop
      perform pg_temp.prepare_prediction_case(
        v_status, v_locked,
        'b6100000-0000-0000-0000-000000000003', 12
      );
      v_expected := v_locked or v_status = 'archived';
      select exists (
        select 1 from public.season_predictions
        where season_id = 'b6200000-0000-0000-0000-000000000001'
          and predictor_profile_id = 'b6100000-0000-0000-0000-000000000003'
          and season_player_id = 'b6300000-0000-0000-0000-000000000001'
      ) into v_visible;

      insert into pg_temp.season_prediction_read_state_space values (
        v_status, v_locked, v_expected, v_visible,
        v_visible is distinct from v_expected
      );
    end loop;
  end loop;
end;
$state_space$;

select is((select count(*) from pg_temp.season_prediction_read_state_space), 6::bigint,
  'six états de visibilité adverse sont exécutés');
select is((select count(*) from pg_temp.season_prediction_read_state_space where expected_visible), 4::bigint,
  'les pronostics adverses sont visibles après verrou ou archivage');
select is((select count(*) from pg_temp.season_prediction_read_state_space where mismatch), 0::bigint,
  'les pronostics adverses restent secrets avant révélation');

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
select throws_ok(
  $$select public.set_season_predictions_lock(
    'b6200000-0000-0000-0000-000000000001'::uuid, true
  )$$,
  '42501', 'Active administrator role required',
  'un joueur ne peut pas verrouiller les pronostics de saison'
);

reset role;
select * from finish();
rollback;
