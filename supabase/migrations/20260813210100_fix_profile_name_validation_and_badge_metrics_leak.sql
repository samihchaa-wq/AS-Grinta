-- Bug 3 : le declencheur trg_validate_profile_names s'execute en SECURITY
-- INVOKER, or le role `authenticated` n'avait pas le droit d'executer
-- public.is_valid_person_name(). Toute modification de prenom / nom / surnom
-- par un membre echouait donc en 403 « permission denied for function ».
--
-- Bug 5 : public.profile_badge_metrics() etait la seule fonction SECURITY
-- DEFINER exposee a `authenticated` sans controle d'identite. N'importe quel
-- membre pouvait lire le bilan complet d'un autre membre, y compris la
-- metrique `bet_against_grinta` qui alimente le badge secret « Traitre ».
-- L'implementation part dans le schema private ; le point d'entree public
-- devient un garde-fou. Les consommateurs internes (etoiles de badges,
-- recalcul) attaquent directement l'implementation privee, car ils doivent
-- continuer a calculer pour n'importe quel profil.

begin;

-- ---------------------------------------------------------------------------
-- Bug 3 — validation des noms de profil
-- ---------------------------------------------------------------------------

revoke all on function public.is_valid_person_name(text) from public, anon;
grant execute on function public.is_valid_person_name(text)
  to authenticated, service_role;

comment on function public.is_valid_person_name(text) is
  'Verifie qu''un nom de personne ne contient que des lettres. Executable par authenticated : trg_validate_profile_names l''appelle en SECURITY INVOKER.';

-- ---------------------------------------------------------------------------
-- Bug 5 — cloisonnement des metriques de badges
-- ---------------------------------------------------------------------------

-- Rien n'est recopie ici : les implementations existantes sont DEPLACEES vers
-- `private`, et les appelants internes sont reecrits a partir de leur
-- definition courante. Figer une copie ferait diverger ce fichier de la
-- realite des que le catalogue de badges evolue — ce qui s'est deja produit
-- avec l'ajout de `display_value` a featured_badges().

alter function public.profile_badge_metrics(uuid) set schema private;
alter function public.profile_badge_stars(uuid) set schema private;

-- Les etoiles doivent pouvoir lire les metriques privees quel que soit
-- l'appelant : featured_badges() les demande pour n'importe quel profil.
alter function private.profile_badge_stars(uuid) security definer;

revoke all on function private.profile_badge_metrics(uuid)
  from public, anon, authenticated;

revoke all on function private.profile_badge_stars(uuid) from public, anon;
-- `private` n'est pas exposee par PostgREST : ce grant ne sert qu'aux
-- fonctions SECURITY INVOKER du schema public, comme featured_badges().
grant execute on function private.profile_badge_stars(uuid)
  to authenticated, service_role;

comment on function private.profile_badge_metrics(uuid) is
  'Implementation reelle des metriques de badges. Reservee aux appelants internes : passer par public.profile_badge_metrics() qui controle l''identite.';

-- Tout appelant interne suit le deplacement. La boucle echoue bruyamment si
-- plus rien ne reference ces fonctions : mieux vaut une migration qui refuse
-- de s'appliquer qu'un cloisonnement silencieusement inoperant.
do $repoint$
declare
  v_target record;
  v_patched integer := 0;
begin
  for v_target in
    select proc.oid
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname in ('public', 'private')
      and proc.prokind = 'f'
      and (proc.prosrc like '%public.profile_badge_metrics(%'
        or proc.prosrc like '%public.profile_badge_stars(%')
  loop
    execute replace(
      replace(
        pg_get_functiondef(v_target.oid),
        'public.profile_badge_metrics(', 'private.profile_badge_metrics('
      ),
      'public.profile_badge_stars(', 'private.profile_badge_stars('
    );
    v_patched := v_patched + 1;
  end loop;

  if v_patched = 0 then
    raise exception
      'Aucun appelant de profile_badge_metrics/stars trouve : le cloisonnement serait inoperant.';
  end if;
  raise notice 'profile_badge_* : % appelant(s) repointe(s) vers private', v_patched;
end;
$repoint$;

-- Points d'entree publics : un membre ne lit que son propre bilan, le staff
-- lit celui de tout le monde. La signature est reprise de l'implementation
-- privee, donc elle suit automatiquement toute evolution du catalogue.
do $wrappers$
declare
  v_name text;
  v_result text;
begin
  foreach v_name in array array['profile_badge_metrics', 'profile_badge_stars']
  loop
    select pg_get_function_result(proc.oid)
    into strict v_result
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'private' and proc.proname = v_name;

    execute format(
      $wrapper$
        create or replace function public.%1$I(p_profile_id uuid)
        returns %2$s
        language plpgsql
        security definer
        set search_path to ''
        as $body$
        begin
          if p_profile_id is null then
            return;
          end if;

          if p_profile_id is distinct from (select auth.uid())
             and not public.is_match_staff() then
            raise exception 'Forbidden' using errcode = '42501';
          end if;

          return query select * from private.%1$I(p_profile_id);
        end;
        $body$;
      $wrapper$,
      v_name, v_result
    );

    execute format(
      'revoke all on function public.%I(uuid) from public, anon', v_name
    );
    execute format(
      'grant execute on function public.%I(uuid) to authenticated, service_role',
      v_name
    );
  end loop;
end;
$wrappers$;

comment on function public.profile_badge_metrics(uuid) is
  'Metriques de badges d''un profil : reservees au profil appelant, sauf pour le staff (is_match_staff).';
comment on function public.profile_badge_stars(uuid) is
  'Etoiles de badges d''un profil : reservees au profil appelant, sauf pour le staff (is_match_staff).';

commit;
