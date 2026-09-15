# Transition des rôles

Décision produit du 5 août 2026 : AS Grinta ne conserve plus que deux niveaux d'accès applicatifs.

- `admin` : tous les droits d'administration ;
- `pronostiqueur` : utilisateur standard, affiché comme « Utilisateur » dans l'interface.

Les notions de coach et gardien restent des attributs sportifs et ne créent pas un troisième niveau d'accès.

Gardien n'accorde aucun droit applicatif supplémentaire.

Coach accorde le pilotage du Live des matchs de la saison, et rien d'autre de l'administration du club. Depuis le 15 septembre 2026, le coach conserve par ailleurs exactement les fonctionnalités d'un membre ordinaire : voir `docs/changes/coach-is-a-regular-member.md`.

La valeur historique `moderateur` doit être migrée vers `admin` en base puis retirée des contrôles et de l'interface. Les anciennes migrations restent immuables. Les anciens noms de fonctions liés au modérateur peuvent rester temporairement comme alias techniques de compatibilité pendant le déploiement, sans recréer un troisième rôle.
