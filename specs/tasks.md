# Implementation Plan

- [x] 1. Record approved requirements and architecture
  - Define EARS acceptance criteria, non-goals, package boundaries, and safety.
  - _Requirements: R1-R8_

- [x] 2. Scaffold the publishable pure Dart package
  - Add package metadata, curated exports, license, support documents, and example.
  - _Requirements: R1, R8_

- [x] 3. Implement public values, policies, limits, and typed errors
  - Add value equality and nested standard JSON output.
  - Ensure all public entry points use typed failure boundaries.
  - _Requirements: R1, R2, R6_

- [x] 4. Implement safe metadata and container codecs
  - Add strict JSON/XMP parsing and TC260 validation.
  - Add bounded PNG/JPEG parsing and canonical writing.
  - _Requirements: R2-R4, R6_

- [x] 5. Implement read, embed, transplant, and verify orchestration
  - Enforce format, dimensions, propagation, conflict, and post-write checks.
  - _Requirements: R3-R6_

- [x] 6. Add package documentation and examples
  - Write synchronized English/Chinese guides and API Dartdoc.
  - Document preservation limits, error handling, and interoperability.
  - _Requirements: R6, R8_

- [x] 7. Build the reliability suite
  - Cover PNG/JPEG success/failure, policies, golden behavior, mutations, and
    every public error code with stable typed failures.
  - _Requirements: R2-R6, R8_

- [x] 8. Migrate the Flutter app
  - Add the path dependency, replace imports/types, and use transplant after
    visible watermark encoding while retaining final pixel decoding.
  - _Requirements: R7_

- [x] 9. Run quality gates and review final diff
  - Run package and app format/analyze/tests/builds plus publish dry-run.
  - Do not formally publish.
  - _Requirements: R7, R8_
