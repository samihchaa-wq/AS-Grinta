# Tests Supabase

La suite métier utilise pgTAP sur une pile Supabase locale et éphémère. Elle ne se connecte jamais à la production.

L’historique ancien du dépôt n’est pas entièrement rejouable depuis une base vide : une migration utilise `profiles.status` avant sa création. Le workflow installe donc une baseline structurelle limitée aux modules testés, puis applique réellement les migrations des passes #284 et #287.

Fichiers principaux :

- `bootstrap/current_business_schema.sql` : tables, RPC et politiques nécessaires, sans donnée réelle ;
- `bootstrap/enable_prediction_guard.sql` : recrée le trigger déjà présent en production ;
- `database/business_rls.test.sql` : scénarios métier et RLS, tous annulés par `ROLLBACK`.

La commande pgTAP exécutée par la CI est :

```bash
supabase test db supabase/tests/database/business_rls.test.sql
```

Les scénarios couvrent l’authentification, les politiques RLS, les pronostics, le bonus x2, les fermetures manuelle et H−5, les opérations staff, les rollbacks atomiques et le rapport d’intégrité.
