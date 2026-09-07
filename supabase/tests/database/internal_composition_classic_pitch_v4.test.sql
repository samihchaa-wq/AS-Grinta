begin;

select plan(18);

select ok(
  to_regprocedure(
    'public.admin_save_internal_composition_v4(uuid,text,text,text,text,text,text,jsonb,boolean)'
  ) is not null,
  'la RPC V4 existe'
);

select ok(
  to_regprocedure(
    'public.admin_save_internal_composition_v5(uuid,text,text,text,text,text,text,jsonb)'
  ) is not null,
  'la RPC V5 terrain existe'
);

select ok(
  to_regprocedure(
    'private.internal_composition_visual_is_complete(uuid)'
  ) is not null,
  'le garde de synchronisation visuelle existe'
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

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_save_internal_composition_v5(uuid,text,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  'authenticated peut appeler V5, avec contrôle admin interne'
);

select ok(
  position(
    'private.internal_composition_visual_is_complete(p_match_id)' in pg_get_functiondef(
      'private.notify_composition_published(uuid)'::regprocedure
    )
  ) > 0
  and position(
    'as_grinta.internal_visual_publish' in pg_get_functiondef(
      'private.notify_composition_published(uuid)'::regprocedure
    )
  ) > 0,
  'la notification entre nous exige le terrain complet et le chemin V5'
);

select ok(
  position(
    'Compositions faites' in pg_get_functiondef(
      'private.dispatch_composition_published_push(uuid,uuid[])'::regprocedure
    )
  ) > 0,
  'le push entre nous utilise le libellé Compositions faites'
);

select ok(
  position(
    'from public.profiles profile' in pg_get_functiondef(
      'private.notify_composition_published(uuid)'::regprocedure
    )
  ) > 0
  and position(
    'profile.notify_composition' in pg_get_functiondef(
      'private.notify_composition_published(uuid)'::regprocedure
    )
  ) > 0,
  'le push entre nous vise tous les profils actifs abonnés'
);

select ok(
  position(
    'v_can_see_assignments := public.is_match_staff()' in pg_get_functiondef(
      'public.get_internal_composition(uuid)'::regprocedure
    )
  ) > 0
  and position(
    'private.internal_composition_visual_is_complete(p_match_id)' in pg_get_functiondef(
      'public.get_internal_composition(uuid)'::regprocedure
    )
  ) > 0,
  'la lecture masque le papier aux non-admins tant que le terrain est incomplet'
);

select ok(
  private.internal_default_formation_code(1) = 'GB'
  and private.internal_default_formation_code(5) = '1-2-1'
  and private.internal_default_formation_code(9) = '3-3-2'
  and private.internal_default_formation_code(11) = '4-3-3'
  and private.internal_default_formation_code(14) = '4-3-3',
  'le serveur impose le dispositif unique de 1 à 11 joueurs'
);

select ok(
  private.internal_v4_formation_slots('4-2-3-1') is null
  and cardinality(private.internal_v4_formation_slots('3-3-2')) = 9
  and cardinality(private.internal_v4_formation_slots('4-3-3')) = 11,
  'les anciennes variantes ne sont plus acceptées par V4'
);

select * from finish();
rollback;
