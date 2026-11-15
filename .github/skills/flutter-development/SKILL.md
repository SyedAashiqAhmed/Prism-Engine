---
name: flutter-development
description: Develop and validate Prism-Engine as a Flutter/Dart application.
---

Use the existing project structure and coding conventions.

For Dart or Flutter changes:

1. Run `flutter pub get` when dependencies change.
2. Run `dart format .`.
3. Run `flutter analyze`.
4. Run `flutter test`.
5. For Android release validation, run `flutter build apk`.
6. Prefer reusable widgets and null-safe Dart.
7. Do not modify generated files unless required.
8. Add focused tests for new behavior.
