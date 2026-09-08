begin;

set local search_path = public, extensions, pg_catalog;
select plan(8);

select ok(
  to_regprocedure(
    'private.admin_availability_change_message(text,text,text,timestamp with time zone)'
  ) is not null,
  'le formateur de notification admin existe'
);

select ok(
  to_regprocedure('private.notify_admin_player_availability_change()') is not null,
  'la fonction de trigger de notification admin existe'
);

select is(
  private.admin_availability_change_message(
    'Alice',
    'available',
    'absent',
    '2026-09-08 12:07:00+00'::timestamptz
  ),
  'Alice est passé de présent à absent à 14h07.',
  'Présent -> Absent utilise le libellé demandé et l’heure de Paris'
);

select is(
  private.admin_availability_change_message(
    'Bruno',
    'absent',
    'available',
    '2026-09-08 19:42:00+00'::timestamptz
  ),
  'Bruno est passé de absent à présent à 21h42.',
  'Absent -> Présent utilise le libellé demandé et l’heure de Paris'
);

select is(
  private.admin_availability_change_message(
    'Alice',
    'no_response',
    'available',
    '2026-09-08 12:07:00+00'::timestamptz
  ),
  null::text,
  'la première réponse no_response -> présent ne notifie pas les admins'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.match_sport_participants'::regclass
      and trigger.tgname = 'notify_admin_player_availability_change'
      and not trigger.tgisinternal
  ),
  'le trigger est installé sur match_sport_participants'
);

select ok(
  (
    select procedure.prosecdef
    from pg_proc procedure
    where procedure.oid = to_regprocedure(
      'private.notify_admin_player_availability_change()'
    )
  ),
  'le trigger serveur est SECURITY DEFINER'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.notify_admin_player_availability_change()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.admin_availability_change_message(text,text,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'aucune fonction interne de cette notification n’est appelable directement par un client'
);

select * from finish();
rollback;
