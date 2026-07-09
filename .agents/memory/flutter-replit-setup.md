---
name: Flutter on Replit via Nix
description: How to install Flutter and serve a Flutter web build on Replit.
---

Install Flutter via `installSystemDependencies({ packages: ["flutter"] })`.
Flutter 3.32.0 is available on the `stable-25_05` Nix channel.

Workflow command:
```
flutter build web --release && python3 -m http.server 5000 --directory build/web
```

**Why:** Flutter is not a Replit module (listAvailableModules returns 0 results) — Nix is the only path. Python's built-in http.server requires no install.

**How to apply:** Any Flutter project imported to Replit needs this setup. Run `flutter pub get` first, then `flutter analyze` before building.

web/index.html: use relative asset paths (`flutter_bootstrap.js`, `manifest.json`) instead of absolute paths like `/AS-Grinta/flutter_bootstrap.js`. The `--base-href` flag at build time rewrites `<base href>` so relative paths work in both root and subpath deployments.
