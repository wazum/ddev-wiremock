#!/usr/bin/env bats

# Run locally with:
#   bats tests/test.bats --show-output-of-passing-tests --verbose-run
# Filter a single test with:
#   bats tests/test.bats --filter 'sample stub is served'

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=wazum/ddev-wiremock

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"

  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true

  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site --project-type=generic
  assert_success

  # Echo sidecar for recording tests - must be in .ddev/ before `ddev start`.
  cp "${DIR}/tests/echo/docker-compose.echo.yaml" .ddev/docker-compose.echo.yaml

  run ddev add-on get "${DIR}"
  assert_success

  run ddev start -y
  assert_success
}

teardown() {
  cd "${HOME}"
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  rm -rf "${TESTDIR}"
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
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/never-stubbed-xyz" || true

  run ddev wiremock-requests --limit 50
  assert_success
  assert_output --partial "/never-stubbed-xyz"
  assert_output --partial "unmatched"
}

@test "wiremock-requests --unmatched filters to unmatched" {
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/never-stubbed-path-xyz" || true

  run ddev wiremock-requests --unmatched
  assert_success
  assert_output --partial "/never-stubbed-path-xyz"
}

@test "wiremock-requests --json outputs full JSON" {
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
  # Add a runtime-only stub.
  run ddev exec "curl -fsS -X POST -H 'Content-Type: application/json' -d '{\"request\":{\"method\":\"GET\",\"urlPath\":\"/transient\"},\"response\":{\"status\":200,\"body\":\"transient\"}}' http://wiremock:8080/__admin/mappings"
  assert_success

  # Confirm it's live.
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/transient"
  assert_success
  assert_output --partial "transient"

  # Reset (skip prompt).
  run ddev wiremock-reset --yes
  assert_success
  assert_output --partial "WireMock reset"

  # The runtime stub is gone.
  run curl -sf -k "https://${PROJNAME}.ddev.site:8443/transient"
  assert_failure

  # The file-backed sample stub is reloaded automatically.
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
