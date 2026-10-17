begin;

-- Le prono s'ouvre en même temps que des disponibilités ouvertes en avance.
--
-- Un admin peut ouvrir les disponibilités d'un match avant J-6 à 12 h
-- (« maintenant » ou une date choisie) : les joueurs reçoivent alors
-- « Es-tu disponible ? ». La fiche du match, elle, gardait Effectif, Compo et
-- Prono cachés jusqu'à J-6, et le serveur refusait tout prono avant J-6.
--
-- L'application affiche désormais ces onglets dès l'ouverture réelle des
-- disponibilités. Le serveur accepte le prono à partir du même instant :
-- J-6 à 12 h, ou plus tôt si les disponibilités ont été ouvertes avant. Une
-- ouverture des disponibilités plus tardive que J-6 ne retarde jamais le
-- prono. La fermeture (T-15, ou la fermeture manuelle) ne change pas.
--
-- Seule la borne d'ouverture change dans les deux fonctions ci-dessous ;
-- chaque corps reprend sa dernière définition en production
-- (20261002120000_texts_audit_wording.sql). Les droits existants sont
-- conservés par CREATE OR REPLACE.

create or replace function private.match_predictions_open_at(
  p_match_id uuid,
  p_kickoff_at timestamptz
)
returns timestamptz
language sql
stable
set search_path to ''
as $function$
  -- least() ignore une valeur absente : sans suivi sportif, J-6 s'applique.
  select least(
    private.match_features_open_at(p_kickoff_at),
    (
      select workflow.availability_opens_at
      from public.match_sport_workflows workflow
      where workflow.match_id = p_match_id
    )
  );
$function$;

comment on function private.match_predictions_open_at(uuid, timestamptz) is
  'Ouverture du prono d''un match : J-6 à 12 h Europe/Paris, ou l''ouverture des disponibilités si elle est plus tôt.';

revoke all on function private.match_predictions_open_at(uuid, timestamptz)
  from public, anon, authenticated;

-- Garde-fou de la table des pronos : même ouverture que ci-dessus.
CREATE OR REPLACE FUNCTION public.guard_match_prediction_window()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare v_kickoff timestamptz; v_match_status text; v_closed_at timestamptz; v_match_type text; begin if (select auth.uid()) is not null and pg_trigger_depth() <= 1 then if tg_op='UPDATE' and new.match_id is distinct from old.match_id then raise exception 'Le match d’un pronostic ne peut pas être modifié.' using errcode='22023'; end if; new.profile_id := (select auth.uid()); end if; if new.is_filled then select match.kickoff_at,match.status,match.predictions_closed_at,match.match_type into v_kickoff,v_match_status,v_closed_at,v_match_type from public.matches match where match.id=new.match_id; if not found then raise exception 'Match introuvable.' using errcode='P0002'; end if; if v_match_type='entre_nous' then raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.' using errcode='22023'; end if; if v_kickoff is null or v_match_status<>'a_venir' or now()<private.match_predictions_open_at(new.match_id,v_kickoff) or now()>=private.match_prediction_closes_at(v_kickoff) or (v_closed_at is not null and now()>=v_closed_at) then raise exception 'Les pronostics de ce match sont fermés.' using errcode='22023'; end if; end if; return new; end; $function$;

-- Enregistrement du prono : même ouverture que ci-dessus.
create or replace function public.save_match_prediction(
  p_match_id uuid,
  p_score_as_grinta integer,
  p_score_adverse integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_match public.matches%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Ta session a expiré. Reconnecte-toi.' using errcode = '42501';
  end if;
  if not private.is_active_profile() then
    raise exception 'Compte inactif.' using errcode = '42501';
  end if;
  if p_match_id is null then
    raise exception 'Match requis.' using errcode = '22023';
  end if;
  if p_score_as_grinta is null or p_score_adverse is null
     or p_score_as_grinta not between 0 and 99
     or p_score_adverse not between 0 and 99 then
    raise exception 'Les scores doivent être compris entre 0 et 99.' using errcode = '22023';
  end if;

  select *
  into v_match
  from public.matches
  where id = p_match_id
  for share;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  if v_match.match_type = 'entre_nous' then
    raise exception 'Les matchs entre nous ne sont pas ouverts aux pronostics.'
      using errcode = '22023';
  end if;

  if v_match.kickoff_at is null
     or v_match.status <> 'a_venir'
     or now() < private.match_predictions_open_at(v_match.id, v_match.kickoff_at)
     or now() >= private.match_prediction_closes_at(v_match.kickoff_at)
     or (
       v_match.predictions_closed_at is not null
       and now() >= v_match.predictions_closed_at
     ) then
    raise exception 'Ce match n’est pas ouvert aux pronostics.'
      using errcode = '22023';
  end if;

  insert into public.match_predictions as existing (
    match_id,
    profile_id,
    predicted_score_as_grinta,
    predicted_score_adverse,
    is_filled,
    updated_at
  ) values (
    p_match_id,
    v_actor_id,
    p_score_as_grinta,
    p_score_adverse,
    true,
    now()
  )
  on conflict (match_id, profile_id) do update
  set predicted_score_as_grinta = excluded.predicted_score_as_grinta,
      predicted_score_adverse = excluded.predicted_score_adverse,
      is_filled = true,
      updated_at = now()
  where (
    existing.predicted_score_as_grinta,
    existing.predicted_score_adverse,
    existing.is_filled
  ) is distinct from (
    excluded.predicted_score_as_grinta,
    excluded.predicted_score_adverse,
    true
  );

  return true;
end;
$function$;

commit;
