-- Instantané, en lecture seule, des compteurs de requêtes de la production.
--
-- Utilisé par `.github/workflows/supabase_usage_guard.yml` : la même requête
-- est lancée chaque jour, puis `tool/check_request_usage.py` compare avec la
-- veille pour obtenir le nombre de requêtes des dernières 24 heures.
--
-- Aucune donnée métier n'est lue : uniquement les statistiques de
-- `pg_stat_statements`, dont les valeurs littérales sont déjà remplacées par
-- `$1`, `$2`… Le texte n'est gardé que pour les lectures et écritures
-- ordinaires (SELECT, WITH, INSERT, UPDATE, DELETE), tronqué ; les autres
-- instructions (réglages, administration) n'apparaissent que sous un libellé
-- générique, pour qu'aucune valeur ne puisse fuiter dans un rapport public.

select json_build_object(
  'taken_at', now(),
  'entries', coalesce(json_agg(entry), '[]'::json)
) as snapshot
from (
  select
    s.userid::text || '|' || s.dbid::text || '|' || s.queryid::text
      || '|' || s.toplevel::text as key,
    pg_catalog.pg_get_userbyid(s.userid) as role,
    s.calls,
    case
      -- Requête de l'application passée par l'API (PostgREST) : son texte
      -- généré commence toujours de la même façon, seul le nom de la fonction
      -- ou de la table appelée permet de la reconnaître.
      when s.query like 'WITH pgrst_source AS%' then
        coalesce(
          'API rpc/' || substring(s.query from '"public"\."([A-Za-z0-9_]+)"\('),
          'API table ' || substring(s.query from '"public"\."([A-Za-z0-9_]+)"'),
          'API ?'
        )
      when s.query ~* '^\s*(select|with|insert|update|delete)\s'
        then left(regexp_replace(s.query, '\s+', ' ', 'g'), 160)
      else '<instruction utilitaire>'
    end as query
  from extensions.pg_stat_statements s
  where s.calls > 0
    and s.queryid is not null
) entry;
