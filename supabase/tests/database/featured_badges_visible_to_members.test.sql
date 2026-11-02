begin;
set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Les badges arborés dans Statistiques doivent s'afficher pour TOUS les
-- membres, pas seulement pour les admins. Régression : featured_badges()
-- appelait un calcul réservé au profil lui-même ou au staff, et échouait
-- en entier pour un simple membre dès qu'un autre joueur arborait un badge.

insert into auth.users(id, email, raw_user_meta_data)
select ('fb100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       format('arbore-%s@example.invalid', n),
       jsonb_build_object('first_name', (array['Arbore', 'Lecteur'])[n])
from generate_series(1, 2) n;

update public.profiles
set status = 'active', role = 'pronostiqueur', is_test_account = false
where id::text like 'fb100000-0000-0000-0000-%';

-- Le joueur 1 arbore un badge chiffré ; il possède aussi un autre badge
-- chiffré, non arboré, dont le chiffre ne doit pas sortir.
create temp table picked as
select
  (select id from public.badges where metric is not null order by sort_order limit 1) as shown_id,
  (select metric from public.badges where metric is not null order by sort_order limit 1) as shown_metric,
  (select id from public.badges
   where metric is not null
     and metric <> (select metric from public.badges where metric is not null order by sort_order limit 1)
   order by sort_order limit 1) as hidden_id;

set local session_replication_role = replica;
insert into public.profile_badges(profile_id, badge_id, featured)
select 'fb100000-0000-0000-0000-000000000001'::uuid, shown_id, true from picked
union all
select 'fb100000-0000-0000-0000-000000000001'::uuid, hidden_id, false from picked;
set local session_replication_role = origin;

grant select on picked to authenticated;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fb100000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select lives_ok(
  $$ select * from public.featured_badges() $$,
  'un simple membre lit les badges arborés de tout le club'
);

select ok(
  exists (
    select 1
    from public.featured_badges() fb, picked
    where fb.profile_id = 'fb100000-0000-0000-0000-000000000001'
      and fb.metric = picked.shown_metric
      and fb.display_value is not null
  ),
  'le badge arboré par un autre joueur est renvoyé avec son chiffre'
);

select throws_ok(
  $$ select * from public.profile_badge_display_metrics('fb100000-0000-0000-0000-000000000001') $$,
  '42501',
  'Forbidden',
  'le bilan complet d''un autre joueur reste réservé au staff'
);

select throws_ok(
  $$ select * from private.profile_badge_display_metrics('fb100000-0000-0000-0000-000000000001') $$,
  '42501',
  null::text,
  'l''implémentation privée du bilan n''est pas appelable par un membre'
);

select is(
  (select array_agg(metric)
   from private.featured_badge_display_values('fb100000-0000-0000-0000-000000000001')),
  (select array[shown_metric] from picked),
  'seul le chiffre des badges arborés est exposé'
);

select lives_ok(
  $$ select * from public.profile_badge_display_metrics('fb100000-0000-0000-0000-000000000002') $$,
  'un membre lit toujours son propre bilan'
);

select * from finish();
rollback;
