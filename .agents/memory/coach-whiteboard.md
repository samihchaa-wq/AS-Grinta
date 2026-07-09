---
name: Coach Whiteboard
description: Architecture and key decisions for the local coach tactical board (/coach route)
---

# Coach Whiteboard module

## Route & RBAC
- `/coach` accessible to `admin` and `moderateur` only (RBAC in `app_router.dart`)
- Modérateur nav bar shows "Tableau" (5th item = Admin, 3rd = Tableau)

## Provider lifecycle
- `coachBoardControllerProvider` is **autoDispose** — Timer.periodic is cancelled automatically when the user navigates away from /coach
- **Why:** Without autoDispose, a started timer would run off-screen indefinitely

## Timer
- `Timer.periodic(Duration(seconds: 1), ...)` inside the StateNotifier
- Pause = cancel ticker; Reset = cancel + set elapsedSeconds=0, isRunning=false, events=[], scores=0

## resetBoard() contract
- Cancels timer, reconstructs a clean `CoachBoardState` (events=[], scores=0, elapsed=0)
- KEEPS current players list and formation — just re-fills the lineup from scratch
- **Why:** UX says "remise à zéro" = fresh match, not reload data from Supabase

## Formation positions (2D)
- `computeFormationPositions(code, slots)` in `coach_board.dart`
- Parses "4-3-3" → [4,3,3] rows; GK always at (0.5, 0.90); outfield distributed defense→attack (dy 0.74→0.14)
- Loads from Supabase `formations` table; falls back to `hardcodedFormationSlots()` if unavailable

## Players source
- Loads from `profiles` WHERE role='pronostiqueur' AND status='active'
- Goalkeeper flag from `profiles.is_goalkeeper`
