-- « La composition est en ligne » : prévenir les convoqués, une seule fois
--
-- L'application savait annoncer un nouveau match, l'ouverture des
-- disponibilités, une convocation, un report ou une annulation — mais rien
-- lorsque la composition était mise en ligne. Les joueurs devaient penser à
-- aller voir.
--
-- Ils reçoivent désormais « La composition est en ligne » à la première mise en
-- ligne de la feuille, et à celle-là seulement : les retouches suivantes, elles,
-- ne renotifient personne. C'est vrai des matchs de championnat, des matchs
-- amicaux et des matchs entre nous, dont la feuille est en ligne dès son
-- enregistrement.
--
-- Sont prévenus les joueurs convoqués qui ont gardé ce type de notification
-- activé. Le nouveau réglage « Composition » est actif par défaut, comme les
-- autres, et se coupe depuis l'écran Notifications.
--
-- L'unicité ne repose pas sur la bonne volonté des appelants : elle vient de la
-- clé primaire de push_notification_log, qui n'accepte qu'une ligne par match et
-- par type. Deux enregistrements simultanés ne peuvent donc pas envoyer deux
-- fois le message.

-- Nouveau réglage personnel, actif par défaut.
alter table public.profiles
  add column if not exists notify_composition boolean not null default true;

comment on column public.profiles.notify_composition is
  'Prévenir ce joueur lorsque la composition d''un match est mise en ligne.';

-- Le journal anti-doublon doit accepter le nouveau type.
alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;

alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (
    kind = any (array[
      'motm_open'::text,
      'motm_result_general'::text,
      'motm_result_winner'::text,
      'prediction_j5'::text,
      'match_cancelled'::text,
      'match_rescheduled_date'::text,
      'match_rescheduled_time'::text,
      'composition_published'::text
    ])
  ) not valid;

-- Envoi proprement dit, calqué sur celui de la convocation : un message libre,
-- déjà rédigé ici, adressé aux profils retenus par l'appelant.
create or replace function private.dispatch_composition_published_push(
  p_match_id uuid,
  p_profile_ids uuid[]
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
  v_title text := 'La composition est en ligne';
  v_body text;
  v_match record;
begin
  if p_profile_ids is null
     or cardinality(p_profile_ids) = 0
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
      'La compo du match entre nous du %s est en ligne.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'La compo du match du %s contre %s est en ligne.',
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
      'profile_ids', to_jsonb(p_profile_ids),
      'title', v_title,
      'message', v_body
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

-- Décide s'il faut prévenir, et qui. Renvoie vrai seulement quand l'envoi part.
create or replace function private.notify_composition_published(p_match_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_status text;
  v_kickoff_at timestamptz;
  v_first boolean;
  v_profile_ids uuid[];
begin
  select m.status, m.kickoff_at
  into v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id;

  if not found or v_status <> 'a_venir' or v_kickoff_at is null then
    return false;
  end if;
  if now() >= v_kickoff_at then
    return false;
  end if;

  -- La clé primaire (match_id, kind) fait office de garde : la ligne n'est
  -- écrite qu'une fois, donc le message ne part qu'une fois.
  insert into public.push_notification_log(match_id, kind, sent_at)
  values (p_match_id, 'composition_published', now())
  on conflict (match_id, kind) do nothing;

  get diagnostics v_first = row_count;
  if not v_first then
    return false;
  end if;

  select array_agg(distinct player.profile_id)
  into v_profile_ids
  from public.match_sport_participants participant
  join public.season_players player
    on player.id = participant.season_player_id
  join public.profiles profile
    on profile.id = player.profile_id
  where participant.match_id = p_match_id
    and participant.is_eligible
    and participant.convocation_status = 'convoked'
    and profile.status = 'active'
    and profile.notify_composition;

  if v_profile_ids is null or cardinality(v_profile_ids) = 0 then
    return false;
  end if;

  return private.dispatch_composition_published_push(p_match_id, v_profile_ids);
end;
$function$;

revoke all on function private.dispatch_composition_published_push(uuid, uuid[])
  from public, anon;
revoke all on function private.notify_composition_published(uuid)
  from public, anon;
grant execute on function private.dispatch_composition_published_push(uuid, uuid[])
  to service_role;
grant execute on function private.notify_composition_published(uuid)
  to service_role;

-- Composition d'un match classique : la publication initiale prévient.
CREATE OR REPLACE FUNCTION "private"."publish_match_composition"("p_match_id" "uuid", "p_allow_squad_size_exception" boolean DEFAULT false, "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_actor uuid := (select auth.uid());
  v_reason text := nullif(btrim(p_reason), '');
  v_match_status text;
  v_squad_limit integer;
  v_convocation_state public.sport_convocation_state;
  v_current_version integer;
  v_has_unpublished_changes boolean;
  v_field_count integer;
  v_bench_count integer;
  v_available_count integer;
  v_selected_count integer;
  v_exception_used boolean;
  v_publication_kind text;
  v_snapshot jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select match.status, workflow.squad_size_limit,
    workflow.convocation_state, composition.version,
    composition.has_unpublished_changes
  into v_match_status, v_squad_limit,
    v_convocation_state, v_current_version, v_has_unpublished_changes
  from public.matches match
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  join public.match_compositions composition on composition.match_id = match.id
  where match.id = p_match_id
  for update of match, workflow, composition;

  if not found then
    raise exception 'Composition not found' using errcode = 'P0002';
  end if;
  if v_match_status not in ('a_venir', 'termine', 'archive') then
    raise exception 'Composition cannot be published for this match state'
      using errcode = '22023';
  end if;
  if v_match_status = 'a_venir' and v_convocation_state <> 'published' then
    raise exception 'Convocations must be available before the composition'
      using errcode = '22023';
  end if;

  if v_current_version > 0 and not coalesce(v_has_unpublished_changes, false) then
    return private.composition_snapshot(p_match_id);
  end if;

  select
    count(*) filter (where zone = 'field'),
    count(*) filter (where zone = 'bench'),
    count(*) filter (where zone = 'available')
  into v_field_count, v_bench_count, v_available_count
  from public.match_composition_entries
  where match_id = p_match_id;

  v_selected_count := v_field_count + v_bench_count;
  if v_field_count > 11 then
    raise exception 'A composition cannot contain more than 11 starters'
      using errcode = '22023';
  end if;
  if v_available_count > 0 then
    raise exception 'Every selected player must be placed on the field or bench before publication'
      using errcode = '22023';
  end if;
  if v_selected_count > v_squad_limit
     and not coalesce(p_allow_squad_size_exception, false) then
    raise exception 'Selected squad exceeds the configured match limit'
      using errcode = '22023';
  end if;

  v_exception_used := v_selected_count > v_squad_limit;
  v_publication_kind := case
    when v_match_status in ('termine', 'archive') then 'postmatch'
    when v_current_version = 0 then 'initial'
    else 'update'
  end;

  update public.match_compositions composition
  set status = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      version = v_current_version + 1,
      has_unpublished_changes = false,
      squad_size_exception_approved = v_exception_used,
      published_at = now(),
      published_by = v_actor,
      last_modified_at = now(),
      last_modified_by = v_actor
  where composition.match_id = p_match_id;

  update public.match_sport_workflows workflow
  set composition_state = case
        when v_current_version = 0
          then 'published'::public.sport_composition_state
        else 'updated'::public.sport_composition_state
      end,
      composition_version = v_current_version + 1,
      updated_by = v_actor,
      updated_at = now()
  where workflow.match_id = p_match_id;

  v_snapshot := private.composition_snapshot(p_match_id)
    || jsonb_build_object(
      'published_at', now(),
      'publication_kind', v_publication_kind
    );

  insert into public.match_composition_publications(
    match_id, version, formation_code, snapshot, publication_kind, published_by
  ) values (
    p_match_id,
    v_current_version + 1,
    (select formation_code from public.match_compositions where match_id = p_match_id),
    v_snapshot,
    v_publication_kind,
    v_actor
  );

  -- Première mise en ligne d'une feuille : les convoqués sont prévenus une
  -- fois, et une seule. Les mises à jour suivantes ne renotifient personne.
  if v_publication_kind = 'initial' and v_match_status = 'a_venir' then
    perform private.notify_composition_published(p_match_id);
  end if;

  insert into private.sport_admin_audit_log(
    match_id, action, actor_profile_id, reason, metadata
  ) values (
    p_match_id,
    case when v_match_status in ('termine', 'archive')
      then 'publish_postmatch_composition'
      else 'update_composition'
    end,
    v_actor,
    v_reason,
    jsonb_build_object(
      'version', v_current_version + 1,
      'publication_kind', v_publication_kind,
      'field_count', v_field_count,
      'bench_count', v_bench_count,
      'match_status', v_match_status
    )
  );

  return v_snapshot;
end;
$$;

-- Match entre nous : la feuille est en ligne dès son enregistrement.
create or replace function public.admin_save_internal_composition_v2(
  p_match_id uuid,
  p_team1_name text,
  p_team2_name text,
  p_team1_jersey text,
  p_team2_jersey text,
  p_entries jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_match_type text;
  v_status text;
  v_kickoff_at timestamptz;
  v_team1_name text := coalesce(nullif(btrim(p_team1_name), ''), 'Équipe 1');
  v_team2_name text := coalesce(nullif(btrim(p_team2_name), ''), 'Équipe 2');
  v_team1_jersey text := lower(btrim(coalesce(p_team1_jersey, '')));
  v_team2_jersey text := lower(btrim(coalesce(p_team2_jersey, '')));
  v_entry jsonb;
begin
  if not public.is_match_staff() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if char_length(v_team1_name) > 40 or char_length(v_team2_name) > 40 then
    raise exception 'Nom d''équipe trop long (40 caractères max).' using errcode = '22023';
  end if;
  if v_team1_jersey not in ('france', 'orange', 'blue')
      or v_team2_jersey not in ('france', 'orange', 'blue') then
    raise exception 'Maillot invalide.' using errcode = '22023';
  end if;
  if v_team1_jersey = v_team2_jersey then
    raise exception 'Les deux équipes doivent avoir des maillots différents.'
      using errcode = '22023';
  end if;

  select
    m.match_type,
    m.status,
    coalesce(
      m.kickoff_at,
      ((m.match_date + m.match_time) at time zone 'Europe/Paris')
    )
  into v_match_type, v_status, v_kickoff_at
  from public.matches m
  where m.id = p_match_id
  for update;

  if v_match_type is null or v_match_type <> 'entre_nous' then
    raise exception 'Match entre nous introuvable' using errcode = 'P0002';
  end if;
  if v_status <> 'a_venir' then
    raise exception 'La composition d’un match terminé ou annulé est verrouillée.'
      using errcode = '22023';
  end if;
  if v_kickoff_at is null then
    raise exception 'Horaire du match introuvable : composition refusée.' using errcode = '22023';
  end if;
  if now() >= private.match_prediction_closes_at(v_kickoff_at) then
    raise exception 'La composition est figée depuis l’ouverture du Live.'
      using errcode = '22023';
  end if;

  insert into public.match_internal_compositions (
    match_id,
    team1_name,
    team2_name,
    team1_jersey,
    team2_jersey,
    updated_by
  ) values (
    p_match_id,
    v_team1_name,
    v_team2_name,
    v_team1_jersey,
    v_team2_jersey,
    (select auth.uid())
  )
  on conflict (match_id) do update
  set team1_name = excluded.team1_name,
      team2_name = excluded.team2_name,
      team1_jersey = excluded.team1_jersey,
      team2_jersey = excluded.team2_jersey,
      updated_by = excluded.updated_by,
      updated_at = now();

  delete from public.match_internal_composition_entries
  where match_id = p_match_id;

  for v_entry in
    select value
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    insert into public.match_internal_composition_entries (
      match_id,
      participant_id,
      team_no,
      sort_order
    ) values (
      p_match_id,
      (v_entry ->> 'participant_id')::uuid,
      nullif(v_entry ->> 'team_no', '')::smallint,
      coalesce((v_entry ->> 'sort_order')::integer, 0)
    );
  end loop;

  -- Un match entre nous n'a pas de publication séparée : la feuille est en
  -- ligne dès qu'elle est enregistrée. On ne prévient qu'une fois des joueurs
  -- réellement répartis, pour ne pas annoncer une feuille vide.
  if exists (
    select 1
    from public.match_internal_composition_entries entry
    where entry.match_id = p_match_id
      and entry.team_no is not null
  ) then
    perform private.notify_composition_published(p_match_id);
  end if;

  return public.get_internal_composition(p_match_id);
end;
$function$;

-- Le réglage personnel s'ajoute à ceux qui existent. L'ancien appel à trois
-- arguments reste valable pendant le temps où d'anciennes pages sont encore
-- ouvertes : le quatrième est facultatif, et ne change rien s'il est absent.
drop function if exists public.update_my_notification_preferences(
  boolean, boolean, boolean
);

create or replace function public.update_my_notification_preferences(
  p_notify_prediction boolean,
  p_notify_motm_vote boolean,
  p_notify_convocation boolean,
  p_notify_composition boolean default null
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.profiles
  set notify_prediction_reminders =
        coalesce(p_notify_prediction, notify_prediction_reminders),
      notify_motm_vote = coalesce(p_notify_motm_vote, notify_motm_vote),
      notify_convocation = coalesce(p_notify_convocation, notify_convocation),
      notify_composition = coalesce(p_notify_composition, notify_composition),
      updated_at = now()
  where id = v_actor
    and status = 'active';

  if not found then
    raise exception 'Active profile not found' using errcode = '42501';
  end if;
  return true;
end;
$function$;

revoke all on function public.update_my_notification_preferences(
  boolean, boolean, boolean, boolean
) from public, anon;
grant execute on function public.update_my_notification_preferences(
  boolean, boolean, boolean, boolean
) to authenticated, service_role;

-- Aperçu depuis l'écran Notifications, pour vérifier le rendu sans attendre un
-- vrai match.
create or replace function public.send_test_push_kind(p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_token text;
  v_actor uuid := (select auth.uid());
  v_subscriptions integer;
  v_recent_attempts integer;
  v_title text;
  v_body text;
  v_kind text := btrim(coalesce(p_kind, ''));
begin
  if v_actor is null or not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  case v_kind
    when 'test' then
      v_title := 'Test AS Grinta';
      v_body := 'Si tu vois ceci, les notifications fonctionnent 🎉';
    when 'availability_open' then
      v_title := 'Disponibilité';
      v_body := 'Dispo pour le match du 12/09 contre FC Exemple à 20h30 ?';
    when 'availability_manual' then
      v_title := 'Tu n''as pas répondu 👀';
      v_body := 'Pense à indiquer si tu es dispo pour le match contre FC Exemple !';
    when 'convocation_promoted' then
      v_title := 'Tu es convoqué';
      v_body := 'Tu es convoqué pour le match du 12/09 contre FC Exemple.';
    when 'composition_published' then
      v_title := 'La composition est en ligne';
      v_body := 'La compo du match du 12/09 contre FC Exemple est en ligne.';
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
      v_body := 'Pense à voter pour l’homme du match.';
    when 'motm_result_general' then
      v_title := 'Homme du match';
      v_body := 'Joueur Test a été élu Homme du match !';
    when 'motm_result_winner' then
      v_title := 'Homme du match';
      v_body := 'Bravo, tu as été élu Homme du match !';
    when 'admin_pending_signup' then
      v_title := 'Nouveau compte en attente';
      v_body := 'Joueur Test attend ta validation.';
    else
      raise exception 'Unknown test notification kind' using errcode = '22023';
  end case;

  -- Partage le même quota que le test historique afin d'éviter le spam.
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
    return jsonb_build_object(
      'sent', false,
      'reason', 'rate_limited'
    );
  end if;

  select count(*)
  into v_subscriptions
  from public.push_subscriptions subscription
  where subscription.profile_id = v_actor;

  if v_subscriptions = 0 then
    return jsonb_build_object(
      'sent', false,
      'reason', 'no_subscription'
    );
  end if;

  if coalesce(
       (private.get_notifications_paused()
          #>> '{notifications_paused,enabled}')::boolean,
       false
     ) then
    return jsonb_build_object(
      'sent', false,
      'reason', 'notifications_paused'
    );
  end if;

  select secret.decrypted_secret into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    return jsonb_build_object(
      'sent', false,
      'reason', 'not_configured'
    );
  end if;

  insert into private.test_push_attempts (profile_id)
  values (v_actor);

  -- Le transport "custom" envoie exactement ce contenu au seul profil courant.
  -- Aucun match réel n'est lu, créé ou modifié.
  perform net.http_post(
    url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'kind', 'custom',
      'profile_ids', jsonb_build_array(v_actor),
      'title', v_title,
      'message', v_body
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
