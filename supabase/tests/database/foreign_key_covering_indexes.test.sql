begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Postgres n'impose aucun index du cote enfant d'une cle etrangere. Sans lui,
-- chaque suppression d'une ligne parente doit parcourir toute la table enfant
-- pour verifier qu'aucune ligne n'y renvoie. Le cout ne se voit pas tant que
-- la table enfant est petite, puis il devient une suppression qui bloque.
--
-- Un index couvre la cle si les colonnes de la cle forment le debut de ses
-- colonnes indexees. Un index partiel convient aussi tant que sa condition se
-- reduit a « la colonne n'est pas vide » : la verification cherche une egalite
-- avec une cle parente, jamais vide, donc les lignes exclues ne pouvaient de
-- toute facon pas correspondre.

create temporary view foreign_keys_without_index as
  select constraint_table.table_name, constraint_table.constraint_name
  from (
    select
      namespace.nspname || '.' || child.relname as table_name,
      contrainte.conname as constraint_name,
      contrainte.conrelid as child_oid,
      contrainte.conkey as key_columns
    from pg_constraint contrainte
    join pg_class child on child.oid = contrainte.conrelid
    join pg_namespace namespace on namespace.oid = child.relnamespace
    where contrainte.contype = 'f'
      and namespace.nspname in ('public', 'private')
  ) as constraint_table
  where not exists (
    select 1
    from pg_index index_entry
    where index_entry.indrelid = constraint_table.child_oid
      and index_entry.indisvalid
      and array_length(constraint_table.key_columns, 1)
            <= index_entry.indnkeyatts
      and (index_entry.indkey::int2[])[
            0:array_length(constraint_table.key_columns, 1) - 1
          ] @> constraint_table.key_columns
      and (
        index_entry.indpred is null
        or pg_get_expr(index_entry.indpred, index_entry.indrelid)
             ~ '^\(?[a-z_]+ IS NOT NULL\)?$'
      )
  );

select diag(
  'clés étrangères sans index de couverture : '
  || string_agg(table_name || '.' || constraint_name, ', ' order by table_name)
)
from foreign_keys_without_index
having count(*) > 0;

select is(
  (select count(*) from foreign_keys_without_index),
  0::bigint,
  'toute clé étrangère de public et private est couverte par un index'
);

-- L'index du journal d'incidents porte aussi la lecture chaude de la table :
-- avant chaque écriture, le compte des incidents du meme profil sur la
-- dernière minute. Sur la seule colonne de la clé, cette lecture repasserait
-- sur tout l'historique du profil.
select ok(
  exists (
    select 1
    from pg_index index_entry
    join pg_class index_class on index_class.oid = index_entry.indexrelid
    where index_entry.indrelid = 'private.client_incident_log'::regclass
      and index_entry.indisvalid
      and index_class.relname = 'client_incident_log_profile_created_idx'
      and index_entry.indnkeyatts = 2
  ),
  'le journal d’incidents est indexé par profil puis par date'
);

select * from finish();
rollback;
