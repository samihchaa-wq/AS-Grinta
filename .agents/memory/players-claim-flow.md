---
name: Player accounts & roster linking
description: How an account is created, validated and linked to a roster player (the old claim-token flow is gone)
---

# Player accounts & roster linking

The old claim flow no longer exists: no `players.claim_token`, no
`claim_player_profile` RPC, no `/claim` page. The `claim-account` Edge
Function only answers `410 Gone` until it is removed.

## Roles
- Only two profile roles: `pronostiqueur` and `admin` (`profiles_role_check`).
- The former `moderateur` role is gone; `is_admin()` / `is_match_staff()`
  accept an active `admin` only.

## Account creation
- Public sign-up page (`AuthRegisterPage`) calls the `register-account` Edge
  Function. The account is created with status `pending` and has no business
  access until validated.

## Validation and linking (admin only)
- Administration > Utilisateurs: `staff_validate_profile(profile, season_player?)`
  sets the profile `active` and can link it to a roster player at once.
- `/players` (`PlayersRegistryPage`, admin only) lists the season roster
  (`season_players`) and links or unlinks an account with
  `staff_set_season_player_profile` — an RPC, never a direct table update: it
  locks the row, refuses non-active profiles and merges player identities
  (`private.merge_player_identities`).
- Historical players are linked with `staff_set_historical_profile`.
- Linking is optional: a roster player may have no account.
