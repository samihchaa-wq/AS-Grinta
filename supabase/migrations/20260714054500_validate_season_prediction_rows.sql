-- Enforce the business invariants of season predictions at database level.

create or replace function public.validate_season_prediction_row()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_player_season_id uuid;
  v_is_goalkeeper boolean;
  v_is_active boolean;
begin
  select sp.season_id, sp.is_goalkeeper, sp.is_active
  into v_player_season_id, v_is_goalkeeper, v_is_active
  from public.season_players sp
  where sp.id = new.season_player_id;

  if not found then
    raise exception 'Joueur de saison introuvable.' using errcode = '23503';
  end if;

  if v_player_season_id <> new.season_id then
    raise exception 'Le joueur n’appartient pas à cette saison.' using errcode = '23514';
  end if;

  if not v_is_active then
    raise exception 'Ce joueur n’est plus actif pour cette saison.' using errcode = '23514';
  end if;

  if v_is_goalkeeper and new.category <> 'clean_sheets' then
    raise exception 'Un gardien doit être pronostiqué en clean sheets.' using errcode = '23514';
  end if;

  if not v_is_goalkeeper and new.category <> 'buts' then
    raise exception 'Un joueur de champ doit être pronostiqué en buts.' using errcode = '23514';
  end if;

  if new.predicted_value_30 < 0
     or new.predicted_value_30 > case when v_is_goalkeeper then 30 else 99 end then
    raise exception 'Valeur de pronostic hors limites.' using errcode = '22003';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_season_prediction_row
  on public.season_predictions;

create trigger trg_validate_season_prediction_row
before insert or update of season_id, season_player_id, category, predicted_value_30
on public.season_predictions
for each row
execute function public.validate_season_prediction_row();

revoke execute on function public.validate_season_prediction_row()
  from public, anon, authenticated;
grant execute on function public.validate_season_prediction_row()
  to service_role;
