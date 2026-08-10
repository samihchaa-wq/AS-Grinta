-- Export du Tableau Blanc avant l'heure du coup d'envoi.
--
-- private.finalize_match_sport_postgame refusait toute validation tant
-- que now() < kickoff_at, ce qui bloquait le bouton « Valider » du
-- récapitulatif sur un match à venir — alors que le Tableau Blanc est
-- justement utilisable sur tous les prochains matchs depuis la
-- migration 20260731190000.
--
-- Le garde-fou reste actif pour la validation manuelle classique, et
-- n'est levé que lorsqu'une session live existe ET a été menée jusqu'à
-- « Fin du match » : l'intention du coach est alors explicite.
--
-- On patche uniquement cette condition, sans réécrire le corps complet
-- de la fonction : elle est longue et partagée avec le pipeline de
-- finalisation existant (score / présences / badges / Homme du Match),
-- qui doit rester strictement inchangé.

do $do$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'finalize_match_sport_postgame';

  if v_def is null then
    raise exception 'private.finalize_match_sport_postgame introuvable';
  end if;

  -- Idempotence : ne rien faire si le correctif est déjà en place.
  if position('live_session.state' in v_def) > 0 then
    return;
  end if;

  v_new := replace(
    v_def,
    'if now() < v_kickoff_at then',
    'if now() < v_kickoff_at and not exists (
    select 1
    from public.match_live_sessions live_session
    where live_session.match_id = p_match_id
      and live_session.state = ''finished''
  ) then'
  );

  if v_new = v_def then
    raise exception
      'Garde-fou kickoff introuvable dans finalize_match_sport_postgame';
  end if;

  execute v_new;
end
$do$;
