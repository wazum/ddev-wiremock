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
