# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- [#10](https://github.com/numbata/danger-pr-comment/pull/10): Automate release changelog preparation and update workflow tag references in the README, installer, and installer specs - [@dblock](https://github.com/dblock).

## [0.1.1] - 2026-10-21

### Added

- [#2](https://github.com/numbata/danger-pr-comment/pull/2): Add automated releases using RubyGems Trusted Publishing, with release validation, GitHub release creation, and next development version preparation - [@dblock](https://github.com/dblock).
- [#6](https://github.com/numbata/danger-pr-comment/pull/6): Setup danger workflows as an example - [@numbata](https://github.com/numbata).
- [#1](https://github.com/numbata/danger-pr-comment/pull/1): Add comprehensive test suite with RSpec, Rubocop, and CI - [@dblock](https://github.com/dblock).
* [#4](https://github.com/numbata/danger-pr-comment/pull/4): Improve install script documentation - [@dblock](https://github.com/dblock).

### Fixed

- [#7](https://github.com/numbata/danger-pr-comment/pull/7): Add required permissions to workflow examples and templates - [@numbata](https://github.com/numbata).

## [0.1.0] - 2024-01-01

### Added

- Initial release
- `DangerPrComment::Reporter` class for JSON report generation
- Shared Dangerfile for automatic report export via `at_exit` hook
- Reusable GitHub Actions workflow `danger-run.yml` for running Danger
- Reusable GitHub Actions workflow `danger-comment.yml` for posting PR comments
- Installation script `scripts/install-workflows.sh`
