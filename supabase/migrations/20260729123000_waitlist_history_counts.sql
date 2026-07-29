-- Expose, for each permanent player, how many times their waitlist turn was
-- definitively consumed during the current season. The public wrappers enrich
-- the existing private payloads so later workflow/draft behavior stays intact.

create or replace function private.enrich_sport_waitlist_history(p_payload jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_set(
    p_payload,
    '{entries}',
    coalesce(
      (
        select jsonb_agg(
          entry || jsonb_build_object(
            'current_season_waitlist_count',
            (
              select count(distinct participant.match_id)::integer
              from public.match_sport_participants participant
              join public.matches match on match.id = participant.match_id
              where participant.season_player_id = (entry ->> 'season_player_id')::uuid
                and match.season_id = (p_payload ->> 'season_id')::uuid
                and participant.waitlist_turn_state = 'consumed'
            )
          )
          order by ordinal
        )
        from jsonb_array_elements(coalesce(p_payload -> 'entries', '[]'::jsonb))
          with ordinality as rows(entry, ordinal)
      ),
      '[]'::jsonb
    ),
    true
  );
$function$;

create or replace function private.enrich_match_convocation_history(p_payload jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_set(
    p_payload,
    '{players}',
    coalesce(
      (
        select jsonb_agg(
          player || jsonb_build_object(
            'current_season_waitlist_count',
            case
              when nullif(player ->> 'season_player_id', '') is null then 0
              else (
                select count(distinct participant.match_id)::integer
                from public.match_sport_participants participant
                join public.matches match on match.id = participant.match_id
                where participant.season_player_id = (player ->> 'season_player_id')::uuid
                  and match.season_id = (p_payload ->> 'season_id')::uuid
                  and participant.waitlist_turn_state = 'consumed'
              )
            end
          )
          order by ordinal
        )
        from jsonb_array_elements(coalesce(p_payload -> 'players', '[]'::jsonb))
          with ordinality as rows(player, ordinal)
      ),
      '[]'::jsonb
    ),
    true
  );
$function$;

create or replace function public.admin_get_sport_waitlist(p_season_id uuid default null)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.enrich_sport_waitlist_history(
    private.get_sport_waitlist(p_season_id)
  );
$function$;

create or replace function public.admin_reorder_sport_waitlist(
  p_season_id uuid,
  p_ordered_player_ids uuid[],
  p_reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.enrich_sport_waitlist_history(
    private.reorder_sport_waitlist(
      p_season_id,
      p_ordered_player_ids,
      p_reason
    )
  );
$function$;

create or replace function public.admin_get_match_convocations(p_match_id uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.enrich_match_convocation_history(
    private.get_match_convocations(p_match_id)
  );
$function$;
