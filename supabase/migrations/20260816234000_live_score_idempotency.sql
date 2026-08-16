-- Rend les commandes +1/-1 du Live rejouables sans modifier deux fois le score.
--
-- Le client fournit un UUID stable pour une action logique. Si une réponse RPC
-- se perd apres le commit, le meme UUID peut etre rejoue : la commande est
-- reconnue et l'etat courant est renvoye sans reappliquer le score.

begin;

create table private.match_live_score_commands (
  actor_id uuid not null references public.profiles(id) on delete cascade,
  operation_id uuid not null,
  match_id uuid not null references public.matches(id) on delete cascade,
  team text not null check (team in ('us', 'them')),
  delta smallint not null check (delta in (-1, 1)),
  scorer_participant_id uuid,
  created_at timestamptz not null default now(),
  primary key (actor_id, operation_id)
);

alter table private.match_live_score_commands enable row level security;

revoke all on table private.match_live_score_commands
  from public, anon, authenticated;

comment on table private.match_live_score_commands is
  'Ledger prive d idempotence des commandes de score Live. Un operation_id est unique par acteur.';

create or replace function private.adjust_match_live_score_idempotent(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_inserted boolean;
  v_existing private.match_live_score_commands%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  perform private.require_sports_management_enabled();

  if not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  if p_operation_id is null then
    raise exception 'Operation id is required' using errcode = '22023';
  end if;

  insert into private.match_live_score_commands(
    actor_id,
    operation_id,
    match_id,
    team,
    delta,
    scorer_participant_id
  )
  values (
    v_actor_id,
    p_operation_id,
    p_match_id,
    p_team,
    p_delta,
    p_scorer_participant_id
  )
  on conflict (actor_id, operation_id) do nothing
  returning true into v_inserted;

  if coalesce(v_inserted, false) then
    -- L'insertion et l'ajustement vivent dans la meme transaction : si la
    -- commande echoue, le ledger est lui aussi annule et un retry pourra
    -- legitimately retenter l'operation.
    return private.adjust_match_live_score(
      p_match_id,
      p_team,
      p_delta,
      p_scorer_participant_id
    );
  end if;

  select command.*
  into v_existing
  from private.match_live_score_commands command
  where command.actor_id = v_actor_id
    and command.operation_id = p_operation_id;

  if not found then
    raise exception 'Idempotency command unavailable' using errcode = '40001';
  end if;

  if v_existing.match_id is distinct from p_match_id
     or v_existing.team is distinct from p_team
     or v_existing.delta is distinct from p_delta
     or v_existing.scorer_participant_id is distinct from p_scorer_participant_id then
    raise exception 'Operation id already used for another score command'
      using errcode = '22023';
  end if;

  return private.match_live_snapshot(p_match_id);
end;
$function$;

revoke all on function
  private.adjust_match_live_score_idempotent(uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;

comment on function
  private.adjust_match_live_score_idempotent(uuid, text, integer, uuid, uuid)
is
  'Applique une commande de score Live une seule fois par operation_id et acteur.';

create or replace function public.coach_adjust_match_live_score(
  p_match_id uuid,
  p_team text,
  p_delta integer,
  p_scorer_participant_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return private.adjust_match_live_score_idempotent(
    p_match_id,
    p_team,
    p_delta,
    p_scorer_participant_id,
    p_operation_id
  );
end;
$function$;

revoke all on function
  public.coach_adjust_match_live_score(uuid, text, integer, uuid, uuid)
  from public, anon;
grant execute on function
  public.coach_adjust_match_live_score(uuid, text, integer, uuid, uuid)
  to authenticated, service_role;

comment on function
  public.coach_adjust_match_live_score(uuid, text, integer, uuid, uuid)
is
  'Commande de score Live idempotente. Rejouer le meme operation_id avec le meme payload ne modifie pas le score deux fois.';

commit;
