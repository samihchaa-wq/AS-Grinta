drop function if exists public.admin_update_match_complete(
  uuid, uuid, uuid, date, time without time zone, text, text,
  numeric, numeric, numeric, integer, text, boolean, text, text
);

drop function if exists public.update_internal_match(
  uuid, uuid, date, time without time zone, text
);
