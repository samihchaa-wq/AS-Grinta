-- Notifications push Web Push (PWA).
-- Les clés VAPID et le jeton interne sont stockés dans Supabase Vault sous les
-- noms push_vapid_public / push_vapid_private / push_internal_token ; ils sont
-- insérés une seule fois hors migration (jamais dans le dépôt).

-- 1. Abonnements push : chaque utilisateur gère les siens.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_subscriptions_profile
  on public.push_subscriptions (profile_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subscriptions_owner_select on public.push_subscriptions;
create policy push_subscriptions_owner_select
on public.push_subscriptions for select
to authenticated
using (profile_id = (select auth.uid()));

drop policy if exists push_subscriptions_owner_insert on public.push_subscriptions;
create policy push_subscriptions_owner_insert
on public.push_subscriptions for insert
to authenticated
with check (profile_id = (select auth.uid()));

drop policy if exists push_subscriptions_owner_update on public.push_subscriptions;
create policy push_subscriptions_owner_update
on public.push_subscriptions for update
to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

drop policy if exists push_subscriptions_owner_delete on public.push_subscriptions;
create policy push_subscriptions_owner_delete
on public.push_subscriptions for delete
to authenticated
using (profile_id = (select auth.uid()));

grant select, insert, update, delete on public.push_subscriptions to authenticated;

-- 2. Journal anti-doublon des envois.
create table if not exists public.push_notification_log (
  match_id uuid not null references public.matches(id) on delete cascade,
  kind text not null check (kind in ('new_match', 'closing_soon', 'result_validated')),
  sent_at timestamptz not null default now(),
  primary key (match_id, kind)
);

alter table public.push_notification_log enable row level security;

-- 3. Configuration lue depuis Vault (service_role uniquement).
create or replace function public.internal_push_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'vapid_public', max(decrypted_secret) filter (where name = 'push_vapid_public'),
    'vapid_private', max(decrypted_secret) filter (where name = 'push_vapid_private'),
    'token', max(decrypted_secret) filter (where name = 'push_internal_token')
  )
  from vault.decrypted_secrets
  where name in ('push_vapid_public', 'push_vapid_private', 'push_internal_token');
$$;

revoke all on function public.internal_push_config() from public, anon, authenticated;
grant execute on function public.internal_push_config() to service_role;

-- 4. Construction du message + des destinataires selon le type d'envoi.
create or replace function public.internal_push_dispatch(p_kind text, p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_match record;
  v_payload jsonb;
  v_subs jsonb;
begin
  select m.id,
         m.score_as_grinta,
         m.score_adverse,
         o.name as opponent_name,
         ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris') as kickoff
  into v_match
  from public.matches m
  join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found then
    raise exception 'Match introuvable';
  end if;

  if p_kind = 'new_match' then
    v_payload := jsonb_build_object(
      'title', 'Nouveau match à pronostiquer',
      'body', format('AS Grinta – %s le %s. Les pronostics sont ouverts !',
        v_match.opponent_name,
        to_char(v_match.kickoff at time zone 'Europe/Paris', 'DD/MM à HH24hMI')),
      'url', '.',
      'tag', 'match-' || v_match.id || '-new'
    );
    select coalesce(jsonb_agg(jsonb_build_object(
      'endpoint', ps.endpoint, 'p256dh', ps.p256dh, 'auth', ps.auth)), '[]'::jsonb)
    into v_subs
    from public.push_subscriptions ps
    join public.profiles pr on pr.id = ps.profile_id
    where pr.status = 'active' and pr.notify_prediction_reminders;

  elsif p_kind = 'closing_soon' then
    v_payload := jsonb_build_object(
      'title', 'Dernière chance de pronostiquer',
      'body', format('AS Grinta – %s : les pronostics ferment à %s.',
        v_match.opponent_name,
        to_char((v_match.kickoff - interval '5 minutes') at time zone 'Europe/Paris', 'HH24hMI')),
      'url', '.',
      'tag', 'match-' || v_match.id || '-closing'
    );
    select coalesce(jsonb_agg(jsonb_build_object(
      'endpoint', ps.endpoint, 'p256dh', ps.p256dh, 'auth', ps.auth)), '[]'::jsonb)
    into v_subs
    from public.push_subscriptions ps
    join public.profiles pr on pr.id = ps.profile_id
    where pr.status = 'active'
      and pr.notify_prediction_reminders
      and not exists (
        select 1 from public.match_predictions mp
        where mp.match_id = p_match_id
          and mp.profile_id = pr.id
          and mp.is_filled
      );

  elsif p_kind = 'result_validated' then
    v_payload := jsonb_build_object(
      'title', 'Résultat validé',
      'body', format('AS Grinta %s-%s %s. Découvre tes points et le classement !',
        coalesce(v_match.score_as_grinta::text, '?'),
        coalesce(v_match.score_adverse::text, '?'),
        v_match.opponent_name),
      'url', '.',
      'tag', 'match-' || v_match.id || '-result'
    );
    select coalesce(jsonb_agg(jsonb_build_object(
      'endpoint', ps.endpoint, 'p256dh', ps.p256dh, 'auth', ps.auth)), '[]'::jsonb)
    into v_subs
    from public.push_subscriptions ps
    join public.profiles pr on pr.id = ps.profile_id
    where pr.status = 'active' and pr.notify_match_reminders;

  else
    raise exception 'Type d''envoi inconnu: %', p_kind;
  end if;

  return jsonb_build_object('payload', v_payload, 'subscriptions', v_subs);
end;
$$;

revoke all on function public.internal_push_dispatch(text, uuid) from public, anon, authenticated;
grant execute on function public.internal_push_dispatch(text, uuid) to service_role;

-- 5. Purge des abonnements expirés (410/404 côté push service).
create or replace function public.internal_push_prune(p_endpoints text[])
returns integer
language sql
security definer
set search_path = public
as $$
  with deleted as (
    delete from public.push_subscriptions
    where endpoint = any(p_endpoints)
    returning 1
  )
  select count(*)::integer from deleted;
$$;

revoke all on function public.internal_push_prune(text[]) from public, anon, authenticated;
grant execute on function public.internal_push_prune(text[]) to service_role;

-- 6. Déclenchement asynchrone de l'Edge Function via pg_net.
create or replace function public.internal_push_notify(p_kind text, p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'push_internal_token';

  if v_token is null then
    return;
  end if;

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('kind', p_kind, 'match_id', p_match_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );
exception when others then
  -- L'envoi de notification ne doit jamais faire échouer la transaction métier.
  null;
end;
$$;

revoke all on function public.internal_push_notify(text, uuid) from public, anon, authenticated;

-- 7. Push à la création d'un match.
create or replace function public.push_on_match_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'a_venir' then
    insert into public.push_notification_log (match_id, kind)
    values (new.id, 'new_match')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('new_match', new.id);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.push_on_match_insert() from public, anon, authenticated;

drop trigger if exists trg_push_on_match_insert on public.matches;
create trigger trg_push_on_match_insert
after insert on public.matches
for each row execute function public.push_on_match_insert();

-- 8. Push à la validation du résultat.
create or replace function public.push_on_match_result()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'termine' and old.status is distinct from 'termine' then
    insert into public.push_notification_log (match_id, kind)
    values (new.id, 'result_validated')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('result_validated', new.id);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.push_on_match_result() from public, anon, authenticated;

drop trigger if exists trg_push_on_match_result on public.matches;
create trigger trg_push_on_match_result
after update on public.matches
for each row execute function public.push_on_match_result();

-- 9. Rappel ~1 h avant la fermeture des pronostics (cron toutes les 5 min).
create or replace function public.push_closing_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match record;
  v_sent integer := 0;
begin
  for v_match in
    select m.id
    from public.matches m
    where m.status = 'a_venir'
      and ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris')
          - interval '5 minutes' > now()
      and ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris')
          - interval '5 minutes' <= now() + interval '65 minutes'
  loop
    insert into public.push_notification_log (match_id, kind)
    values (v_match.id, 'closing_soon')
    on conflict do nothing;
    if found then
      perform public.internal_push_notify('closing_soon', v_match.id);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end;
$$;

revoke all on function public.push_closing_reminders() from public, anon, authenticated;

select cron.schedule(
  'push-closing-reminders',
  '*/5 * * * *',
  $$select public.push_closing_reminders();$$
);
