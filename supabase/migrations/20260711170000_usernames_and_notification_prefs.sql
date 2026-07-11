-- Connexion par identifiant (prénom + initiale du nom, ex. samihc) : plus
-- d'emails visibles. L'identifiant est stocké dans profiles.username et sert
-- de partie locale à une adresse technique <username>@pronos.as-grinta.local.
-- password_set=false marque un compte invité en attente de première
-- connexion (le joueur choisira alors son mot de passe).
-- Trois préférences de notification distinctes : pronostic ouvert, rappel
-- 2 h avant le match si pas encore pronostiqué, match terminé.

alter table public.profiles
  add column if not exists username text unique,
  add column if not exists password_set boolean not null default true,
  add column if not exists notify_prediction_open boolean not null default true;

grant select (username) on public.profiles to authenticated;

update public.profiles
set username = 'samihc'
where id = '89f24276-dac0-4046-87a3-6c28e48fef3a' and username is null;

-- Préférences : trois interrupteurs indépendants.
drop function if exists public.update_my_app_preferences(boolean, boolean);
create function public.update_my_app_preferences(
  p_notify_prediction_open boolean,
  p_notify_prediction_reminders boolean,
  p_notify_match_reminders boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.profiles
  set notify_prediction_open =
        coalesce(p_notify_prediction_open, notify_prediction_open),
      notify_prediction_reminders =
        coalesce(p_notify_prediction_reminders, notify_prediction_reminders),
      notify_match_reminders =
        coalesce(p_notify_match_reminders, notify_match_reminders),
      updated_at = now()
  where id = auth.uid();

  return found;
end;
$$;

revoke all on function public.update_my_app_preferences(boolean, boolean, boolean) from public, anon;
grant execute on function public.update_my_app_preferences(boolean, boolean, boolean) to authenticated;

-- La liste staff expose l'identifiant et l'état de première connexion.
drop function if exists public.staff_list_profiles();
create function public.staff_list_profiles()
returns table(
  id uuid, first_name text, last_name text, surnom text, username text,
  password_set boolean, photo_url text, role text, is_goalkeeper boolean,
  status text, created_at timestamptz, updated_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.first_name, p.last_name, p.surnom, p.username,
         p.password_set, p.photo_url, p.role, p.is_goalkeeper,
         p.status, p.created_at, p.updated_at
  from public.profiles p
  where public.is_match_staff()
  order by p.first_name, p.last_name;
$$;

revoke all on function public.staff_list_profiles() from public, anon;
grant execute on function public.staff_list_profiles() to authenticated;

-- Ciblage des notifications push : pronostic ouvert → notify_prediction_open.
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
    where pr.status = 'active' and pr.notify_prediction_open;

  elsif p_kind = 'closing_soon' then
    v_payload := jsonb_build_object(
      'title', 'Plus que 2 h pour pronostiquer',
      'body', format('AS Grinta – %s : tu n''as pas encore pronostiqué. Fermeture à %s.',
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
      'body', format('AS Grinta %s-%s %s. Découvre tes points et les pronostics des autres !',
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

-- Le rappel part 2 h avant le coup d'envoi (fenêtre glissante de 5 min du cron).
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
      and now() >= ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris')
                   - interval '2 hours'
      and now() < ((m.match_date + coalesce(m.match_time, '00:00'::time)) at time zone 'Europe/Paris')
                  - interval '5 minutes'
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
