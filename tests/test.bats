#!/usr/bin/env bats

# Run locally with:
#   bats tests/test.bats --print-output-on-failure
# Filter a single test with:
#   bats tests/test.bats --filter 'sample stub is served'
#
# Design:
#   setup_file/teardown_file spin up a single throwaway DDEV project once
#   for the whole file. Each test that mutates WireMock runtime state calls
#   `ddev wiremock-reset --yes` in its setup, so tests stay independent
#   without paying the full DDEV start/stop cost per test.

setup_file() {
  set -eu -o pipefail

  export GITHUB_REPO=wazum/ddev-wiremock

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"

  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  # Persist TESTDIR across tests (bats resets exports between tests otherwise).
  echo "$TESTDIR" > "${BATS_FILE_TMPDIR}/testdir"

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  cd "${TESTDIR}"
  ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --project-type=generic >/dev/null

  # Echo sidecar for recording tests - must be in .ddev/ before `ddev start`.
  cp "${DIR}/tests/echo/docker-compose.echo.yaml" .ddev/docker-compose.echo.yaml

  ddev add-on get "${DIR}" >/dev/null
  ddev start -y >/dev/null
}

teardown_file() {
  ddev delete -Oy "test-$(basename "wazum/ddev-wiremock")" >/dev/null 2>&1 || true
  if [ -f "${BATS_FILE_TMPDIR}/testdir" ]; then
    rm -rf "$(cat "${BATS_FILE_TMPDIR}/testdir")"
  fi
}

setup() {
  set -eu -o pipefail

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export PROJNAME="test-$(basename "wazum/ddev-wiremock")"
  export TESTDIR=$(cat "${BATS_FILE_TMPDIR}/testdir")
  cd "${TESTDIR}"
}

# Helper: reset WireMock state. Use in tests that add runtime stubs or
# issue requests that should not leak into later tests.
reset_wiremock() {
  ddev wiremock-reset --yes >/dev/null 2>&1 || true
}

@test "install places all project files" {
  assert_file_exist .ddev/docker-compose.wiremock.yaml
  assert_file_exist .ddev/wiremock/mappings/sample.json
  assert_file_exist .ddev/wiremock/mappings/.gitkeep
  assert_file_exist .ddev/wiremock/__files/.gitkeep
  assert_file_exist .ddev/wiremock/README.md
  assert_file_exist .ddev/commands/host/wiremock-reset
  assert_file_exist .ddev/commands/host/wiremock-mappings
  assert_file_exist .ddev/commands/host/wiremock-requests
  assert_file_exist .ddev/commands/host/wiremock-logs
  assert_file_exist .ddev/commands/host/wiremock-record
  assert_file_exist .ddev/commands/host/wiremock-record-stop
  assert_file_exist .ddev/commands/host/wiremock-snapshot
  assert_file_exist .ddev/.env.wiremock
}

@test "wiremock service starts" {
  run bash -c "ddev describe -j | docker run -i --rm ddev/ddev-utilities jq -r '.raw.services.wiremock.status'"
  assert_success
  assert_output "running"
}

@test "wiremock container reports healthy to docker" {
  run bash -c "docker inspect --format '{{.State.Health.Status}}' ddev-${PROJNAME}-wiremock"
  assert_success
  assert_output "healthy"
}

@test "public URL serves WireMock admin" {
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/__admin/health"
  assert_success
  assert_output --partial "Wiremock is ok"
}

@test "sample stub is served" {
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/sample"
  assert_success
  assert_output --partial "Hello from ddev-wiremock"
}

@test "wiremock-logs prints WireMock container output" {
  run ddev wiremock-logs
  assert_success
  assert_output --partial "WireMock"
}

@test "wiremock-logs --help prints usage" {
  run ddev wiremock-logs --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "wiremock-logs"
}

@test "wiremock-mappings lists stubs in compact form" {
  reset_wiremock
  run ddev wiremock-mappings
  assert_success
  assert_output --partial "UUID"
  assert_output --partial "METHOD"
  assert_output --partial "00000000-0000-0000-0000-000000000001"
  assert_output --partial "GET"
  assert_output --partial "/sample"
}

@test "wiremock-mappings --json outputs full JSON" {
  run ddev wiremock-mappings --json
  assert_success
  assert_output --partial '"mappings"'
  assert_output --partial "00000000-0000-0000-0000-000000000001"
}

@test "wiremock-mappings --id fetches a single stub as JSON" {
  run ddev wiremock-mappings --id 00000000-0000-0000-0000-000000000001
  assert_success
  assert_output --partial "Hello from ddev-wiremock"
  assert_output --partial '"status": 200'
}

@test "wiremock-mappings --help prints usage" {
  run ddev wiremock-mappings --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--id"
  assert_output --partial "--json"
}

@test "wiremock-requests shows recent journal entries after a request" {
  reset_wiremock
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/sample"
  assert_success

  run ddev wiremock-requests
  assert_success
  assert_output --partial "TIME"
  assert_output --partial "METHOD"
  assert_output --partial "STATUS"
  assert_output --partial "GET"
  assert_output --partial "200"
  assert_output --partial "/sample"
}

@test "wiremock-requests marks unmatched requests in default output" {
  reset_wiremock
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/never-stubbed-xyz" || true

  run ddev wiremock-requests --limit 50
  assert_success
  assert_output --partial "/never-stubbed-xyz"
  assert_output --partial "unmatched"
}

@test "wiremock-requests --unmatched filters to unmatched" {
  reset_wiremock
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/never-stubbed-path-xyz" || true

  run ddev wiremock-requests --unmatched
  assert_success
  assert_output --partial "/never-stubbed-path-xyz"
}

@test "wiremock-requests --json outputs full JSON" {
  reset_wiremock
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/sample"
  assert_success

  run ddev wiremock-requests --json
  assert_success
  assert_output --partial '"requests"'
}

@test "wiremock-requests --limit rejects invalid values" {
  run ddev wiremock-requests --limit -5
  assert_failure
  assert_output --partial "error"
}

@test "wiremock-requests --help prints usage" {
  run ddev wiremock-requests --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--limit"
  assert_output --partial "--unmatched"
}

@test "wiremock-reset clears runtime stubs and journal but keeps file-backed stubs" {
  reset_wiremock
  # Add a runtime-only stub.
  run ddev exec "curl -fsS -X POST -H 'Content-Type: application/json' -d '{\"request\":{\"method\":\"GET\",\"urlPath\":\"/transient\"},\"response\":{\"status\":200,\"body\":\"transient\"}}' http://wiremock:8080/__admin/mappings"
  assert_success

  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/transient"
  assert_success
  assert_output --partial "transient"

  run ddev wiremock-reset --yes
  assert_success
  assert_output --partial "WireMock reset"

  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/transient"
  assert_failure

  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/sample"
  assert_success
  assert_output --partial "Hello from ddev-wiremock"
}

@test "wiremock-reset without --yes aborts when user says no" {
  run bash -c 'echo n | ddev wiremock-reset'
  assert_success
  assert_output --partial "aborted"
}

@test "wiremock-reset --help prints usage" {
  run ddev wiremock-reset --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--yes"
}

@test "wiremock-record without an upstream URL fails with usage" {
  run ddev wiremock-record
  assert_failure
  assert_output --partial "missing upstream URL"
}

@test "wiremock-record rejects extra arguments" {
  run ddev wiremock-record http://echo:8080 extra
  assert_failure
  assert_output --partial "too many"
}

@test "wiremock-record and wiremock-record-stop capture stubs from the echo sidecar" {
  reset_wiremock
  # Count existing stub files so we can diff.
  before=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')

  run ddev wiremock-record http://echo:8080
  assert_success
  assert_output --partial "Recording started"
  assert_output --partial "http://echo:8080"

  # Issue a request through WireMock - it proxies to echo and records it.
  run curl -sf -k -H "X-Record-Test: true" "https://${PROJNAME}.ddev.site:8443/recorded-path"
  assert_success

  run ddev wiremock-record-stop
  assert_success
  assert_output --partial "Recording stopped"
  assert_output --partial "stubs written"

  # At least one new stub file was created.
  after=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -gt "$before" ]
}

@test "wiremock-record --help prints usage" {
  run ddev wiremock-record --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "upstream-url"
}

@test "wiremock-record-stop --help prints usage" {
  run ddev wiremock-record-stop --help
  assert_success
  assert_output --partial "Usage:"
}
