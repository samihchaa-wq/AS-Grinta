---
name: Independent Players & Claim Flow
description: Architecture of the players table and profile-claiming mechanism
---

# Independent Players

## Table: `players` (migration 202607090014)
- Columns: id, first_name, last_name, is_goalkeeper, is_active, linked_profile_id, claim_token (uuid), claim_expires_at, claimed_at, archived_at
- Backfilled from `profiles` at migration time

## Admin UI: `/players` (PlayersPage)
- Lists all players from `players` table
- Create, generate/revoke claim token, archive/restore
- Claim token is a UUID v4 generated in Dart (`Random.secure()`, RFC 4122 v4)
- Token validity: 7 days

## Claim flow: `/claim?token=...`
- User enters/pastes claim token on `ClaimPlayerPage`
- Calls RPC `claim_player_profile(claim uuid)` — NOT a direct table update
- **Why RPC:** The RPC uses `FOR UPDATE` row lock preventing race conditions; also validates auth.uid() server-side
- ProfileId is passed to claimProfile() but ignored — RPC uses auth.uid() directly

## Error handling
- If `players` table missing: _ErrorView shows "table players n'existe pas — appliquez les migrations"
- PostgrestException message is surfaced directly to the user (already in French from the RPC)

## Navigation
- Admin page has shortcuts to /players and /coach
- /players is RBAC-restricted to admin + moderateur
