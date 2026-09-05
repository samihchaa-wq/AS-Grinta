begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Aucune fonction privilegiee ne doit etre joignable sans compte, dans aucun
-- des deux schemas exposes.
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosecdef
      and has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  0::bigint,
  'aucune fonction SECURITY DEFINER n’est exécutable anonymement'
);

-- Le schema private est exposé au meme titre que public : authenticated y a
-- USAGE. Ne surveiller que public laissait cette moitié sans garde.
select diag(
  'fonctions SECURITY DEFINER exposées avec search_path non vide : '
  || string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private')
  and p.prosecdef
  and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  and not coalesce(p.proconfig, '{}'::text[])
    @> array['search_path=""']
having count(*) > 0;

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not coalesce(p.proconfig, '{}'::text[])
        @> array['search_path=""']
  ),
  0::bigint,
  'toute fonction SECURITY DEFINER exposée utilise un search_path vide'
);

-- Inventaire revu à la main des fonctions privilégiées joignables par un
-- compte connecté dont le corps n’appelle aucun garde nommé is_*, can_* ou
-- require_*. Chacune a été relue : soit elle ne fait que son propre garde,
-- soit elle est bornée au demandeur lui-meme, soit elle délègue à une fonction
-- interne gardée (vérifié plus bas), soit elle ne renvoie rien de personnel.
--
-- La liste est une borne haute : une nouvelle fonction sans garde fait échouer
-- ce test tant qu’elle n’a pas été relue et ajoutée ici. Elle ne dispense
-- jamais d’un garde — elle enregistre pourquoi il n’y en a pas besoin.
create temporary table reviewed_open_definers (
  fonction text primary key,
  motif text not null
) on commit drop;

insert into reviewed_open_definers (fonction, motif) values
  ('coach_adjust_match_live_score(uuid,text,integer,uuid,uuid)',
   'délègue à private.adjust_match_live_score_idempotent, qui exige coach ou admin'),
  ('coach_change_match_live_formation(uuid,text,jsonb,integer)',
   'délègue à private.save_match_live_lineup_versioned, qui exige coach ou admin'),
  ('coach_save_match_live_lineup(uuid,jsonb,jsonb,integer)',
   'délègue à private.save_match_live_lineup_versioned, qui exige coach ou admin'),
  ('complete_password_change()',
   'n’écrit que la ligne du demandeur, et seulement si son profil est actif'),
  ('get_my_profile()',
   'ne lit que la ligne du demandeur'),
  ('get_or_create_calendar_subscription_token()',
   'ne crée et ne lit que le jeton du demandeur, profil actif exigé'),
  ('is_moderator()',
   'garde elle-meme : lit le role du demandeur et ne renvoie qu’un booléen'),
  ('log_client_incident(text,text,text,text)',
   'ignore un appelant anonyme, tronque ses entrées et se limite à 20 écritures par minute'),
  ('register_push_subscription(text,text,text,text)',
   'n’enregistre que l’abonnement du demandeur, profil actif exigé'),
  ('set_badge_featured(text,boolean)',
   'ne modifie que les badges déjà détenus par le demandeur'),
  ('update_my_app_preferences(boolean,boolean,boolean)',
   'n’écrit que la ligne du demandeur, et seulement si son profil est actif'),
  ('update_my_notification_preferences(boolean,boolean,boolean,boolean)',
   'n’écrit que la ligne du demandeur, et seulement si son profil est actif'),
  ('private.configure_match_sport_workflow(uuid,integer)',
   'délègue à private.configure_match_sport_workflow_v2, qui exige admin'),
  ('private.sync_match_sport_workflow(uuid)',
   'délègue à private.sync_match_sport_workflow_v2, qui exige admin'),
  ('private.get_public_feature_flags()',
   'ne renvoie que le drapeau sports_management, aucune donnée personnelle'),
  ('private.is_active_profile()',
   'garde elle-meme : lit le statut du demandeur et ne renvoie qu’un booléen'),
  ('private.is_admin()',
   'garde elle-meme : lit le role du demandeur et ne renvoie qu’un booléen'),
  ('private.is_feature_enabled(text)',
   'ne renvoie qu’un booléen de configuration, aucune donnée personnelle'),
  ('private.profile_badge_stars(uuid)',
   'agrégats de badges uniquement ; contrepartie interne de public.profile_badge_metrics');

create temporary view open_definers as
  select p.oid::regprocedure::text as fonction
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosecdef
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and p.prosrc !~* '(private|public)\.(is_|can_|require_)[a-z0-9_]*\s*\(';

select diag(
  'fonctions SECURITY DEFINER exposées sans garde et non relues : '
  || string_agg(fonction, ', ' order by fonction)
)
from open_definers
where fonction not in (select fonction from reviewed_open_definers)
having count(*) > 0;

select is(
  (
    select count(*)
    from open_definers
    where fonction not in (select fonction from reviewed_open_definers)
  ),
  0::bigint,
  'toute fonction privilégiée exposée sans garde interne figure dans l’inventaire relu'
);

-- Une entrée qui ne désigne plus rien signale un renommage : l’inventaire
-- doit suivre le code, sinon il finit par autoriser une fonction disparue.
select diag(
  'entrées de l’inventaire qui ne désignent plus aucune fonction exposée : '
  || string_agg(fonction, ', ' order by fonction)
)
from reviewed_open_definers
where fonction not in (
  select p.oid::regprocedure::text
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosecdef
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
)
having count(*) > 0;

select is(
  (
    select count(*)
    from reviewed_open_definers
    where fonction not in (
      select p.oid::regprocedure::text
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private')
        and p.prosecdef
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    )
  ),
  0::bigint,
  'l’inventaire relu ne contient aucune entrée périmée'
);

-- Les motifs « délègue à » ci-dessus ne valent que si la fonction interne
-- porte bien le garde et reste, elle, hors de portée d’un compte connecté.
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in (
        'adjust_match_live_score_idempotent',
        'save_match_live_lineup_versioned',
        'configure_match_sport_workflow_v2',
        'sync_match_sport_workflow_v2'
      )
      and (
        has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or p.prosrc !~* '(private|public)\.(is_|can_|require_)[a-z0-9_]*\s*\('
      )
  ),
  0::bigint,
  'les fonctions internes recevant une délégation sont gardées et non exposées'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.profile_badge_metrics(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.profile_badge_metrics(uuid)',
    'EXECUTE'
  ),
  'l’exception de lecture des métriques de badge est authentifiée uniquement'
);

select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral unnest(p.proargnames)
      with ordinality as argument(argument_name, position)
    where n.nspname = 'public'
      and p.proname = 'profile_badge_metrics'
      and argument.position > p.pronargs
      and coalesce(argument.argument_name, '') ~*
        '(email|username|password|token|endpoint|first_name|last_name|photo_url)'
  ),
  0::bigint,
  'profile_badge_metrics ne renvoie aucune donnée d’identité ou d’authentification'
);

select * from finish();
rollback;
