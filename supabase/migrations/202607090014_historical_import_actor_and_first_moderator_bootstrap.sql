create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned_role text;
begin
  perform pg_advisory_xact_lock(927451);
  assigned_role := case
    when new.email = 'historique@as-grinta.invalid' then 'pronostiqueur'
    when not exists (
      select 1 from public.profiles
      where email <> 'historique@as-grinta.invalid'
        and status = 'active'
        and role = 'moderateur'
    ) then 'moderateur'
    else 'pronostiqueur'
  end;

  insert into public.profiles(
    id,email,first_name,last_name,role,is_goalkeeper,status
  ) values (
    new.id,
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    assigned_role,
    false,
    case
      when new.email='historique@as-grinta.invalid' then 'archived'
      else 'active'
    end
  )
  on conflict(id) do update
  set email=excluded.email,
      first_name=case
        when public.profiles.first_name='' then excluded.first_name
        else public.profiles.first_name
      end,
      last_name=case
        when public.profiles.last_name='' then excluded.last_name
        else public.profiles.last_name
      end,
      updated_at=now();
  return new;
end;
$$;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,
  is_sso_user,is_anonymous
)
select
  null,
  '00000000-0000-0000-0000-000000000001'::uuid,
  'authenticated',
  'authenticated',
  'historique@as-grinta.invalid',
  crypt(gen_random_uuid()::text,gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"first_name":"Import","last_name":"Historique"}'::jsonb,
  false,
  now(),
  now(),
  false,
  false
where not exists (
  select 1 from auth.users
  where id='00000000-0000-0000-0000-000000000001'::uuid
);

update public.profiles
set role='pronostiqueur',status='archived',updated_at=now()
where id='00000000-0000-0000-0000-000000000001'::uuid;

update public.matches
set created_by='00000000-0000-0000-0000-000000000001'::uuid
where created_by is null;

alter table public.matches alter column created_by set not null;
alter table public.matches validate constraint matches_created_by_required;
