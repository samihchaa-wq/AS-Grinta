-- All available players start as convoked. Their display order follows the
-- permanent season waitlist in reverse, while manually waitlisted players keep
-- the normal waitlist order.

do $migration$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'private.get_match_convocations(uuid)'::regprocedure
  ) into v_definition;

  v_updated := replace(
    v_definition,
    E'        waitlist.position,\n        lower(coalesce(player.first_name, guest.first_name)),',
    E'        case\n          when participant.convocation_status = ''convoked''\n            and (participant.availability_status = ''available'' or participant.guest_player_id is not null)\n            then waitlist.position\n        end desc nulls last,\n        case\n          when participant.convocation_status = ''not_convoked''\n            and participant.availability_status = ''available''\n            then waitlist.position\n        end asc nulls last,\n        lower(coalesce(player.first_name, guest.first_name)),'
  );

  if v_updated = v_definition then
    raise exception 'Unable to update private.get_match_convocations ordering';
  end if;

  execute v_updated;

  select pg_get_functiondef(
    'private.get_match_availability_board(uuid)'::regprocedure
  ) into v_definition;

  v_updated := replace(
    v_definition,
    E'        waitlist.position,\n        lower(coalesce(player.first_name, guest.first_name, '''')),',
    E'        case\n          when participant.convocation_status = ''convoked''\n            and (participant.availability_status = ''available'' or guest.id is not null)\n            then waitlist.position\n        end desc nulls last,\n        case\n          when participant.convocation_status = ''not_convoked''\n            and participant.availability_status = ''available''\n            then waitlist.position\n        end asc nulls last,\n        lower(coalesce(player.first_name, guest.first_name, '''')),'
  );

  if v_updated = v_definition then
    raise exception 'Unable to update private.get_match_availability_board ordering';
  end if;

  execute v_updated;
end;
$migration$;