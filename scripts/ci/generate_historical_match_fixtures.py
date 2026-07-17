#!/usr/bin/env python3
"""Generate CI-only synthetic matches required by a historical data migration.

The tracked restore migration intentionally aborts unless all 156 historical
match dates already exist. Hosted production had those rows before migrations
were introduced; an empty local stack does not. This generator reads only the
committed migration, extracts its dates, and emits synthetic placeholder rows
for the disposable CI database. It never connects to a hosted project.
"""

from __future__ import annotations

import pathlib
import re
import sys

DATE_LINE = re.compile(r"^\s*(20\d{2}-\d{2}-\d{2})\|\d+\|\d+\s*$", re.MULTILINE)
EXPECTED = 156
SYNTHETIC_SEASON_NAME = "2099-2100"


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: generate_historical_match_fixtures.py SOURCE_SQL OUTPUT_SQL", file=sys.stderr)
        return 2

    source = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    dates = list(dict.fromkeys(DATE_LINE.findall(source.read_text(encoding="utf-8"))))
    if len(dates) != EXPECTED:
        raise SystemExit(f"expected {EXPECTED} unique historical dates, found {len(dates)}")

    values = ",\n".join(f"  ('{date}'::date)" for date in dates)
    sql = f"""-- Generated CI-only synthetic fixtures. Never apply to a hosted project.
-- Source dates: {source.name}; rows: {EXPECTED}.
-- The reserved synthetic season follows the later YYYY-YYYY integrity rule.

create temporary table ci_historical_match_dates(
  match_date date primary key
) on commit drop;

insert into ci_historical_match_dates(match_date) values
{values};

do $fixture$
declare
  v_season_id uuid;
  v_opponent_id uuid;
  v_actor_id uuid := '00000000-0000-0000-0000-000000000001'::uuid;
  v_columns text;
  v_values text;
  v_unknown_required text;
begin
  insert into public.seasons(name)
  values ('{SYNTHETIC_SEASON_NAME}')
  on conflict(name) do update set name = excluded.name
  returning id into v_season_id;

  insert into public.opponents(name)
  values ('CI Synthetic Historical Opponent')
  on conflict(name) do update set name = excluded.name
  returning id into v_opponent_id;

  with mapped(column_name, expression_sql) as (values
    ('id', 'gen_random_uuid()'),
    ('season_id', quote_literal(v_season_id::text) || '::uuid'),
    ('opponent_id', quote_literal(v_opponent_id::text) || '::uuid'),
    ('kickoff_at', '(d.match_date::timestamp + time ''21:00'') at time zone ''Europe/Paris'''),
    ('is_home', 'true'),
    ('planned_duration_minutes', '90'),
    ('status', quote_literal('archive')),
    ('match_date', 'd.match_date'),
    ('match_time', 'time ''21:00'''),
    ('location', quote_literal('domicile')),
    ('competition', quote_literal('CI Synthetic')),
    ('created_by', quote_literal(v_actor_id::text) || '::uuid'),
    ('created_at', 'now()'),
    ('updated_at', 'now()'),
    ('archived_at', 'now()')
  )
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position),
         string_agg(m.expression_sql, ', ' order by c.ordinal_position)
  into v_columns, v_values
  from information_schema.columns c
  join mapped m using(column_name)
  where c.table_schema = 'public' and c.table_name = 'matches';

  with mapped(column_name) as (values
    ('id'), ('season_id'), ('opponent_id'), ('kickoff_at'), ('is_home'),
    ('planned_duration_minutes'), ('status'), ('match_date'), ('match_time'),
    ('location'), ('competition'), ('created_by'), ('created_at'),
    ('updated_at'), ('archived_at')
  )
  select string_agg(c.column_name, ', ' order by c.ordinal_position)
  into v_unknown_required
  from information_schema.columns c
  left join mapped m using(column_name)
  where c.table_schema = 'public'
    and c.table_name = 'matches'
    and c.is_nullable = 'NO'
    and c.column_default is null
    and m.column_name is null;

  if v_unknown_required is not null then
    raise exception 'CI historical fixture has unmapped required match columns: %', v_unknown_required;
  end if;

  execute format(
    'insert into public.matches (%s) select %s from ci_historical_match_dates d on conflict do nothing',
    v_columns,
    v_values
  );

  if (select count(*) from public.matches m join ci_historical_match_dates d using(match_date)) <> {EXPECTED} then
    raise exception 'CI historical fixture did not create all {EXPECTED} placeholder matches';
  end if;
end;
$fixture$;
"""
    output.write_text(sql, encoding="utf-8")
    print(f"Generated {output} with {EXPECTED} synthetic historical matches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
