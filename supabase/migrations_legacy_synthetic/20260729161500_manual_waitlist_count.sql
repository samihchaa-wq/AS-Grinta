-- Le nombre de fois en liste d'attente n'est plus calculé automatiquement
-- (à partir des tours de liste d'attente consommés) : c'est désormais un
-- champ que l'admin renseigne lui-même. On initialise la nouvelle colonne
-- avec la valeur jusqu'ici calculée pour ne pas perdre l'historique déjà
-- affiché aux joueurs.

alter table public.sport_waitlist_entries
  add column manual_waitlist_count integer not null default 0
  constraint sport_waitlist_entries_manual_waitlist_count_check
    check (manual_waitlist_count >= 0);

update public.sport_waitlist_entries entry
set manual_waitlist_count = coalesce((
  select count(distinct participant.match_id)::integer
  from public.match_sport_participants participant
  join public.matches match on match.id = participant.match_id
  where participant.season_player_id = entry.season_player_id
    and match.season_id = entry.season_id
    and participant.waitlist_turn_state = 'consumed'
), 0);

create or replace function public.admin_set_waitlist_manual_count(
  p_season_player_id uuid,
  p_count integer
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;
  if p_count is null or p_count < 0 then
    raise exception 'Invalid count' using errcode = '22023';
  end if;

  update public.sport_waitlist_entries
  set manual_waitlist_count = p_count,
      updated_at = now(),
      updated_by = (select auth.uid())
  where season_player_id = p_season_player_id;

  if not found then
    raise exception 'Waitlist entry not found' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.admin_set_waitlist_manual_count(uuid, integer) to authenticated;

-- Les deux enrichissements existants lisaient le nombre de fois en liste
-- d'attente à partir des tours consommés : ils lisent maintenant la valeur
-- saisie manuellement, sans changer la forme de leur réponse (même clé
-- JSON « current_season_waitlist_count »), donc aucun changement client
-- n'est requis côté lecture.

create or replace function private.enrich_sport_waitlist_history(p_payload jsonb)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_set(
    p_payload,
    '{entries}',
    coalesce(
      (
        select jsonb_agg(
          entry || jsonb_build_object(
            'current_season_waitlist_count',
            coalesce((
              select swe.manual_waitlist_count
              from public.sport_waitlist_entries swe
              where swe.season_player_id = (entry ->> 'season_player_id')::uuid
            ), 0)
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
$$;

create or replace function private.enrich_match_convocation_history(p_payload jsonb)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
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
              else coalesce((
                select swe.manual_waitlist_count
                from public.sport_waitlist_entries swe
                where swe.season_player_id = (player ->> 'season_player_id')::uuid
              ), 0)
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
$$;
