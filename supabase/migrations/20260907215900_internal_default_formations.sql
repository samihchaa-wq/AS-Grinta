-- Un seul dispositif autorisé par taille d'équipe pour les matchs entre nous.
-- Les coordonnées sont gérées côté Flutter ; le serveur verrouille ici le code
-- et les postes afin qu'un ancien client ne puisse pas republier une variante.

create or replace function private.internal_default_formation_code(
  p_player_count integer
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select case least(greatest(coalesce(p_player_count, 0), 0), 11)
    when 1 then 'GB'
    when 2 then '1'
    when 3 then '1-1'
    when 4 then '2-1'
    when 5 then '1-2-1'
    when 6 then '2-2-1'
    when 7 then '2-3-1'
    when 8 then '3-3-1'
    when 9 then '3-3-2'
    when 10 then '3-4-2'
    when 11 then '4-3-3'
    else null
  end;
$function$;

create or replace function private.internal_v4_formation_slots(p_code text)
returns text[]
language sql
immutable
set search_path to ''
as $function$
  select case p_code
    when 'GB' then array['GB']
    when '1' then array['GB','MC']
    when '1-1' then array['GB','DC','BU']
    when '2-1' then array['GB','DCG','DCD','BU']
    when '1-2-1' then array['GB','DC','MCG','MCD','BU']
    when '2-2-1' then array['GB','DCG','DCD','MCG','MCD','BU']
    when '2-3-1' then array['GB','DCG','DCD','MCG','MC','MCD','BU']
    when '3-3-1' then array['GB','DCG','DC','DCD','MCG','MC','MCD','BU']
    when '3-3-2' then array['GB','DCG','DC','DCD','MCG','MC','MCD','BUG','BUD']
    when '3-4-2' then array['GB','DCG','DC','DCD','MG','MCG','MCD','MD','BUG','BUD']
    when '4-3-3' then array['GB','DG','DCG','DCD','DD','MCG','MC','MCD','AG','BU','AD']
    else null
  end;
$function$;

revoke all on function private.internal_default_formation_code(integer)
  from public, anon, authenticated;
revoke all on function private.internal_v4_formation_slots(text)
  from public, anon, authenticated;
