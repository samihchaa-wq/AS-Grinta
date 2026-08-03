begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  to_regprocedure('public.save_match_prediction(uuid,integer,integer)') is not null,
  'le pronostic sans bonus x2 expose la nouvelle RPC'
);

select ok(
  to_regprocedure('public.save_match_prediction(uuid,integer,integer,boolean)') is not null,
  'l’ancienne signature reste disponible temporairement pour compatibilité'
);

select ok(
  to_regprocedure('public.enforce_match_prediction_x2()') is null,
  'le garde serveur du bonus x2 a disparu'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'match_predictions'
      and column_name = 'use_x2'
  ),
  'la colonne use_x2 a disparu des pronostics'
);

select ok(
  to_regclass('public.v_x2_wallet') is null,
  'le portefeuille x2 a disparu'
);

select is(
  (select bucket.public from storage.buckets bucket where bucket.id = 'profile-photos'),
  false,
  'le bucket des photos de profil est privé'
);

select ok(
  to_regclass('private.match_effectif_drafts') is null
  and to_regclass('private.match_effectif_draft_entries') is null,
  'les tables de brouillon d’effectif ont disparu'
);

select ok(
  to_regprocedure('public.admin_save_match_squad_plan(uuid,text,jsonb,text)') is null
  and to_regprocedure('public.admin_publish_match_squad_plan(uuid,text,jsonb,text)') is null,
  'les anciennes RPC de plan brouillon/publication ont disparu'
);

select ok(
  to_regprocedure('public.admin_save_match_effectif(uuid,integer,jsonb,text)') is not null
  and to_regprocedure('public.admin_save_match_composition(uuid,text,jsonb,boolean,text)') is not null,
  'les écritures immédiates d’effectif et de composition restent exposées'
);

select * from finish();
rollback;
