#!/usr/bin/env bats

# Removal test lives in its own file so it has its own setup_file.
# `ddev add-on remove wiremock` destroys the installation, so it cannot
# run in the shared-project harness used by tests/test.bats.

setup_file() {
  set -eu -o pipefail

  export GITHUB_REPO=wazum/ddev-wiremock

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"

  export ADDON_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJECT_NAME="test-$(basename "${GITHUB_REPO}")-removal"

  mkdir -p ~/tmp
  export TEST_DIR=$(mktemp -d ~/tmp/${PROJECT_NAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  echo "$TEST_DIR" > "${BATS_FILE_TMPDIR}/test_dir"

  ddev delete -Oy "${PROJECT_NAME}" >/dev/null 2>&1 || true

  cd "${TEST_DIR}"
  ddev config --project-name="${PROJECT_NAME}" --project-tld=ddev.site --project-type=generic >/dev/null
  ddev add-on get "${ADDON_DIR}" >/dev/null
}

teardown_file() {
  ddev delete -Oy "test-$(basename "wazum/ddev-wiremock")-removal" >/dev/null 2>&1 || true
  if [ -f "${BATS_FILE_TMPDIR}/test_dir" ]; then
    rm -rf "$(cat "${BATS_FILE_TMPDIR}/test_dir")"
  fi
}

setup() {
  set -eu -o pipefail
  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export TEST_DIR=$(cat "${BATS_FILE_TMPDIR}/test_dir")
  cd "${TEST_DIR}"
}

@test "add-on remove preserves user-authored stubs and env" {
  # Drop a user-authored stub file (not tracked by DDEV).
  cat > .ddev/wiremock/mappings/user.json <<'JSON'
{
  "request": {"method": "GET", "urlPath": "/user"},
  "response": {"status": 200, "jsonBody": {"owner": "user"}}
}
JSON
  assert_file_exist .ddev/wiremock/mappings/user.json

  # Modify the seeded .env.wiremock so it loses the #ddev-generated marker.
  # This should cause removal to skip it (user-modified).
  sed -i '' '/^#ddev-generated$/d' .ddev/.env.wiremock 2>/dev/null \
    || sed -i '/^#ddev-generated$/d' .ddev/.env.wiremock

  run ddev add-on remove wiremock
  assert_success

  # User stub survives.
  assert_file_exist .ddev/wiremock/mappings/user.json

  # The add-on's compose file is removed (had the #ddev-generated marker).
  assert_file_not_exist .ddev/docker-compose.wiremock.yaml

  # Command scripts are removed.
  assert_file_not_exist .ddev/commands/host/wiremock-reset

  # User-modified .env.wiremock is preserved.
  assert_file_exist .ddev/.env.wiremock
}
