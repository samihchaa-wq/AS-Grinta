-- Les heures relevees dans SportEasy sont, en pratique au club, des heures de
-- rendez-vous et non des coups d'envoi : l'evenement y etait cree a l'heure de
-- convocation. Le coup d'envoi reel a lieu 30 minutes plus tard.
--
-- L'archive ne doit afficher que l'heure de debut du match. On decale donc les
-- heures importees par le lot 1 de +30 minutes.
--
-- Appliquee en production le 2026-08-26 sous la version 20260826163813.
-- Verifie apres coup : 313 heures, de 20:00 a 22:30, somme 392990 minutes.
--
-- Trois situations sont distinguees a partir des donnees elles-memes, sans
-- objet de suivi supplementaire :
--
--   * aucune heure enregistree  -> base neuve, l'archive n'a pas ete chargee,
--                                  la migration ne fait rien ;
--   * somme des heures = 383600 -> etat attendu avant decalage, on decale ;
--   * somme des heures = 392990 -> decalage deja applique, on ne refait rien.
--
-- Tout autre etat arrete la migration plutot que de decaler des heures dont
-- l'origine n'est pas certaine.

do $decalage$
declare
  v_rencontres integer;
  v_somme bigint;
  v_trop_tard integer;
  v_decalees integer;
  v_attendu_avant constant bigint := 383600;
  v_attendu_apres constant bigint := 392990;
begin
  select count(*) filter (where match_time is not null),
         coalesce(sum(extract(hour from match_time) * 60
                    + extract(minute from match_time)), 0)
  into v_rencontres, v_somme
  from public.historical_match_scores;

  if v_rencontres = 0 then
    raise notice 'Aucune heure archivee, rien a decaler.';
    return;
  end if;

  if v_somme = v_attendu_apres then
    raise notice 'Decalage de 30 minutes deja applique, rien a faire.';
    return;
  end if;

  if v_somme <> v_attendu_avant then
    raise exception
      'Decalage refuse : somme des heures = % minutes sur % rencontres, attendu % avant decalage',
      v_somme, v_rencontres, v_attendu_avant;
  end if;

  -- Une rencontre decalee ne doit pas franchir minuit.
  select count(*) into v_trop_tard
  from public.historical_match_scores
  where match_time > time '23:29';

  if v_trop_tard > 0 then
    raise exception
      'Decalage refuse : % rencontres passeraient apres minuit', v_trop_tard;
  end if;

  update public.historical_match_scores
  set match_time = match_time + interval '30 minutes'
  where match_time is not null;

  get diagnostics v_decalees = row_count;

  select coalesce(sum(extract(hour from match_time) * 60
                    + extract(minute from match_time)), 0)
  into v_somme
  from public.historical_match_scores;

  if v_somme <> v_attendu_apres then
    raise exception 'Decalage incorrect : somme des heures = % minutes, attendu %',
      v_somme, v_attendu_apres;
  end if;

  raise notice 'Decalage de 30 minutes applique a % rencontres.', v_decalees;
end;
$decalage$;
