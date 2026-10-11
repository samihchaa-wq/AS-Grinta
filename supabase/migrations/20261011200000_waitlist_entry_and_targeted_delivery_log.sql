begin;

-- Liste d'attente annoncée dès l'entrée, et trace de livraison des
-- notifications ciblées.
--
-- 1. Entrer en liste d'attente prévient toujours le joueur.
--
--    Jusqu'ici, « Tu passes en liste d'attente » ne partait que pour un joueur
--    déjà convoqué qui perdait sa place. Un joueur qui répondait « Présent »
--    et tombait directement en liste d'attente ne recevait rien, pas plus que
--    ceux déjà en liste d'attente quand l'effectif est publié pour la
--    première fois. Être convoqué est le résultat attendu : y entrer
--    directement reste silencieux. Être en liste d'attente ne l'est pas :
--    le joueur est désormais prévenu à chaque entrée, quelle qu'en soit
--    l'origine. Le passage de la liste d'attente aux convoqués continue
--    d'envoyer « Tu es convoqué ».
--
-- 2. Les notifications ciblées laissent une trace par appareil.
--
--    Les envois à contenu préparé (kind custom) — convocation, liste
--    d'attente, composition, résultat Homme du match, badges — ne laissaient
--    aucune trace dans push_delivery_log : un refus d'Apple ou de Google
--    passait inaperçu. send-push les journalise désormais, sous le type
--    transmis par la base (log_kind) et avec le match concerné quand il y en
--    a un. Les badges n'ont pas de match : la colonne match_id accepte NULL.
--
--    Les deux livraisons (migration, fonction send-push) peuvent se faire
--    dans n'importe quel ordre : une clé inconnue est ignorée par l'ancienne
--    fonction, et un type refusé par l'ancienne contrainte fait seulement
--    échouer l'écriture du journal, jamais l'envoi.
--
-- Les corps repris sont identiques à leur définition de production
-- (20261006093000, 20261009120000), aux seules clés 'log_kind' et
-- 'match_id' près pour les envois, et au cas d'entrée en liste d'attente près
-- pour le déclencheur. create or replace conserve propriétaires, droits et
-- commentaires.

-- ---------------------------------------------------------------------------
-- Journal de livraison
-- ---------------------------------------------------------------------------

alter table public.push_delivery_log
  alter column match_id drop not null;

alter table public.push_delivery_log
  drop constraint push_delivery_log_kind_check;

-- Les anciens types (availability_j3, availability_j1) restent acceptés :
-- l'historique en contient.
alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check check (kind = any (array[
    'availability_open',
    'availability_j3',
    'availability_j1',
    'availability_manual',
    'motm_open',
    'prediction_j5',
    'match_cancelled',
    'match_rescheduled_date',
    'match_rescheduled_time',
    'convocation_promoted',
    'convocation_demoted',
    'composition_published',
    'motm_result_general',
    'motm_result_winner',
    'badge_unlocked',
    'admin_pending_signup',
    'test',
    'custom',
    'live_kickoff',
    'live_goal_us',
    'live_goal_them',
    'live_full_time'
  ]));

-- ---------------------------------------------------------------------------
-- Convocation
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_convocation_push(
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
  v_title text := 'Tu es convoqué';
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
      'Tu es convoqué pour le match entre nous du %s.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'Tu es convoqué pour le match du %s contre %s.',
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
      'log_kind', 'convocation_promoted',
      'match_id', p_match_id,
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

-- ---------------------------------------------------------------------------
-- Liste d'attente
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
      'log_kind', 'convocation_demoted',
      'match_id', p_match_id,
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

-- ---------------------------------------------------------------------------
-- Déclencheur sur les joueurs : changement de groupe et entrée en attente
-- ---------------------------------------------------------------------------
--
-- Le nom de la fonction et du déclencheur sont conservés (contrat existant).
-- Nouveau cas : un joueur disponible qui entre en liste d'attente sans avoir
-- été convoqué (réponse « Présent » après la publication, retour d'absence…).
-- L'exigence de disponibilité écarte un joueur absent qu'un administrateur
-- laisserait hors des convoqués : il n'est pas en liste d'attente.

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
  v_entered_waitlist boolean :=
    old.convocation_status = 'not_applicable'
    and new.convocation_status = 'not_convoked'
    and new.availability_status::text = 'available';
begin
  if not (v_promoted or v_demoted or v_entered_waitlist) then
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
-- Déclencheur sur la publication : la liste d'attente initiale
-- ---------------------------------------------------------------------------
--
-- Avant la première publication, les places se calculent sans rien envoyer.
-- Au moment où l'effectif devient public, chaque joueur déjà placé en liste
-- d'attente est prévenu une fois. Les convoqués ne reçoivent rien : c'est le
-- résultat attendu. Une republication (effectif déjà public) ne renvoie rien
-- ici : les changements de place y sont annoncés un par un par le
-- déclencheur sur les joueurs.

create or replace function private.notify_waitlist_on_convocation_publish()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_profile_id uuid;
begin
  if old.convocation_state is not distinct from new.convocation_state
     or new.convocation_state <> 'published' then
    return new;
  end if;

  for v_profile_id in
    select distinct player.profile_id
    from public.match_sport_participants participant
    join public.season_players player on player.id = participant.season_player_id
    join public.profiles profile on profile.id = player.profile_id
    where participant.match_id = new.match_id
      and participant.is_eligible
      and participant.convocation_status = 'not_convoked'
      and participant.availability_status::text = 'available'
      and profile.status = 'active'
  loop
    perform private.dispatch_waitlist_demotion_push(new.match_id, v_profile_id);
  end loop;

  return new;
end;
$function$;

revoke all on function private.notify_waitlist_on_convocation_publish()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_notify_waitlist_on_convocation_publish
  on public.match_sport_workflows;

create trigger trg_notify_waitlist_on_convocation_publish
after update of convocation_state on public.match_sport_workflows
for each row
execute function private.notify_waitlist_on_convocation_publish();

-- ---------------------------------------------------------------------------
-- Composition en ligne
-- ---------------------------------------------------------------------------

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
  v_title text;
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
    m.match_type,
    nullif(btrim(o.name), '') as opponent_name
  into v_match
  from public.matches m
  left join public.opponents o on o.id = m.opponent_id
  where m.id = p_match_id;

  if not found or v_match.kickoff_at is null then
    return false;
  end if;

  v_title := case
    when v_match.match_type = 'entre_nous'
      then 'Les compositions sont en ligne'
    else 'La composition est en ligne'
  end;

  v_body := case
    when v_match.match_type = 'entre_nous' then format(
      'Les compositions du match entre nous du %s sont prêtes.',
      to_char(v_match.kickoff_at at time zone 'Europe/Paris', 'DD/MM')
    )
    else format(
      'La composition du match du %s contre %s est en ligne.',
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
      'log_kind', 'composition_published',
      'match_id', p_match_id,
      'profile_ids', to_jsonb(p_profile_ids),
      'title', v_title,
      'message', v_body,
      'url', 'matches/' || p_match_id || '/lineup?section=composition'
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

-- ---------------------------------------------------------------------------
-- Résultat Homme du match
-- ---------------------------------------------------------------------------

create or replace function private.dispatch_motm_result_notification(
  p_kind text,
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_payload jsonb;
  v_token text;
  v_profile_ids jsonb;
  v_title text;
  v_message text;
  v_request_id bigint;
begin
  if p_kind not in ('motm_result_general', 'motm_result_winner') then
    raise exception 'Unknown MOTM result notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management')
     or private.is_feature_enabled('notifications_paused') then
    return false;
  end if;

  v_payload := private.match_motm_result_notification_payloads(p_match_id);
  if p_kind = 'motm_result_general' then
    v_profile_ids := coalesce(v_payload -> 'general_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'general_title';
    v_message := v_payload ->> 'general_message';
  else
    v_profile_ids := coalesce(v_payload -> 'winner_profile_ids', '[]'::jsonb);
    v_title := v_payload ->> 'winner_title';
    v_message := v_payload ->> 'winner_message';
  end if;

  if jsonb_array_length(v_profile_ids) = 0 then
    return true;
  end if;

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
      'log_kind', p_kind,
      'match_id', p_match_id,
      'profile_ids', v_profile_ids,
      'title', v_title,
      'message', v_message,
      'url', 'matches/' || p_match_id
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-token', v_token
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception
  when others then
    return false;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Badges débloqués
-- ---------------------------------------------------------------------------

create or replace function private.process_badge_unlock_notifications(
  p_now timestamp with time zone default now()
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_sent integer := 0;
  v_row record;
  v_payload jsonb;
begin
  -- Deux exécutions simultanées ne doivent pas annoncer deux fois.
  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended('process_badge_unlock_notifications', 0)
  ) then
    return 0;
  end if;

  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'push_internal_token';

  if v_token is null then
    -- Sans canal push, on évite simplement que la file grossisse sans fin.
    delete from private.badge_unlock_push_queue queue
    where queue.queued_at < p_now - interval '1 day';
    return 0;
  end if;

  for v_row in
    with ready as (
      select queue.profile_id
      from private.badge_unlock_push_queue queue
      group by queue.profile_id
      having max(queue.queued_at) <= p_now - interval '45 seconds'
    ),
    taken as (
      delete from private.badge_unlock_push_queue queue
      using ready
      where queue.profile_id = ready.profile_id
      returning queue.profile_id, queue.badge_id, queue.queued_at
    )
    select
      taken.profile_id,
      array_agg(badge.name order by taken.queued_at, badge.name) as names
    from taken
    join public.badges badge on badge.id = taken.badge_id
    join public.profile_badges owned
      on owned.profile_id = taken.profile_id
     and owned.badge_id = taken.badge_id
    join public.profiles profile on profile.id = taken.profile_id
    where profile.status = 'active'
      and profile.notify_badges
    group by taken.profile_id
  loop
    v_payload := private.badge_unlock_push_message(v_row.names);
    if v_payload is null then
      continue;
    end if;

    perform net.http_post(
      url := 'https://ovzijmqrnsgcmryinkfa.supabase.co/functions/v1/send-push',
      body := jsonb_build_object(
        'kind', 'custom',
        'log_kind', 'badge_unlocked',
        'profile_ids', jsonb_build_array(v_row.profile_id),
        'title', v_payload ->> 'title',
        'message', v_payload ->> 'message',
        'url', 'armoire'
      ),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-token', v_token
      ),
      timeout_milliseconds := 10000
    );
    v_sent := v_sent + 1;
  end loop;

  return v_sent;
end;
$function$;

commit;
