# Transition des rôles

Décision produit du 5 août 2026 : AS Grinta ne conserve plus que deux niveaux d'accès applicatifs.

- `admin` : tous les droits d'administration ;
- `pronostiqueur` : utilisateur standard, affiché comme « Utilisateur » dans l'interface.

Les notions de coach et gardien restent des attributs sportifs. Elles n'accordent aucun droit applicatif supplémentaire.

La valeur historique `moderateur` doit être migrée vers `admin` en base puis retirée des contrôles et de l'interface. Les anciennes migrations restent immuables. Les anciens noms de fonctions liés au modérateur peuvent rester temporairement comme alias techniques de compatibilité pendant le déploiement, sans recréer un troisième rôle.
