begin;

-- L'effectif d'un match n'a plus qu'un état : publié, dès la création du
-- match.
--
-- Il naissait jusqu'ici en « brouillon » et passait en « publié » la
-- première fois qu'un admin ouvrait la page du match : l'application
-- enregistrait alors l'effectif d'elle-même. Personne ne choisissait ce
-- moment et personne ne le voyait. Pourtant, il changeait les règles :
-- tant que l'effectif restait en brouillon, les joueurs ne voyaient pas
-- l'effectif ni leur statut, aucune notification de convocation ou de
-- liste d'attente ne partait, un désistement ne réservait pas la place du
-- joueur qui revient, et la composition ne pouvait pas être publiée. Cette
-- saison, ce brouillon a duré de quelques secondes à 23 minutes après
-- l'ouverture des disponibilités, selon le moment où un admin passait.
--
-- Désormais :
-- - un nouveau match naît publié, version 1 ;
-- - un report à un autre jour remet les réponses à zéro mais laisse
--   l'effectif publié ;
-- - les matchs encore en brouillon passent en publié. En production, aucun
--   n'a de réponse : aucune notification ne part.
--
-- La version démarre à 1 parce que le passage de 0 à 1 marquait la première
-- publication : pour un match entre nous, il efface la composition interne
-- préparée avant. Sans brouillon, ce passage ne doit plus se produire après
-- la création, sinon la première modification de l'effectif effacerait une
-- composition déjà préparée.
--
-- Les règles qui distinguent encore le brouillon (recalcul à la lecture,
-- notification groupée au premier passage en publié) restent en place : il
-- n'y a simplement plus de brouillon pour les déclencher.

alter table public.match_sport_workflows
  alter column convocation_state set default 'published',
  alter column convocation_version set default 1,
  alter column convocation_published_at set default now();

create or replace function private.handle_match_notification_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_in_old_window boolean := false;
  v_date_changed boolean := false;
  v_old_opens_at timestamptz;
  v_mode text := 'automatic';
  v_new_opens_at timestamptz;
  v_new_state public.sport_availability_state;
begin
  select workflow.availability_opens_at, workflow.availability_schedule_mode
  into v_old_opens_at, v_mode
  from public.match_sport_workflows workflow
  where workflow.match_id = old.id;

  v_old_opens_at := coalesce(v_old_opens_at, private.match_features_open_at(old.kickoff_at));
  v_mode := coalesce(v_mode, 'automatic');

  if old.kickoff_at is not null then
    v_in_old_window := now() >= v_old_opens_at and now() < old.kickoff_at;
  end if;

  if old.status = 'a_venir'
     and new.status = 'annule'
     and v_in_old_window then
    if not private.is_feature_enabled('notifications_paused') then
      perform public.internal_push_notify('match_cancelled', new.id);
    end if;
    return new;
  end if;

  if old.status = 'a_venir'
     and new.status = 'a_venir'
     and old.kickoff_at is distinct from new.kickoff_at
     and new.kickoff_at is not null
     and v_in_old_window then
    v_date_changed := (old.kickoff_at at time zone 'Europe/Paris')::date
      is distinct from (new.kickoff_at at time zone 'Europe/Paris')::date;

    if v_date_changed then
      if v_mode = 'automatic' then
        v_new_opens_at := private.match_features_open_at(new.kickoff_at);
      else
        v_new_opens_at := v_old_opens_at;
        if v_new_opens_at >= new.kickoff_at then
          v_mode := 'automatic';
          v_new_opens_at := private.match_features_open_at(new.kickoff_at);
        end if;
      end if;

      v_new_state := case
        when now() >= new.kickoff_at then 'closed'::public.sport_availability_state
        when now() >= v_new_opens_at then 'open'::public.sport_availability_state
        else 'pending'::public.sport_availability_state
      end;

      update public.match_sport_participants participant
      set availability_status = 'no_response',
          availability_comment_private = null,
          availability_updated_at = null,
          availability_updated_by = null,
          convocation_status = 'not_applicable',
          convocation_manual_override = false,
          waitlist_recommended_not_convoked = false,
          waitlist_turn_should_consume = false,
          updated_at = now()
      where participant.match_id = new.id
        and participant.season_player_id is not null
        and (
          participant.is_eligible
          or private.participant_is_coach(participant.season_player_id)
        );

      update public.match_sport_workflows workflow
      set availability_opens_at = v_new_opens_at,
          availability_schedule_mode = v_mode,
          availability_state = v_new_state,
          availability_opened_at = case
            when v_new_state = 'open' then coalesce(workflow.availability_opened_at, now())
            else null
          end,
          convocation_state = 'published',
          convocation_published_at = now(),
          convocation_version = workflow.convocation_version + 1,
          updated_at = now()
      where workflow.match_id = new.id;

      delete from public.push_notification_log
      where match_id = new.id and kind = 'prediction_j5';

      if not private.is_feature_enabled('notifications_paused') then
        insert into public.push_notification_log(match_id, kind, sent_at)
        values (new.id, 'match_rescheduled_date', now())
        on conflict (match_id, kind) do update set sent_at = excluded.sent_at;
        perform public.internal_push_notify('match_rescheduled_date', new.id);
      end if;
    else
      if not private.is_feature_enabled('notifications_paused') then
        perform public.internal_push_notify('match_rescheduled_time', new.id);
      end if;
    end if;
  end if;

  return new;
end;
$function$;

update public.match_sport_workflows workflow
set convocation_state = 'published',
    convocation_published_at = coalesce(workflow.convocation_published_at, now()),
    convocation_version = greatest(workflow.convocation_version, 1),
    updated_at = now()
where workflow.convocation_state = 'draft';

commit;
