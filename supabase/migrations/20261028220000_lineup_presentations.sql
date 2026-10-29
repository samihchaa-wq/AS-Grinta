begin;

-- Présentation cinématique des compositions
--
-- Quand la composition d'un match est mise en ligne, les joueurs découvrent
-- d'abord une courte vidéo (18 s) qui révèle le onze de départ, joueur par
-- joueur, puis laisse place à l'écran Compo habituel.
--
-- La vidéo ne peut pas être fabriquée par Supabase : il faut un navigateur
-- complet. Elle l'est par un workflow GitHub, déclenché ici, qui la dépose
-- dans un espace de stockage privé. La base ne fait que trois choses :
--
--   * préparer, au moment de la publication, la liste figée de ce que la vidéo
--     montrera (titulaires, positions, photos, adversaire) et son empreinte ;
--   * tenir la file des vidéos à fabriquer, une seule par contenu : la même
--     vidéo sert à tous les joueurs, et une retouche du banc, qui n'apparaît
--     pas dans la vidéo, n'en fabrique pas une nouvelle ;
--   * dire à l'application si une vidéo est prête pour le contenu actuel.
--
-- La publication n'attend jamais la vidéo : tout ce qui la concerne est isolé
-- et ne peut pas faire échouer l'enregistrement d'une composition. Rien n'est
-- préparé avant la publication, et seule la composition publiée est lue :
-- aucune feuille non publiée ne peut fuiter par la vidéo.
--
-- Le réglage « lineup_presentation » est coupé par défaut : tant qu'il l'est,
-- seuls les administrateurs voient la présentation, ce qui permet de la
-- vérifier en conditions réelles avant de l'ouvrir à tous.

insert into private.app_feature_flags(key, enabled, config)
values ('lineup_presentation', false, '{}'::jsonb)
on conflict (key) do nothing;

create table if not exists public.match_lineup_presentations (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  -- Empreinte du contenu montré : deux compositions qui donnent la même
  -- vidéo ont la même empreinte.
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{32}$'),
  composition_version integer not null check (composition_version >= 1),
  -- Ce que la vidéo montrera, figé au moment de la demande.
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  status text not null default 'pending' check (
    status in ('pending', 'rendering', 'ready', 'failed', 'superseded', 'expired')
  ),
  attempts integer not null default 0 check (attempts >= 0),
  claimed_at timestamptz,
  video_path_1080 text,
  video_path_720 text,
  duration_ms integer check (duration_ms is null or duration_ms > 0),
  bytes_1080 bigint check (bytes_1080 is null or bytes_1080 > 0),
  bytes_720 bigint check (bytes_720 is null or bytes_720 > 0),
  last_error text check (last_error is null or char_length(last_error) <= 500),
  requested_at timestamptz not null default now(),
  rendered_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (match_id, fingerprint),
  constraint match_lineup_presentations_ready_has_files check (
    status <> 'ready'
    or (
      video_path_1080 is not null
      and video_path_720 is not null
      and duration_ms is not null
      and rendered_at is not null
    )
  )
);

comment on table public.match_lineup_presentations is
  'Vidéos de présentation des compositions publiées : une par contenu, fabriquées hors de Supabase.';

create index if not exists match_lineup_presentations_queue_idx
  on public.match_lineup_presentations (status, requested_at)
  where status in ('pending', 'rendering');

create index if not exists match_lineup_presentations_match_idx
  on public.match_lineup_presentations (match_id, requested_at desc);

-- Aucun accès direct depuis l'application : tout passe par les fonctions
-- ci-dessous, qui ne rendent que ce qu'un joueur a le droit de voir.
alter table public.match_lineup_presentations enable row level security;
revoke all on table public.match_lineup_presentations from public, anon, authenticated;
grant all on table public.match_lineup_presentations to service_role;

-- Garde commune à toutes les tables métier, même fermées à l'application.
drop policy if exists "active_authenticated_profile_only" on public.match_lineup_presentations;
create policy "active_authenticated_profile_only"
  on public.match_lineup_presentations
  as restrictive
  for all
  to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

-- Stockage privé des vidéos. Seul le serveur y écrit.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types, type)
values (
  'lineup-presentations', 'lineup-presentations', false, 31457280,
  array['video/mp4'], 'STANDARD'
)
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  type = excluded.type;

-- Un fichier n'est lisible que par un membre actif, quand la présentation lui
-- est ouverte, et seulement s'il appartient à une vidéo prête.
create or replace function private.can_read_lineup_presentation_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.is_active_profile()
    and private.is_feature_enabled('sports_management')
    and (private.is_feature_enabled('lineup_presentation') or private.is_admin())
    and exists (
      select 1
      from public.match_lineup_presentations presentation
      where presentation.status = 'ready'
        and p_name in (presentation.video_path_1080, presentation.video_path_720)
    );
$function$;

revoke all on function private.can_read_lineup_presentation_object(text) from public, anon;
grant execute on function private.can_read_lineup_presentation_object(text)
  to authenticated, service_role;

drop policy if exists "lineup_presentations_active_read" on storage.objects;
create policy "lineup_presentations_active_read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'lineup-presentations'
    and private.can_read_lineup_presentation_object(name)
  );

-- Ce que la vidéo montrera pour la composition publiée d'un match, et son
-- empreinte. Lit exactement ce que l'écran Compo affiche (joueurs sortis de
-- l'effectif, photos et prénoms à jour), donc le même onze. Rend NULL quand
-- il n'y a rien à présenter : match entre nous, match commencé ou terminé,
-- composition non publiée ou sans titulaire.
--
-- Doit être appelée par un membre actif : c'est la lecture de la composition
-- publiée qui l'exige, et cette exigence est voulue.
create or replace function private.lineup_presentation_source(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_match record;
  v_composition jsonb;
  v_players jsonb;
  v_payload jsonb;
begin
  select
    match.status,
    match.match_type,
    match.kickoff_at,
    match.championship_round,
    match.competition,
    nullif(btrim(opponent.name), '') as opponent_name
  into v_match
  from public.matches match
  left join public.opponents opponent on opponent.id = match.opponent_id
  where match.id = p_match_id;

  if not found
     or v_match.match_type = 'entre_nous'
     or v_match.status <> 'a_venir'
     or v_match.kickoff_at is null
     or now() >= v_match.kickoff_at then
    return null;
  end if;

  v_composition := private.get_published_match_composition(p_match_id);
  if v_composition is null then
    return null;
  end if;

  -- Seuls les titulaires figurent dans la vidéo : le banc apparaît ensuite,
  -- sur l'écran Compo. L'ordre est fixe pour que l'empreinte le soit aussi.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', entry ->> 'participant_id',
        'display_name', coalesce(nullif(btrim(entry ->> 'display_name'), ''), 'Joueur'),
        'last_initial', nullif(btrim(entry ->> 'last_initial'), ''),
        'photo_path', nullif(btrim(entry ->> 'photo_url'), ''),
        'is_goalkeeper', coalesce((entry ->> 'is_goalkeeper')::boolean, false),
        'is_guest', coalesce((entry ->> 'is_guest')::boolean, false)
          or nullif(entry ->> 'guest_player_id', '') is not null,
        'x', (entry ->> 'x')::numeric,
        'y', (entry ->> 'y')::numeric,
        'sort_order', coalesce((entry ->> 'sort_order')::integer, 0)
      )
      order by entry ->> 'participant_id'
    ),
    '[]'::jsonb
  )
  into v_players
  from jsonb_array_elements(coalesce(v_composition -> 'entries', '[]'::jsonb)) entry
  where entry ->> 'zone' = 'field';

  if jsonb_array_length(v_players) = 0 then
    return null;
  end if;

  v_payload := jsonb_build_object(
    'team_name', 'AS Grinta',
    'formation_code', nullif(btrim(v_composition ->> 'formation_code'), ''),
    'players', v_players,
    'match', jsonb_build_object(
      'opponent_name', v_match.opponent_name,
      'kickoff_at', v_match.kickoff_at,
      'competition', v_match.competition,
      'match_type', v_match.match_type,
      'championship_round', v_match.championship_round
    )
  );

  return jsonb_build_object(
    'fingerprint', md5(v_payload::text),
    'composition_version', greatest(coalesce((v_composition ->> 'version')::integer, 1), 1),
    'payload', v_payload
  );
end;
$function$;

revoke all on function private.lineup_presentation_source(uuid) from public, anon, authenticated;
grant execute on function private.lineup_presentation_source(uuid) to service_role;

-- Prévient le workflow GitHub qu'une vidéo attend. Sans jeton enregistré dans
-- le coffre, ne fait rien : le passage régulier du workflow prendra la
-- demande plus tard. Une erreur réseau n'est jamais remontée.
create or replace function private.dispatch_lineup_presentation_render()
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  select secret.decrypted_secret
  into v_token
  from vault.decrypted_secrets secret
  where secret.name = 'github_lineup_render_token';

  if v_token is null or btrim(v_token) = '' then
    return false;
  end if;

  select net.http_post(
    url := 'https://api.github.com/repos/samihchaa-wq/AS-Grinta/actions/workflows/lineup_presentation_render.yml/dispatches',
    body := jsonb_build_object('ref', 'main'),
    headers := jsonb_build_object(
      'Accept', 'application/vnd.github+json',
      'Authorization', 'Bearer ' || btrim(v_token),
      'Content-Type', 'application/json',
      'User-Agent', 'as-grinta-supabase',
      'X-GitHub-Api-Version', '2022-11-28'
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  return v_request_id is not null;
exception when others then
  return false;
end;
$function$;

revoke all on function private.dispatch_lineup_presentation_render() from public, anon, authenticated;
grant execute on function private.dispatch_lineup_presentation_render() to service_role;

-- Demande la vidéo du contenu actuel d'un match, si elle n'existe pas déjà,
-- et rend sa ligne. Les demandes plus anciennes encore en attente pour ce
-- match sont abandonnées : seule compte la composition actuelle.
create or replace function private.request_lineup_presentation(p_match_id uuid)
returns public.match_lineup_presentations
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_source jsonb;
  v_fingerprint text;
  v_row public.match_lineup_presentations;
begin
  v_source := private.lineup_presentation_source(p_match_id);
  if v_source is null then
    return null;
  end if;
  v_fingerprint := v_source ->> 'fingerprint';

  select presentation.*
  into v_row
  from public.match_lineup_presentations presentation
  where presentation.match_id = p_match_id
    and presentation.fingerprint = v_fingerprint
  for update;

  if found then
    -- Une vidéo effacée ou abandonnée revient en file si son contenu redevient
    -- actuel. Un échec répété n'est retenté qu'au bout d'une heure, pour ne
    -- jamais tourner en boucle.
    if v_row.status in ('superseded', 'expired')
       or (v_row.status = 'failed' and v_row.updated_at < now() - interval '1 hour') then
      update public.match_lineup_presentations presentation
      set status = 'pending',
          attempts = 0,
          last_error = null,
          claimed_at = null,
          payload = v_source -> 'payload',
          composition_version = (v_source ->> 'composition_version')::integer,
          requested_at = now(),
          updated_at = now()
      where presentation.id = v_row.id
      returning presentation.* into v_row;

      update public.match_lineup_presentations presentation
      set status = 'superseded', updated_at = now()
      where presentation.match_id = p_match_id
        and presentation.id <> v_row.id
        and presentation.status in ('pending', 'failed');

      perform private.dispatch_lineup_presentation_render();
    end if;
    return v_row;
  end if;

  update public.match_lineup_presentations presentation
  set status = 'superseded', updated_at = now()
  where presentation.match_id = p_match_id
    and presentation.status in ('pending', 'failed');

  insert into public.match_lineup_presentations (
    match_id, fingerprint, composition_version, payload
  ) values (
    p_match_id,
    v_fingerprint,
    (v_source ->> 'composition_version')::integer,
    v_source -> 'payload'
  )
  on conflict (match_id, fingerprint) do nothing
  returning * into v_row;

  if v_row.id is null then
    -- Demande simultanée : l'autre a déjà écrit la ligne.
    select presentation.*
    into v_row
    from public.match_lineup_presentations presentation
    where presentation.match_id = p_match_id
      and presentation.fingerprint = v_fingerprint;
    return v_row;
  end if;

  perform private.dispatch_lineup_presentation_render();
  return v_row;
end;
$function$;

revoke all on function private.request_lineup_presentation(uuid) from public, anon, authenticated;
grant execute on function private.request_lineup_presentation(uuid) to service_role;

-- À chaque mise en ligne d'une composition, la vidéo est demandée dans la
-- foulée. Quoi qu'il arrive ici, la publication passe.
create or replace function private.enqueue_lineup_presentation_after_publication()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  begin
    perform private.request_lineup_presentation(new.match_id);
  exception when others then
    -- La vidéo sera redemandée à la première consultation de la composition.
    null;
  end;
  return null;
end;
$function$;

revoke all on function private.enqueue_lineup_presentation_after_publication()
  from public, anon, authenticated;

drop trigger if exists trg_enqueue_lineup_presentation on public.match_composition_publications;
create trigger trg_enqueue_lineup_presentation
  after insert on public.match_composition_publications
  for each row
  execute function private.enqueue_lineup_presentation_after_publication();

-- Lecture par l'application : la vidéo est-elle prête pour la composition
-- actuelle ? Redemande la vidéo si le contenu a changé depuis (un joueur
-- sorti de l'effectif, une photo remplacée), sans jamais rien révéler de plus
-- que la composition publiée.
create or replace function public.get_lineup_presentation(p_match_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_open boolean;
  v_row public.match_lineup_presentations;
begin
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;
  if not private.is_feature_enabled('sports_management') then
    return jsonb_build_object('state', 'disabled');
  end if;

  v_open := private.is_feature_enabled('lineup_presentation');
  if not v_open and not private.is_admin() then
    return jsonb_build_object('state', 'disabled');
  end if;

  begin
    v_row := private.request_lineup_presentation(p_match_id);
  exception when others then
    return jsonb_build_object('state', 'unavailable');
  end;

  if v_row.id is null then
    return jsonb_build_object('state', 'unavailable');
  end if;

  return jsonb_build_object(
    'state', case
      when v_row.status = 'ready' then 'ready'
      when v_row.status = 'failed' then 'failed'
      else 'pending'
    end,
    'fingerprint', v_row.fingerprint,
    -- Vrai tant que seuls les administrateurs voient la présentation.
    'preview', not v_open,
    'video_1080', case when v_row.status = 'ready' then v_row.video_path_1080 end,
    'video_720', case when v_row.status = 'ready' then v_row.video_path_720 end,
    'duration_ms', case when v_row.status = 'ready' then v_row.duration_ms end
  );
end;
$function$;

revoke all on function public.get_lineup_presentation(uuid) from public, anon;
grant execute on function public.get_lineup_presentation(uuid) to authenticated, service_role;

-- Fonctions du fabricant de vidéos, appelées par la fonction Edge
-- « lineup-presentations » avec la clé de service, jamais par l'application.

-- Réserve les prochaines vidéos à fabriquer.
create or replace function public.lineup_render_claim(p_limit integer default 2)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_jobs jsonb;
begin
  -- Une demande dont le match a commencé n'a plus d'intérêt.
  update public.match_lineup_presentations presentation
  set status = 'expired', updated_at = now()
  from public.matches match
  where match.id = presentation.match_id
    and presentation.status in ('pending', 'failed')
    and (match.kickoff_at is null or match.kickoff_at <= now() or match.status <> 'a_venir');

  -- Un rendu interrompu (machine perdue) est repris, trois fois au plus.
  update public.match_lineup_presentations presentation
  set status = case when presentation.attempts >= 3 then 'failed' else 'pending' end,
      last_error = coalesce(presentation.last_error, 'Rendu interrompu'),
      claimed_at = null,
      updated_at = now()
  where presentation.status = 'rendering'
    and presentation.claimed_at < now() - interval '20 minutes';

  with candidates as (
    select presentation.id
    from public.match_lineup_presentations presentation
    where presentation.status = 'pending'
      and presentation.attempts < 3
    order by presentation.requested_at
    limit greatest(1, least(coalesce(p_limit, 2), 5))
    for update skip locked
  ),
  claimed as (
    update public.match_lineup_presentations presentation
    set status = 'rendering',
        attempts = presentation.attempts + 1,
        claimed_at = now(),
        updated_at = now()
    from candidates
    where presentation.id = candidates.id
    returning presentation.id, presentation.match_id, presentation.fingerprint,
      presentation.payload, presentation.requested_at
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', claimed.id,
        'match_id', claimed.match_id,
        'fingerprint', claimed.fingerprint,
        'payload', claimed.payload
      )
      order by claimed.requested_at
    ),
    '[]'::jsonb
  )
  into v_jobs
  from claimed;

  return v_jobs;
end;
$function$;

-- Nombre de vidéos en attente : permet au workflow de s'arrêter tout de
-- suite quand il n'a rien à faire.
create or replace function public.lineup_render_pending_count()
returns integer
language sql
stable
security definer
set search_path to ''
as $function$
  select count(*)::integer
  from public.match_lineup_presentations presentation
  join public.matches match on match.id = presentation.match_id
  where presentation.attempts < 3
    and match.kickoff_at > now()
    and match.status = 'a_venir'
    and (
      presentation.status = 'pending'
      or (
        presentation.status = 'rendering'
        and presentation.claimed_at < now() - interval '20 minutes'
      )
    );
$function$;

-- Enregistre une vidéo fabriquée. Les chemins sont imposés : une vidéo ne
-- peut être rangée qu'à l'emplacement de sa propre demande.
create or replace function public.lineup_render_complete(
  p_id uuid,
  p_duration_ms integer,
  p_bytes_1080 bigint,
  p_bytes_720 bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_row public.match_lineup_presentations;
begin
  update public.match_lineup_presentations presentation
  set status = 'ready',
      video_path_1080 = presentation.match_id || '/' || presentation.fingerprint || '/1080.mp4',
      video_path_720 = presentation.match_id || '/' || presentation.fingerprint || '/720.mp4',
      duration_ms = p_duration_ms,
      bytes_1080 = p_bytes_1080,
      bytes_720 = p_bytes_720,
      rendered_at = now(),
      last_error = null,
      claimed_at = null,
      updated_at = now()
  where presentation.id = p_id
    and presentation.status = 'rendering'
  returning presentation.* into v_row;

  if v_row.id is null then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row.id,
    'video_1080', v_row.video_path_1080,
    'video_720', v_row.video_path_720
  );
end;
$function$;

-- Note un échec. La demande repart en file, sauf après trois tentatives.
create or replace function public.lineup_render_fail(p_id uuid, p_error text)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
begin
  update public.match_lineup_presentations presentation
  set status = case when presentation.attempts >= 3 then 'failed' else 'pending' end,
      last_error = left(coalesce(nullif(btrim(p_error), ''), 'Échec du rendu'), 500),
      claimed_at = null,
      updated_at = now()
  where presentation.id = p_id
    and presentation.status = 'rendering';
  return found;
end;
$function$;

-- Vidéos dont les fichiers peuvent être effacés : remplacées par une vidéo
-- plus récente du même match, ou dont le match est passé depuis deux jours.
-- Le stockage reste ainsi limité aux matchs à venir.
create or replace function public.lineup_render_purgeable(p_limit integer default 20)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', stale.id,
        'paths', jsonb_build_array(stale.video_path_1080, stale.video_path_720)
      )
    ),
    '[]'::jsonb
  )
  from (
    select presentation.id, presentation.video_path_1080, presentation.video_path_720
    from public.match_lineup_presentations presentation
    join public.matches match on match.id = presentation.match_id
    where presentation.status = 'ready'
      and (
        match.status = 'annule'
        or match.kickoff_at < now() - interval '2 days'
        or exists (
          select 1
          from public.match_lineup_presentations newer
          where newer.match_id = presentation.match_id
            and newer.status = 'ready'
            and newer.rendered_at > presentation.rendered_at
        )
      )
    order by presentation.rendered_at
    limit greatest(1, least(coalesce(p_limit, 20), 100))
  ) stale;
$function$;

create or replace function public.lineup_render_mark_purged(p_ids uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  update public.match_lineup_presentations presentation
  set status = 'expired',
      video_path_1080 = null,
      video_path_720 = null,
      updated_at = now()
  where presentation.id = any(coalesce(p_ids, array[]::uuid[]))
    and presentation.status = 'ready';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function public.lineup_render_claim(integer) from public, anon, authenticated;
revoke all on function public.lineup_render_pending_count() from public, anon, authenticated;
revoke all on function public.lineup_render_complete(uuid, integer, bigint, bigint)
  from public, anon, authenticated;
revoke all on function public.lineup_render_fail(uuid, text) from public, anon, authenticated;
revoke all on function public.lineup_render_purgeable(integer) from public, anon, authenticated;
revoke all on function public.lineup_render_mark_purged(uuid[]) from public, anon, authenticated;
grant execute on function public.lineup_render_claim(integer) to service_role;
grant execute on function public.lineup_render_pending_count() to service_role;
grant execute on function public.lineup_render_complete(uuid, integer, bigint, bigint) to service_role;
grant execute on function public.lineup_render_fail(uuid, text) to service_role;
grant execute on function public.lineup_render_purgeable(integer) to service_role;
grant execute on function public.lineup_render_mark_purged(uuid[]) to service_role;

commit;
