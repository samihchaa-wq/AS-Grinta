begin;

-- Passage convoqué ↔ liste d'attente : deux notifications toujours envoyées.
--
-- * Un joueur qui passe de la liste d'attente aux convoqués reçoit déjà
--   « Tu es convoqué ». Il la recevait seulement s'il n'avait pas coupé le
--   réglage « Passage en convoqué » : elle part désormais toujours.
-- * Un joueur qui passe des convoqués à la liste d'attente reçoit maintenant
--   « Tu passes en liste d'attente », sur le même modèle.
--
-- Les deux rejoignent les notifications essentielles : l'application ne les
-- propose plus en réglage. La colonne profiles.notify_convocation et la
-- signature de update_my_notification_preferences restent en place pour les
-- versions de l'application déjà installées ; la colonne n'est simplement
-- plus lue pour ces envois.
--
-- Comme pour la convocation, rien ne part tant que les convocations du match
-- ne sont pas publiées, ni quand le coupe-circuit des notifications est
-- actif. Un joueur qui se déclare absent passe hors effectif, pas en liste
-- d'attente : il ne reçoit rien.

-- ---------------------------------------------------------------------------
-- Envoi « Tu passes en liste d'attente »
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_waitlist_demotion_push(
  p_match_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text := 'Tu passes en liste d''attente';
  v_body text;
  v_match record;
begin
  if p_profile_id is null
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  select
    m.kickoff_at,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_body := case
    when v_match.opponent_name is null then format(
      'Tu passes en liste d''attente pour le match entre nous du %s.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'Tu passes en liste d''attente pour le match du %s contre %s.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM'),
      v_match.opponent_name
    )
  end;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';
  if v_token is null then
    return false;
  end if;

  select net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(p_profile_id),
      'title', v_title,
      'message', v_body,
      'url', 'matches/' || p_match_id || '/lineup?section=effectif'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

revoke all on function private.dispatch_waitlist_demotion_push(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Déclencheur : convoqué ↔ liste d'attente, sans réglage individuel
-- ---------------------------------------------------------------------------
--
-- Le nom de la fonction et du déclencheur sont conservés (contrat existant) ;
-- seul le corps change : le filtre profile.notify_convocation disparaît et le
-- sens inverse est ajouté.

create or replace function private.notify_waitlist_promotion()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_id uuid;
  v_promoted boolean :=
    old.convocation_status = 'not_convoked'
    and new.convocation_status = 'convoked';
  v_demoted boolean :=
    old.convocation_status = 'convoked'
    and new.convocation_status = 'not_convoked';
begin
  if not (v_promoted or v_demoted) then
    return new;
  end if;

  if not exists (
    select 1 from public.match_sport_workflows workflow
    where workflow.match_id = new.match_id
      and workflow.convocation_state = 'published'
  ) then
    return new;
  end if;

  select player.profile_id
  into v_profile_id
  from public.season_players player
  join public.profiles profile on profile.id = player.profile_id
  where player.id = new.season_player_id
    and profile.status = 'active';

  if v_profile_id is null then
    return new;
  end if;

  if v_promoted then
    perform private.dispatch_convocation_push(new.match_id, v_profile_id);
  else
    perform private.dispatch_waitlist_demotion_push(new.match_id, v_profile_id);
  end if;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Notification de test : ajout de « Passage en liste d'attente »
-- ---------------------------------------------------------------------------
--
-- Corps repris à l'identique de la définition en production, au seul cas
-- 'convocation_demoted' près.

create or replace function public.send_test_push_kind(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
  v_subscriptions integer;
  v_recent_attempts integer;
  v_title text;
  v_body text;
  v_kind text := btrim(coalesce(p_kind, ''));
  v_badge_payload jsonb;
  -- Les exemples liés à un match n'ont pas de vrai match : ils ouvrent
  -- l'accueil. Les autres ouvrent le même écran que la vraie notification.
  v_url text := '.';
begin
  if v_actor is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  if v_kind = 'admin_availability_change'
     and not public.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  case v_kind
    when 'test' then
      v_title := 'Test AS Grinta';
      v_body := 'Si tu vois ceci, les notifications fonctionnent 🎉';
    when 'availability_open' then
      v_title := 'Disponibilité';
      v_body := 'Es-tu disponible pour le match du 12/09 contre FC Exemple à 20h30 ?';
    when 'availability_manual' then
      v_title := 'Tu n''as pas répondu 👀';
      v_body := 'Pense à indiquer si tu es disponible pour le match contre FC Exemple !';
    when 'convocation_promoted' then
      v_title := 'Tu es convoqué';
      v_body := 'Tu es convoqué pour le match du 12/09 contre FC Exemple.';
    when 'convocation_demoted' then
      v_title := 'Tu passes en liste d''attente';
      v_body := 'Tu passes en liste d''attente pour le match du 12/09 contre FC Exemple.';
    when 'composition_published' then
      v_title := 'La composition est en ligne';
      v_body := 'La composition du match du 12/09 contre FC Exemple est en ligne.';
    when 'prediction_j5' then
      v_title := 'Pronostic';
      v_body := 'Pense à pronostiquer pour le match du 12/09 contre FC Exemple.';
    when 'match_cancelled' then
      v_title := 'Match annulé';
      v_body := 'Le match du 12/09 contre FC Exemple à 20h30 est annulé.';
    when 'match_rescheduled_date' then
      v_title := 'Match reporté';
      v_body := 'Le match contre FC Exemple est reporté au 12/09 à 20h30. Es-tu disponible ?';
    when 'match_rescheduled_time' then
      v_title := 'Horaire du match modifié';
      v_body := 'Le match du 12/09 contre FC Exemple aura finalement lieu à 20h30.';
    when 'motm_open' then
      v_title := 'Homme du match';
      v_body := 'Pense à voter pour l’Homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
      v_url := 'admin/administration';
    when 'admin_availability_change' then
      v_title := 'Changement de disponibilité';
      v_body := 'À 20h30, Joueur Test est passé de présent à absent.';
    when 'badge_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(array['Buteur']);
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
    when 'badges_unlocked' then
      v_badge_payload := private.badge_unlock_push_message(
        array['Buteur', 'Passeur']
      );
      v_title := v_badge_payload ->> 'title';
      v_body := v_badge_payload ->> 'message';
      v_url := 'armoire';
    else
      raise exception 'Unknown test notification kind' using errcode = '22023';
  end case;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('send_test_push:' || v_actor::text, 0)
  );

  delete from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at < now() - interval '1 day';

  select count(*)::integer
  into v_recent_attempts
  from private.test_push_attempts attempt
  where attempt.profile_id = v_actor
    and attempt.attempted_at >= now() - interval '10 minutes';

  if v_recent_attempts >= 3 then
    return jsonb_build_object('sent', false, 'reason', 'rate_limited');
  end if;

  select count(*)
  into v_subscriptions
  from public.push_subscriptions subscription
  where subscription.profile_id = v_actor;

  if v_subscriptions = 0 then
    return jsonb_build_object('sent', false, 'reason', 'no_subscription');
  end if;

  if coalesce(
       (private.get_notifications_paused()
          #>> '{notifications_paused,enabled}')::boolean,
       false
     ) then
    return jsonb_build_object('sent', false, 'reason', 'notifications_paused');
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return jsonb_build_object('sent', false, 'reason', 'not_configured');
  end if;

  insert into private.test_push_attempts (profile_id)
  values (v_actor);

  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(v_actor),
      'title', v_title,
      'message', v_body,
      'url', v_url
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  );

  return jsonb_build_object(
    'sent', true,
    'subscriptions', v_subscriptions,
    'kind', v_kind
  );
end;
$function$;

commit;
