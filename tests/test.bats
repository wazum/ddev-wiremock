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
  export PROJECT_NAME="test-$(basename "${GITHUB_REPO}")"

  mkdir -p ~/tmp
  export TEST_DIR=$(mktemp -d ~/tmp/${PROJECT_NAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true

  # Persist TEST_DIR across tests (bats resets exports between tests otherwise).
  echo "$TEST_DIR" > "${BATS_FILE_TMPDIR}/test_dir"

  ddev delete -Oy "${PROJECT_NAME}" >/dev/null 2>&1 || true

  cd "${TEST_DIR}"
  ddev config --project-name="${PROJECT_NAME}" --project-tld=ddev.site --project-type=generic >/dev/null

  # Echo sidecar for recording tests - must be in .ddev/ before `ddev start`.
  cp "${DIR}/tests/echo/docker-compose.echo.yaml" .ddev/docker-compose.echo.yaml

  ddev add-on get "${DIR}" >/dev/null
  ddev start -y >/dev/null
}

teardown_file() {
  ddev delete -Oy "test-$(basename "wazum/ddev-wiremock")" >/dev/null 2>&1 || true
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

  export PROJECT_NAME="test-$(basename "wazum/ddev-wiremock")"
  export TEST_DIR=$(cat "${BATS_FILE_TMPDIR}/test_dir")
  cd "${TEST_DIR}"
}

# Helper: reset WireMock state. Use in tests that add runtime stubs or
# issue requests that should not leak into later tests.
reset_wiremock() {
  ddev wiremock-reset --yes >/dev/null 2>&1 || true
}

# Helper: print the request-header matcher names of every stub file, lowercased.
stub_request_header_names() {
  python3 - <<'PY'
import glob
import json

for path in sorted(glob.glob(".ddev/wiremock/mappings/*.json")):
    with open(path) as fp:
        for name in json.load(fp).get("request", {}).get("headers", {}):
            print(name.lower())
PY
}

# Helper: print the rendered command line of the wiremock compose service.
wiremock_service_command() {
  ddev debug compose-config | python3 -c '
import sys
import yaml

command = yaml.safe_load(sys.stdin)["services"]["wiremock"]["command"]
print(command if isinstance(command, str) else " ".join(command))
'
}

@test "install places all project files" {
  assert_file_exist .ddev/docker-compose.wiremock.yaml
  assert_file_exist .ddev/config.wiremock.yaml
  assert_file_exist .ddev/wiremock/mappings/sample.json
  assert_file_exist .ddev/wiremock/mappings/.gitkeep
  assert_file_exist .ddev/wiremock/__files/.gitkeep
  assert_file_exist .ddev/wiremock/README.md
  assert_file_exist .ddev/commands/host/wiremock-add
  assert_file_exist .ddev/commands/host/wiremock-logs
  assert_file_exist .ddev/commands/host/wiremock-mappings
  assert_file_exist .ddev/commands/host/wiremock-proxy
  assert_file_exist .ddev/commands/host/wiremock-record
  assert_file_exist .ddev/commands/host/wiremock-record-stop
  assert_file_exist .ddev/commands/host/wiremock-reload
  assert_file_exist .ddev/commands/host/wiremock-requests
  assert_file_exist .ddev/commands/host/wiremock-reset
  assert_file_exist .ddev/commands/host/wiremock-snapshot
  assert_file_exist .ddev/.env.wiremock
}

@test "install writes addon manifest" {
  assert_file_exist .ddev/addon-metadata/wiremock/manifest.yaml
  run grep "name: wiremock" .ddev/addon-metadata/wiremock/manifest.yaml
  assert_success
}

@test "web container has DDEV_WIREMOCK_* env vars" {
  run ddev exec "env | grep -E '^DDEV_WIREMOCK_'"
  assert_success
  assert_output --partial "DDEV_WIREMOCK_URL=http://wiremock:8080"
  assert_output --partial "DDEV_WIREMOCK_ADMIN_URL=http://wiremock:8080/__admin"
}

@test "wiremock service starts" {
  run bash -c "ddev describe -j | docker run -i --rm ddev/ddev-utilities jq -r '.raw.services.wiremock.status'"
  assert_success
  assert_output "running"
}

@test "wiremock container reports healthy to docker" {
  run bash -c "docker inspect --format '{{.State.Health.Status}}' ddev-${PROJECT_NAME}-wiremock"
  assert_success
  assert_output "healthy"
}

@test "public URL serves WireMock admin" {
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/__admin/health"
  assert_success
  assert_output --partial "Wiremock is ok"
}

@test "sample stub is served" {
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
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
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
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
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/never-stubbed-xyz" || true

  run ddev wiremock-requests --limit 50
  assert_success
  assert_output --partial "/never-stubbed-xyz"
  assert_output --partial "unmatched"
}

@test "wiremock-requests --unmatched filters to unmatched" {
  reset_wiremock
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/never-stubbed-path-xyz" || true

  run ddev wiremock-requests --unmatched
  assert_success
  assert_output --partial "/never-stubbed-path-xyz"
}

@test "wiremock-requests --json outputs full JSON" {
  reset_wiremock
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
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

  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/transient"
  assert_success
  assert_output --partial "transient"

  run ddev wiremock-reset --yes
  assert_success
  assert_output --partial "WireMock reset"

  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/transient"
  assert_failure

  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
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

@test "wiremock-record rejects an upstream URL without a scheme" {
  run ddev wiremock-record api.example.com
  assert_failure
  assert_output --partial "must start with http"
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
  run curl -sf -k -H "X-Record-Test: true" "https://${PROJECT_NAME}.ddev.site:8443/recorded-path"
  assert_success

  run ddev wiremock-record-stop
  assert_success
  assert_output --partial "Recording stopped"
  assert_output --partial "stubs written"

  # At least one new stub file was created.
  after=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -gt "$before" ]
}

@test "recorded stubs do not match on the Authorization header" {
  reset_wiremock

  run ddev wiremock-record http://echo:8080
  assert_success

  run curl -sf -k -H "Authorization: Bearer secret-token-xyz" \
    "https://${PROJECT_NAME}.ddev.site:8443/auth-capture-test"
  assert_success

  run ddev wiremock-record-stop
  assert_success

  run stub_request_header_names
  assert_success
  refute_output --partial "authorization"

  rm -f .ddev/wiremock/mappings/*auth-capture-test*.json
}

@test "wiremock-record reads the HTTPS port from the project root, not the current directory" {
  mkdir -p sub
  cp .ddev/.env.wiremock "${BATS_TEST_TMPDIR}/env.bak"
  printf '#ddev-generated\nWIREMOCK_TAG=3x\nWIREMOCK_HTTP_PORT=8080\nWIREMOCK_HTTPS_PORT=9443\n' \
    > .ddev/.env.wiremock

  run bash -c "cd sub && ddev wiremock-record http://echo:8080"
  saved_status="$status"
  saved_output="$output"

  ddev wiremock-record-stop >/dev/null 2>&1 || true
  cp "${BATS_TEST_TMPDIR}/env.bak" .ddev/.env.wiremock
  rmdir sub

  [ "$saved_status" -eq 0 ]
  [[ "$saved_output" == *"https://${PROJECT_NAME}.ddev.site:9443"* ]]
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

@test "wiremock-snapshot runs and reports a count" {
  reset_wiremock
  # Issue one request so the journal is not empty.
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
  assert_success

  run ddev wiremock-snapshot
  assert_success
  assert_output --partial "Snapshot complete"
  # Count is always a non-negative integer; the exact value depends on whether
  # the matched request is considered new by WireMock's snapshot heuristics.
  assert_output --regexp '[0-9]+ stubs written'
}

@test "wiremock-snapshot persists new stubs from proxied requests" {
  reset_wiremock
  before=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')

  # Set up a proxy stub that forwards all unmatched paths to the echo sidecar.
  # WireMock's snapshot endpoint only persists stubs when it has a real
  # upstream response to work from; unmatched 404s are filtered out.
  run ddev exec "curl -fsS -X POST -H 'Content-Type: application/json' -d '{\"priority\":10,\"request\":{\"method\":\"ANY\",\"urlPathPattern\":\"/proxy/.+\"},\"response\":{\"proxyBaseUrl\":\"http://echo:8080\"}}' http://wiremock:8080/__admin/mappings"
  assert_success

  # Issue a request that gets proxied to echo.
  run curl -sf -k -H "Authorization: Bearer snapshot-secret-xyz" \
    "https://${PROJECT_NAME}.ddev.site:8443/proxy/some-endpoint"
  assert_success

  run ddev wiremock-snapshot
  assert_success
  assert_output --partial "Snapshot complete"

  after=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -gt "$before" ]

  run stub_request_header_names
  assert_success
  refute_output --partial "authorization"

  rm -f .ddev/wiremock/mappings/*some-endpoint*.json
}

@test "wiremock-snapshot rejects extra arguments" {
  run ddev wiremock-snapshot extra
  assert_failure
  assert_output --partial "unexpected argument"
}

@test "wiremock-snapshot --help prints usage" {
  run ddev wiremock-snapshot --help
  assert_success
  assert_output --partial "Usage:"
}

@test "wiremock-proxy forwards unstubbed paths upstream without writing stubs" {
  reset_wiremock
  before=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')

  run ddev wiremock-proxy http://echo:8080
  assert_success
  assert_output --partial "http://echo:8080"

  # Unstubbed path reaches the echo sidecar instead of answering 404.
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/proxied-through"
  assert_success
  assert_output --partial "/proxied-through"

  # File-backed stubs still win over the proxy.
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/sample"
  assert_success
  assert_output --partial "Hello from ddev-wiremock"

  # Unlike recording, proxying persists nothing.
  after=$(ls .ddev/wiremock/mappings/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$after" -eq "$before" ]

  run ddev wiremock-proxy --off
  assert_success
  assert_output --partial "Proxy removed"

  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/proxied-through"
  assert_failure
}

@test "wiremock-proxy --off without an active proxy says so" {
  run ddev wiremock-proxy --off
  assert_success
  assert_output --partial "No proxy"
}

@test "wiremock-proxy requires an upstream URL" {
  run ddev wiremock-proxy
  assert_failure
  assert_output --partial "missing upstream URL"
}

@test "wiremock-proxy rejects an upstream URL without a scheme" {
  run ddev wiremock-proxy api.example.com
  assert_failure
  assert_output --partial "must start with http"
}

@test "wiremock-proxy --help prints usage" {
  run ddev wiremock-proxy --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--off"
}

@test "wiremock-add writes a stub and wiremock-reload makes it live" {
  reset_wiremock
  rm -f .ddev/wiremock/mappings/get-added-stub.json

  run ddev wiremock-add GET /added/stub
  assert_success
  assert_output --partial "Wrote"
  assert_file_exist .ddev/wiremock/mappings/get-added-stub.json

  run ddev wiremock-reload
  assert_success
  assert_output --partial "reloaded"

  run curl -s -k -w '\n%{http_code}' "https://${PROJECT_NAME}.ddev.site:8443/added/stub"
  assert_success
  assert_output --partial "200"

  rm -f .ddev/wiremock/mappings/get-added-stub.json
}

@test "wiremock-add honours --status and --body" {
  reset_wiremock
  rm -f .ddev/wiremock/mappings/post-items.json

  run ddev wiremock-add POST /items --status 201 --body '{"id":99}'
  assert_success
  assert_file_exist .ddev/wiremock/mappings/post-items.json

  run cat .ddev/wiremock/mappings/post-items.json
  assert_success
  assert_output --partial '"status": 201'
  assert_output --partial '"id": 99'

  ddev wiremock-reload >/dev/null
  run curl -s -k -X POST -w '\n%{http_code}' "https://${PROJECT_NAME}.ddev.site:8443/items"
  assert_success
  assert_output --partial "201"
  assert_output --partial '"id":99'

  rm -f .ddev/wiremock/mappings/post-items.json
}

@test "wiremock-add refuses to overwrite without --force" {
  reset_wiremock
  rm -f .ddev/wiremock/mappings/get-duplicate.json

  run ddev wiremock-add GET /duplicate
  assert_success

  run ddev wiremock-add GET /duplicate
  assert_failure
  assert_output --partial "already exists"

  run ddev wiremock-add GET /duplicate --force --body '{"v":2}'
  assert_success
  run cat .ddev/wiremock/mappings/get-duplicate.json
  assert_output --partial '"v": 2'

  rm -f .ddev/wiremock/mappings/get-duplicate.json
}

@test "wiremock-add stubs a path with a query string" {
  reset_wiremock
  rm -f .ddev/wiremock/mappings/get-search-q-foo.json

  run ddev wiremock-add GET '/search?q=foo' --body '{"hit":true}'
  assert_success
  assert_file_exist .ddev/wiremock/mappings/get-search-q-foo.json

  ddev wiremock-reload >/dev/null
  run curl -sf -k "https://${PROJECT_NAME}.ddev.site:8443/search?q=foo"
  assert_success
  assert_output --partial '"hit":true'

  rm -f .ddev/wiremock/mappings/get-search-q-foo.json
}

@test "wiremock-add works from a project subdirectory" {
  rm -f .ddev/wiremock/mappings/get-from-subdir.json
  mkdir -p sub/deeper

  run bash -c "cd sub/deeper && ddev wiremock-add GET /from-subdir"
  assert_success
  assert_file_exist .ddev/wiremock/mappings/get-from-subdir.json

  rm -rf sub
  rm -f .ddev/wiremock/mappings/get-from-subdir.json
}

@test "wiremock-add reports a clear error when --body has no value" {
  run ddev wiremock-add GET /no-body-value --body
  assert_failure
  assert_output --partial "--body requires"
}

@test "wiremock-add --delay makes the stub respond slowly" {
  reset_wiremock
  rm -f .ddev/wiremock/mappings/get-slow.json

  run ddev wiremock-add GET /slow --delay 500
  assert_success

  ddev wiremock-reload >/dev/null
  run curl -sf -k -o /dev/null -w '%{time_total}' "https://${PROJECT_NAME}.ddev.site:8443/slow"
  assert_success
  elapsed="$output"

  run awk -v seconds="$elapsed" 'BEGIN { exit !(seconds >= 0.4) }'
  assert_success

  rm -f .ddev/wiremock/mappings/get-slow.json
}

@test "wiremock-add --delay rejects non-numeric values" {
  run ddev wiremock-add GET /slow-bad --delay abc
  assert_failure
  assert_output --partial "--delay requires"
}

@test "wiremock-add reads --body from a file" {
  rm -f .ddev/wiremock/mappings/get-from-file.json
  echo '{"from":"file"}' > "${BATS_TEST_TMPDIR}/payload.json"

  run ddev wiremock-add GET /from-file --body "@${BATS_TEST_TMPDIR}/payload.json"
  assert_success

  run cat .ddev/wiremock/mappings/get-from-file.json
  assert_output --partial '"from": "file"'

  rm -f .ddev/wiremock/mappings/get-from-file.json
}

@test "wiremock-add resolves a relative --body file against the current directory" {
  rm -f .ddev/wiremock/mappings/get-relative-body.json
  mkdir -p sub
  echo '{"from":"subdir"}' > sub/payload.json

  run bash -c "cd sub && ddev wiremock-add GET /relative-body --body @payload.json"
  assert_success

  run cat .ddev/wiremock/mappings/get-relative-body.json
  assert_output --partial '"from": "subdir"'

  rm -rf sub
  rm -f .ddev/wiremock/mappings/get-relative-body.json
}

@test "wiremock-add reads --body from stdin" {
  rm -f .ddev/wiremock/mappings/get-from-stdin.json

  run bash -c "echo '{\"from\":\"stdin\"}' | ddev wiremock-add GET /from-stdin --body -"
  assert_success

  run cat .ddev/wiremock/mappings/get-from-stdin.json
  assert_output --partial '"from": "stdin"'

  rm -f .ddev/wiremock/mappings/get-from-stdin.json
}

@test "wiremock-add reports a missing --body file" {
  run ddev wiremock-add GET /missing-file --body @does-not-exist.json
  assert_failure
  assert_output --partial "not found"
}

@test "wiremock-add rejects invalid JSON bodies" {
  run ddev wiremock-add GET /bad --body 'not-json'
  assert_failure
  assert_output --partial "must be valid JSON"
}

@test "wiremock-add rejects unsupported HTTP methods" {
  run ddev wiremock-add FROBNICATE /x
  assert_failure
  assert_output --partial "unsupported method"
}

@test "wiremock-add requires method and path" {
  run ddev wiremock-add
  assert_failure
  assert_output --partial "required"
}

@test "wiremock-add --help prints usage" {
  run ddev wiremock-add --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--status"
  assert_output --partial "--body"
}

@test "wiremock-reload rejects extra arguments" {
  run ddev wiremock-reload extra
  assert_failure
  assert_output --partial "unexpected argument"
}

@test "wiremock-reload --help prints usage" {
  run ddev wiremock-reload --help
  assert_success
  assert_output --partial "Usage:"
}

@test "WIREMOCK_ARGS from .env.wiremock reaches the container command line" {
  cp .ddev/.env.wiremock "${BATS_TEST_TMPDIR}/env.bak"
  printf '#ddev-generated\nWIREMOCK_TAG=3x\nWIREMOCK_HTTP_PORT=8080\nWIREMOCK_HTTPS_PORT=8443\nWIREMOCK_ARGS=--max-request-journal-entries=7\n' \
    > .ddev/.env.wiremock

  run wiremock_service_command
  saved_status="$status"
  saved_output="$output"

  cp "${BATS_TEST_TMPDIR}/env.bak" .ddev/.env.wiremock

  [ "$saved_status" -eq 0 ]
  [[ "$saved_output" == *"--global-response-templating"* ]]
  [[ "$saved_output" == *"--max-request-journal-entries=7"* ]]
}
