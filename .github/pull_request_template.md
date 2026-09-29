Issue: #<number>

Checklist, matching CI. Run in the repository root:

- [ ] `dart pub get --no-example`
- [ ] `dart format --output=none --set-exit-if-changed lib test bin`
- [ ] `dart analyze --fatal-infos lib test bin`
- [ ] `dart test --exclude-tags e2e`
- [ ] `CHANGELOG.md` entry added
