begin;

select plan(8);

select ok(
  to_regprocedure(
    'public.admin_save_internal_composition_v3(uuid,text,text,text,text,text,text,jsonb)'
  ) is not null,
  'la RPC V3 de composition interne existe'
);

select ok(
  to_regprocedure('public.admin_reset_internal_composition(uuid)') is not null,
  'la RPC de reset dédiée existe'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_internal_compositions'
      and column_name = 'team1_formation'
  ),
  'la formation équipe 1 est persistée'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_internal_compositions'
      and column_name = 'team2_formation'
  ),
  'la formation équipe 2 est persistée'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_internal_composition_entries'
      and column_name = 'slot_label'
  ),
  'le poste visuel est persisté'
);

select ok(
  position(
    'least(v_team1_count, 11)' in
    pg_get_functiondef(
      'public.admin_save_internal_composition_v3(uuid,text,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0,
  'V3 plafonne les titulaires à 11 sans plafonner l’effectif'
);

select ok(
  position(
    'Tous les joueurs convoqués doivent apparaître exactement une fois' in
    pg_get_functiondef(
      'public.admin_save_internal_composition_v3(uuid,text,text,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0,
  'V3 exige tous les convoqués exactement une fois'
);

select ok(
  position(
    'slot_label' in
    pg_get_functiondef('public.get_internal_composition(uuid)'::regprocedure)
  ) > 0
  and position(
    'team1_formation' in
    pg_get_functiondef('public.get_internal_composition(uuid)'::regprocedure)
  ) > 0,
  'la lecture canonique expose formations et postes'
);

select * from finish();

rollback;
