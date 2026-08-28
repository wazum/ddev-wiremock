# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
semantic versioning.

## [Unreleased]

### Added
- `ddev wiremock-proxy <url>` - pass unstubbed requests through to a real
  upstream for partial mocking. `--off` removes the proxy. Nothing is
  written to disk.
- `ddev wiremock-add --delay MS` - stub a slow response, for testing
  client timeouts and retries.
- `ddev wiremock-add --body @FILE` and `--body -` - read the response body
  from a file or from stdin instead of a shell argument.
- `WIREMOCK_ARGS` in `.env.wiremock` - extra WireMock CLI flags appended
  to the container command.

### Fixed
- Recording and snapshots no longer capture the `Authorization` header
  into stub request matchers. Recorded stubs embedded the caller's token,
  which leaked it into the repository and made the stub match for that
  one token only.
- `wiremock-add` and `wiremock-record` work from any subdirectory of the
  project.
- `wiremock-add` with a query string now writes a stub that can match
  (`url` instead of `urlPath`).
- `wiremock-add --body` without a value fails with a usage error instead
  of exiting silently.
- `wiremock-record` rejects an upstream URL without a scheme, and no
  longer starts a throwaway Docker container to resolve the project
  hostname.

## [0.2.0] - 2026-04-21

### Added
- `ddev wiremock-add <METHOD> <PATH>` - scaffold a stub JSON file.
  Flags: `--status`, `--body`, `--content-type`, `--force`.
- `ddev wiremock-reload` - re-read stub files without restarting the
  container; preserves the request journal.

### Fixed
- Install reliability on macOS. Web-container env vars now ship via a
  static `config.wiremock.yaml` instead of being injected through
  `ddev config` at install time.

## [0.1.0] - 2026-04-21

Initial release.

### Added
- WireMock 3 service (`wiremock/wiremock:3x`) exposed through the DDEV
  router at `https://<project>.ddev.site:8443`.
- Configurable ports via `.env.wiremock` (`WIREMOCK_HTTP_PORT`,
  `WIREMOCK_HTTPS_PORT`, `WIREMOCK_TAG`).
- Web-container env vars `DDEV_WIREMOCK_URL` and `DDEV_WIREMOCK_ADMIN_URL`.
- Seven host commands: `wiremock-mappings`, `wiremock-requests`,
  `wiremock-logs`, `wiremock-reset`, `wiremock-record`,
  `wiremock-record-stop`, `wiremock-snapshot`. All take `--help`.
- Committed stub directory `.ddev/wiremock/mappings/` and `__files/` with a
  sample stub.
- Bats test suite (30 tests) with a `mendhak/http-https-echo` sidecar for
  recording workflows.
- GitHub Actions CI (lint + bats).

[Unreleased]: https://github.com/wazum/ddev-wiremock/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/wazum/ddev-wiremock/releases/tag/v0.2.0
[0.1.0]: https://github.com/wazum/ddev-wiremock/releases/tag/v0.1.0
