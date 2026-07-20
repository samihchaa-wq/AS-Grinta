-- La migration #284 remplace le corps de la fonction, mais le trigger existait
-- déjà en production. La baseline locale le recrée explicitement.
drop trigger if exists guard_match_prediction_window
  on public.match_predictions;
create trigger guard_match_prediction_window
before insert or update on public.match_predictions
for each row execute function public.guard_match_prediction_window();
