-- Prévient les admins actifs par push dès qu'un nouveau compte s'inscrit et
-- attend une validation, pour qu'ils n'aient pas à vérifier manuellement.
create or replace function private.notify_admins_of_pending_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_admin_ids uuid[];
  v_display_name text;
begin
  -- Une notification ratée ne doit jamais faire échouer une inscription
  -- réelle : toute erreur ici est avalée silencieusement.
  begin
    select array_agg(p.id)
    into v_admin_ids
    from public.profiles p
    where p.role = 'admin' and p.status = 'active';

    if v_admin_ids is null or array_length(v_admin_ids, 1) = 0 then
      return new;
    end if;

    select decrypted_secret into v_token
    from vault.decrypted_secrets
    where name = 'push_internal_token';

    if v_token is null then
      return new;
    end if;

    v_display_name := nullif(btrim(concat_ws(' ', new.first_name, new.last_name)), '');

    perform net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'admin_pending_signup',
        'profile_ids', to_jsonb(v_admin_ids),
        'display_name', coalesce(v_display_name, 'Un joueur')
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    raise warning 'notify_admins_of_pending_signup failed: %', sqlerrm;
  end;

  return new;
end;
$function$;

drop trigger if exists on_profile_pending_signup on public.profiles;
create trigger on_profile_pending_signup
after insert on public.profiles
for each row
when (new.status = 'pending')
execute function private.notify_admins_of_pending_signup();

revoke execute on function private.notify_admins_of_pending_signup() from public, anon, authenticated;

comment on function private.notify_admins_of_pending_signup() is
  'Push notification to every active admin when a new account registers and needs validation.';
