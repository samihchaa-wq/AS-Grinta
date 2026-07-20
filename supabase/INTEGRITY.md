# Contrôle d’intégrité Supabase

La migration `20260720033749_integrity_backfill_and_staff_audit.sql` ajoute la RPC `staff_app_integrity_report()`.

Cette RPC est réservée aux profils actifs ayant un rôle de staff. Elle ne retourne que des compteurs agrégés et aucune donnée personnelle.

## Contrôles couverts

- matchs sans cotes ;
- matchs terminés sans score complet ;
- matchs à venir avec un score déjà renseigné ;
- date et heure de match en double ;
- plusieurs saisons ouvertes ;
- pronostics de match orphelins ou incomplets ;
- lignes de préremplissage absentes pour les matchs à venir ;
- lignes de préremplissage absentes pour la saison ouverte ;
- divergence entre `kickoff_at` et les champs historiques date/heure.

## Utilisation

Appeler `staff_app_integrity_report()` avec une session authentifiée de staff. Un résultat sain contient :

```json
{
  "healthy": true,
  "total_issues": 0
}
```

Le rapport est un outil de diagnostic. Les corrections de données restent réalisées par des migrations Git versionnées et revues.
