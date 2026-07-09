---
name: Flutter DropdownButtonFormField API
description: DropdownButtonFormField uses value: not initialValue:.
---

`DropdownButtonFormField` does NOT have an `initialValue` parameter. Use `value:` to set the current/default selection.

`initialValue` IS valid for `TextFormField` and `Autocomplete` — but not `DropdownButtonFormField`.

**Why:** Code written targeting a non-existent API will compile-fail with "The named parameter 'initialValue' isn't defined". The fix is a straightforward rename to `value:`.

**How to apply:** When analyzing Flutter code and seeing this error on a DropdownButtonFormField, rename the parameter. Note that `value:` in controlled mode requires the value to match one of the DropdownMenuItems at runtime or Flutter will assert.
