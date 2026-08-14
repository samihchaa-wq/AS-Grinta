-- Non-régression : un badge auto déjà présent ne doit jamais être retiré par
-- recalculate_profile_badges(), même si le profil est actuellement sous le
-- seuil correspondant.

begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

insert into auth.users (id, email, raw_user_meta_data)
values (
  '50000000-0000-0000-0000-000000000001',
  'badge-permanent@example.invalid',
  '{"first_name":"Badge","last_name":"Permanent"}'::jsonb
);

update public.profiles
set role = 'pronostiqueur', status = 'active', updated_at = now()
where id = '50000000-0000-0000-0000-000000000001';

-- Simule un badge qui a été gagné dans le passé alors que les métriques du
-- profil neuf sont maintenant à zéro. On choisit un palier automatique réel du
-- catalogue afin de tester exactement le comportement de production.
insert into public.profile_badges (profile_id, badge_id, source)
select
  '50000000-0000-0000-0000-000000000001'::uuid,
  b.id,
  'auto'
from public.badges b
where b.auto
  and b.kind = 'tier'
  and b.metric is not null
  and b.threshold > 0
order by b.threshold desc, b.id
limit 1;

select is(
  (
    select count(*)
    from public.profile_badges
    where profile_id = '50000000-0000-0000-0000-000000000001'
      and source = 'auto'
  ),
  1::bigint,
  'le badge auto de référence est présent avant recalcul'
);

select lives_ok(
  $$select public.recalculate_profile_badges(
      '50000000-0000-0000-0000-000000000001'::uuid
    )$$,
  'le recalcul des badges s’exécute'
);

select is(
  (
    select count(*)
    from public.profile_badges
    where profile_id = '50000000-0000-0000-0000-000000000001'
      and source = 'auto'
  ),
  1::bigint,
  'un badge déjà gagné reste acquis même si le seuil courant n’est plus atteint'
);

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'recalculate_profile_badges'
      and p.oid::regprocedure::text = 'recalculate_profile_badges(uuid)'
  ),
  'recalculate_profile_badges reste SECURITY DEFINER'
);

select * from finish();
rollback;
