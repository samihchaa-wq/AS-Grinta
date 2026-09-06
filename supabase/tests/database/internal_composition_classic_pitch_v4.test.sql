begin;

select plan(10);

select ok(
  to_regprocedure(
    'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'
  ) is not null,
  'la RPC V4 existe'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='match_internal_composition_entries'
      and column_name='zone'
  ),
  'zone est persistée'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='match_internal_composition_entries'
      and column_name='x'
  ),
  'x est persisté'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='match_internal_composition_entries'
      and column_name='y'
  ),
  'y est persisté'
);

select ok(
  position(
    'p_require_visual_complete' in pg_get_functiondef(
      'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'::regprocedure
    )
  ) > 0,
  'V4 distingue papier et terrain'
);

select ok(
  position(
    '''field''' in pg_get_functiondef(
      'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'::regprocedure
    )
  ) > 0,
  'V4 gère les titulaires'
);

select ok(
  position(
    '''bench''' in pg_get_functiondef(
      'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'::regprocedure
    )
  ) > 0,
  'V4 gère les remplaçants'
);

select ok(
  position(
    'least(v_team1_count, 11)' in pg_get_functiondef(
      'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'::regprocedure
    )
  ) > 0,
  'V4 limite seulement les titulaires à onze'
);

select ok(
  position(
    '''x''' in pg_get_functiondef('public.get_internal_composition(uuid)'::regprocedure)
  ) > 0
  and position(
    '''y''' in pg_get_functiondef('public.get_internal_composition(uuid)'::regprocedure)
  ) > 0,
  'la lecture expose les coordonnées classiques'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)',
    'EXECUTE'
  ),
  'authenticated peut appeler V4'
);

select * from finish();
rollback;
