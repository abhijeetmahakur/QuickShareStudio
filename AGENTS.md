# Standing Rule for QuickShare Studio

After every code change I make, always do all of these without being asked:

1. **Analyze and Test:** Run `flutter analyze` and the tests, and fix any errors.
2. **Version Bump:** Bump the version in `pubspec.yaml` (patch number and build number), and sync `VERSION`, `windows/installer/quickshare.iss`, `lib/core/constants.dart`, and `CHANGELOG.md`.
3. **Commit & Push:** Commit with a clear message and push to `main`. Never force push.
4. **Monitor Release:** Confirm the GitHub Actions release finished, and provide the release link.
5. **Summary & Verification:** Tell me in 3 lines what changed and what I must test.
