# ddev-wiremock

Run [WireMock](https://wiremock.org/) as a DDEV service, with host commands
that wrap the admin API.

[![tests](https://github.com/wazum/ddev-wiremock/actions/workflows/tests.yml/badge.svg)](https://github.com/wazum/ddev-wiremock/actions/workflows/tests.yml)
[![lint](https://github.com/wazum/ddev-wiremock/actions/workflows/lint.yml/badge.svg)](https://github.com/wazum/ddev-wiremock/actions/workflows/lint.yml)
[![release](https://img.shields.io/github/v/release/wazum/ddev-wiremock?sort=semver)](https://github.com/wazum/ddev-wiremock/releases)

## Install

```bash
ddev add-on get wazum/ddev-wiremock
ddev restart
```

WireMock is then reachable at `https://<project>.ddev.site:8443` with the
admin API under `/__admin`. Stubs live under `.ddev/wiremock/mappings/`.

## Commands

| Command | What it does |
|---|---|
| `ddev wiremock-mappings` | List active stubs. `--id <uuid>` fetches one, `--json` dumps full JSON. |
| `ddev wiremock-requests` | Show the request journal. `--limit N`, `--unmatched`, `--json`. |
| `ddev wiremock-logs` | Tail the WireMock container logs. Passes flags through to `ddev logs`. |
| `ddev wiremock-reset` | Wipe runtime stubs and the request journal. File-backed stubs reload on next start. |
| `ddev wiremock-record <url>` | Start recording against an upstream URL. |
| `ddev wiremock-record-stop` | Stop recording; writes stubs into `mappings/`. |
| `ddev wiremock-snapshot` | Convert the current journal into stubs (no upstream needed). |

All commands take `--help`.

## Stubs

Stub files live in `.ddev/wiremock/mappings/` (one JSON per stub), response
bodies in `.ddev/wiremock/__files/`. Everything there is committed - stubs
are shared team state.

Stub syntax: <https://wiremock.org/docs/stubbing/>.

## Recording

```bash
ddev wiremock-record https://api.example.com
# issue requests through https://<project>.ddev.site:8443 ...
ddev wiremock-record-stop
git diff .ddev/wiremock/mappings/
```

`ddev wiremock-snapshot` does the same after the fact, using only the
current request journal.

## Environment and configuration

Injected into the DDEV web container:

| Variable | Value |
|---|---|
| `DDEV_WIREMOCK_URL` | `http://wiremock:8080` |
| `DDEV_WIREMOCK_ADMIN_URL` | `http://wiremock:8080/__admin` |

Editable in `.ddev/.env.wiremock`:

| Key | Default | Effect |
|---|---|---|
| `WIREMOCK_TAG` | `3x` | WireMock image tag. |
| `WIREMOCK_HTTP_PORT` | `8080` | Router port for HTTP. |
| `WIREMOCK_HTTPS_PORT` | `8443` | Router port for HTTPS. |

## Remove

```bash
ddev add-on remove wiremock
```

User-authored files under `.ddev/wiremock/` are preserved. Delete that
directory manually if you no longer need the stubs.

## License

Apache-2.0. Copyright 2026 Wolfgang Klinger. WireMock is a separate project;
see <https://wiremock.org/> for its own license and credits.
