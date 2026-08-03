begin;

-- Le contrat HDM est volontairement basé sur la première finalisation valide
-- (validation des Stats ou export du récapitulatif Live), avec H+2 comme filet
-- de sécurité. Le scrutin ne peut jamais ouvrir avant le coup d'envoi.
create or replace function private.match_motm_opens_at(p_match_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  select least(
    match.kickoff_at + interval '2 hours',
    greatest(
      match.kickoff_at,
      coalesce((
        select min(version.created_at)
        from public.match_sport_finalization_versions version
        where version.match_id = p_match_id
      ), 'infinity'::timestamptz)
    )
  )
  from public.matches match
  where match.id = p_match_id;
$function$;

comment on function private.match_motm_opens_at(uuid) is
  'Ouvre le vote HDM à la première finalisation Stats/récap Live après le coup d''envoi, sinon à H+2.';

-- La fermeture reste fixe à H+24, quelle que soit l'heure réelle d'ouverture.
create or replace function private.ensure_match_motm_election(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_exists boolean;
  v_kickoff timestamptz;
  v_has_ballot boolean;
  v_opens_at timestamptz;
  v_closes_at timestamptz;
  v_version integer;
begin
  select true into v_exists
  from public.match_sport_motm_elections election
  where election.match_id = p_match_id;
  if v_exists then
    return;
  end if;

  select match.kickoff_at into v_kickoff
  from public.matches match
  where match.id = p_match_id
    and match.status <> 'annule';
  if v_kickoff is null then
    return;
  end if;

  v_has_ballot := private.match_has_eligible_motm_ballot(p_match_id);
  if not v_has_ballot then
    return;
  end if;

  v_opens_at := private.match_motm_opens_at(p_match_id);
  v_closes_at := v_kickoff + interval '24 hours';
  v_version := private.match_motm_anchor_version(p_match_id);

  insert into public.match_sport_motm_elections (
    match_id, finalization_version, state, opens_at, closes_at, closed_at,
    total_votes, max_votes, created_at, updated_at
  ) values (
    p_match_id,
    v_version,
    'draft'::public.sport_vote_state,
    v_opens_at,
    v_closes_at,
    null, 0, 0, now(), now()
  )
  on conflict (match_id) do nothing;

  update public.match_sport_workflows
  set vote_state = 'draft',
      updated_at = now()
  where match_id = p_match_id;
end;
$function$;

-- Les anciens rappels/résultats HDM et le push score final ne font plus partie
-- du produit. Les triggers sont retirés de manière idempotente avant les
-- fonctions afin de rendre la migration compatible avec les bases historiques.
drop trigger if exists trg_push_on_motm_election_closed
  on public.match_sport_motm_elections;
drop trigger if exists trg_push_on_match_result on public.matches;

drop function if exists private.push_due_motm_reminders(timestamptz);
drop function if exists public.push_on_motm_election_closed();
drop function if exists public.push_on_match_result();

-- Le transport HDM privé n'accepte plus que l'événement d'ouverture.
create or replace function private.dispatch_motm_push(
  p_kind text,
  p_match_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  if p_kind <> 'motm_open' then
    raise exception 'Unknown MOTM notification kind' using errcode = '22023';
  end if;

  if not private.is_feature_enabled('sports_management') then
    return false;
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
      'kind', p_kind,
      'match_id', p_match_id
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

-- Conserver l'historique des anciens événements sans autoriser de nouveaux
-- inserts avec des types retirés. NOT VALID évite de supprimer l'audit passé.
alter table public.push_notification_log
  drop constraint if exists push_notification_log_kind_check;
alter table public.push_notification_log
  add constraint push_notification_log_kind_check check (kind = any(array[
    'motm_open'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text
  ])) not valid;

alter table public.push_delivery_log
  drop constraint if exists push_delivery_log_kind_check;
alter table public.push_delivery_log
  add constraint push_delivery_log_kind_check check (kind = any(array[
    'availability_open'::text,
    'availability_manual'::text,
    'motm_open'::text,
    'prediction_j5'::text,
    'match_cancelled'::text,
    'match_rescheduled_date'::text,
    'match_rescheduled_time'::text,
    'convocation_promoted'::text
  ])) not valid;

-- La signature historique avec le booléen x2 est uniquement un adaptateur vers
-- la RPC actuelle : elle n'a aucune raison d'exécuter avec des privilèges élevés.
create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_use_x2 boolean
)
returns boolean
language sql
security invoker
set search_path to ''
as $function$
  select public.save_match_prediction(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse
  );
$function$;

revoke all on function public.save_match_prediction(uuid, integer, integer, boolean)
  from public, anon;
grant execute on function public.save_match_prediction(uuid, integer, integer, boolean)
  to authenticated;

-- Index de couverture des clés étrangères signalées par l'advisor Supabase.
create index if not exists match_internal_composition_entries_participant_match_idx
  on public.match_internal_composition_entries(participant_id, match_id);
create index if not exists match_live_events_created_by_idx
  on public.match_live_events(created_by);
create index if not exists match_live_events_player_in_participant_match_idx
  on public.match_live_events(player_in_participant_id, match_id);
create index if not exists match_live_events_player_out_participant_match_idx
  on public.match_live_events(player_out_participant_id, match_id);
create index if not exists match_live_events_scorer_participant_match_idx
  on public.match_live_events(scorer_participant_id, match_id);
create index if not exists match_live_sessions_updated_by_idx
  on public.match_live_sessions(updated_by);

-- Les anciennes policies FOR ALL ajoutaient une seconde policy permissive en
-- SELECT. On conserve la lecture existante et on sépare les écritures.
drop policy if exists match_internal_compositions_write
  on public.match_internal_compositions;
create policy match_internal_compositions_insert
  on public.match_internal_compositions
  for insert to authenticated
  with check (public.is_match_staff());
create policy match_internal_compositions_update
  on public.match_internal_compositions
  for update to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());
create policy match_internal_compositions_delete
  on public.match_internal_compositions
  for delete to authenticated
  using (public.is_match_staff());

drop policy if exists match_internal_composition_entries_write
  on public.match_internal_composition_entries;
create policy match_internal_composition_entries_insert
  on public.match_internal_composition_entries
  for insert to authenticated
  with check (public.is_match_staff());
create policy match_internal_composition_entries_update
  on public.match_internal_composition_entries
  for update to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());
create policy match_internal_composition_entries_delete
  on public.match_internal_composition_entries
  for delete to authenticated
  using (public.is_match_staff());

commit;
