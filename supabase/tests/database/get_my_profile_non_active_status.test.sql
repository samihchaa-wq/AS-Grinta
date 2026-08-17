begin;

set local search_path = public, extensions, pg_catalog;
select plan(6);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('71000000-0000-0000-0000-000000000001', 'pending-profile-tests@example.invalid', '{"first_name":"Pending","last_name":"Profile"}'::jsonb),
  ('71000000-0000-0000-0000-000000000002', 'archived-profile-tests@example.invalid', '{"first_name":"Archived","last_name":"Profile"}'::jsonb);

update public.profiles
set status = case
      when id = '71000000-0000-0000-0000-000000000001' then 'pending'
      else 'archived'
    end,
    updated_at = now()
where id in (
  '71000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000002'
);

set local role anon;
select throws_ok(
  $$select public.get_my_profile()$$,
  '42501',
  'un appel anonyme ne peut pas lire de profil'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000001","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.get_my_profile()->>'id',
  '71000000-0000-0000-0000-000000000001',
  'un compte pending ne reçoit que son propre profil'
);
select is(
  public.get_my_profile()->>'status',
  'pending',
  'un compte pending peut lire son statut pour être routé vers l’écran d’attente'
);
select isnt(
  public.get_my_profile()->>'id',
  '71000000-0000-0000-0000-000000000002',
  'un compte pending ne peut pas obtenir le profil d’un autre utilisateur'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"71000000-0000-0000-0000-000000000002","role":"authenticated","aud":"authenticated"}',
  true
);
set local role authenticated;
select is(
  public.get_my_profile()->>'id',
  '71000000-0000-0000-0000-000000000002',
  'un compte archived ne reçoit que son propre profil'
);
select is(
  public.get_my_profile()->>'status',
  'archived',
  'un compte archived peut lire son statut pour être bloqué proprement par le client'
);
reset role;

select * from finish();
rollback;
