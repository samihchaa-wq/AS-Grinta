begin;

-- Aligne le dépôt sur la production pour le contrôle du verrou du Live.
--
-- En production, `private.assert_match_admin_edit_open` est aussi exécutable
-- par `service_role`, le compte technique des traitements serveur. Le dépôt ne
-- l'accordait pas : le contrôle quotidien des fonctions (« Supabase function
-- drift guard ») signalait donc cet écart à chaque exécution.
--
-- Ce droit existe déjà en production : cette migration n'y change rien. Elle
-- n'ouvre rien aux joueurs ni aux visiteurs.

grant execute on function private.assert_match_admin_edit_open(uuid)
  to service_role;

commit;
