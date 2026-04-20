<!-- #ddev-generated -->
# `.ddev/wiremock/` layout

This directory is mounted into the WireMock container at `/home/wiremock`.

- `mappings/*.json` - stub mappings WireMock serves. One stub per file.
- `__files/` - binary or large text response bodies referenced by mappings via
  `"bodyFileName": "<name>"`.

## Commit policy

Everything here is committed. Stubs are shared team state. Use `git diff` to
review changes after `ddev wiremock-record` or `ddev wiremock-snapshot` before
committing.

If you want recordings to stay local, add `.gitignore` entries yourself. This
add-on ships none.

## Stub syntax

See the official WireMock reference:
<https://wiremock.org/docs/stubbing/>.

## Removal

`ddev add-on remove wiremock` preserves files in this directory by default.
Delete the directory manually if you no longer need the stubs.
