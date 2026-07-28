begin;

-- Une correction post-match ne doit pas rouvrir ni effacer le scrutin HDM.
-- Le workflow doit toutefois refléter l'état réel de l'élection après les
-- transitions temporelles exécutées par le trigger de finalisation.
create or replace function private.trg_reset_match_motm_after_finalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_opens_at timestamptz;
  v_vote_state public.sport_vote_state;
begin
  perform private.ensure_match_motm_election(new.match_id);

  v_opens_at := private.match_motm_opens_at(new.match_id);
  update public.match_sport_motm_elections election
  set opens_at = least(coalesce(election.opens_at, v_opens_at), v_opens_at),
      updated_at = now()
  where election.match_id = new.match_id
    and election.state in ('draft', 'open');

  perform private.transition_match_motm_election(new.match_id);

  select election.state
  into v_vote_state
  from public.match_sport_motm_elections election
  where election.match_id = new.match_id;

  if v_vote_state is not null then
    update public.match_sport_workflows workflow
    set vote_state = v_vote_state,
        updated_at = now()
    where workflow.match_id = new.match_id
      and workflow.vote_state is distinct from v_vote_state;
  end if;

  -- La finalisation efface préventivement les anciens MVP avant le calcul du
  -- scrutin. Lors d'une correction postérieure à sa clôture, les résultats sont
  -- volontairement conservés : on restaure donc uniquement leurs gagnants
  -- permanents dans la table statistique historique.
  if v_vote_state = 'closed' then
    delete from public.match_man_of_match
    where match_id = new.match_id;

    insert into public.match_man_of_match(match_id, season_player_id)
    select result.match_id, participant.season_player_id
    from public.match_sport_motm_results result
    join public.match_sport_participants participant
      on participant.id = result.participant_id
     and participant.match_id = result.match_id
    where result.match_id = new.match_id
      and result.is_winner
      and participant.season_player_id is not null
    on conflict do nothing;
  end if;

  return new;
end;
$function$;

-- Le snapshot historique reste immuable, mais la réponse de l'action doit
-- exposer l'état HDM réellement persisté après le trigger de finalisation.
create or replace function public.admin_finalize_match_sport_postgame(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer,
  p_participants jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_vote_state public.sport_vote_state;
begin
  v_result := private.finalize_match_sport_postgame(
    p_match_id,
    p_score_as_grinta,
    p_score_adverse,
    p_participants,
    p_reason
  );

  select workflow.vote_state
  into v_vote_state
  from public.match_sport_workflows workflow
  where workflow.match_id = p_match_id;

  return v_result || jsonb_build_object('vote_state', v_vote_state);
end;
$function$;

revoke all on function public.admin_finalize_match_sport_postgame(
  uuid, integer, integer, jsonb, text
) from public, anon;
grant execute on function public.admin_finalize_match_sport_postgame(
  uuid, integer, integer, jsonb, text
) to authenticated, service_role;

-- Répare les désynchronisations déjà présentes sans toucher aux bulletins,
-- résultats ou gagnants du scrutin.
update public.match_sport_workflows workflow
set vote_state = election.state,
    updated_at = now()
from public.match_sport_motm_elections election
where election.match_id = workflow.match_id
  and workflow.vote_state is distinct from election.state;

commit;
