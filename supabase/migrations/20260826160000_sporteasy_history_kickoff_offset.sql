-- Les heures relevees dans SportEasy sont, en pratique au club, des heures de
-- rendez-vous et non des coups d'envoi : l'evenement y etait cree a l'heure de
-- convocation. Le coup d'envoi reel a lieu 30 minutes plus tard.
--
-- L'archive ne doit afficher que l'heure de debut du match. On decale donc les
-- 313 heures importees par le lot 1 de +30 minutes.
--
-- Apres decalage : de 20:00 a 22:30, aucune rencontre ne franchit minuit.

do $decalage$
declare
  v_avant bigint;
  v_apres bigint;
  v_attendu_avant constant bigint := 383600;
  v_attendu_apres constant bigint := 392990;
begin
  select coalesce(sum(extract(hour from match_time) * 60
                    + extract(minute from match_time)), 0)
  into v_avant
  from public.historical_match_scores;

  -- Rejouable sans risque : si le decalage est deja en place, on ne fait rien.
  if v_avant = v_attendu_apres then
    raise notice 'Decalage deja applique, rien a faire.';
    return;
  end if;

  if v_avant <> v_attendu_avant then
    raise exception
      'Decalage refuse : somme des heures = % minutes, attendu % avant decalage',
      v_avant, v_attendu_avant;
  end if;

  update public.historical_match_scores
  set match_time = match_time + interval '30 minutes'
  where match_time is not null;

  select coalesce(sum(extract(hour from match_time) * 60
                    + extract(minute from match_time)), 0)
  into v_apres
  from public.historical_match_scores;

  if v_apres <> v_attendu_apres then
    raise exception
      'Decalage incorrect : somme des heures = % minutes, attendu %',
      v_apres, v_attendu_apres;
  end if;

  if exists (
    select 1 from public.historical_match_scores
    where match_time is not null and match_time < time '20:00'
  ) then
    raise exception 'Decalage incorrect : une rencontre commence avant 20:00';
  end if;
end;
$decalage$;
