# Contributing

1. Keep the package focused on TC260 AIGC metadata; generic metadata copying is
   outside its scope.
2. Add a regression test for every parser or writer behavior change.
3. Run `dart format .`, `dart analyze --fatal-infos`, and `dart test`.
4. Run `dart pub publish --dry-run` for changes affecting package contents.
5. Update both READMEs when public behavior changes.

Fixtures must be synthetic or sanitized and safe to redistribute.
