# `cubrid-ini-fzf` Implementation Plan

## Goal

Build an executable command named `cubrid-ini-fzf` that:

1. targets `testdb` by default or a database supplied on the command line,
2. obtains the complete set of runtime-known `cubrid.conf` parameters with `cubrid paramdump`,
3. lets the user fuzzy-search and select one parameter,
4. accepts a replacement value,
5. writes that value to `$CUBRID/conf/cubrid.conf` through `ini.sh`, and
6. clearly tells the user that the affected processes must be restarted before the persistent setting is fully applied.

“All possible changes” will mean every parameter emitted by `paramdump`. `paramdump` provides parameter names and effective/default values, but not a complete enumeration of valid values or ranges, so the first version will not attempt value-domain validation.

## Evidence Gathered

- The local manual defines `cubrid paramdump [options] database_name`; `-S` selects standalone mode and `-C` selects client/server mode ([manual](</home/vimkim/gh/cubrid-manual/en/admin/admin_utils.rst:3437>)).
- `cubrid server status` lists running databases as `Server <name> (...)`; when none are running, this local build prints only the command heading and still exits successfully. Detection therefore must parse the output rather than depend only on its exit status ([manual](</home/vimkim/gh/cubrid-manual/en/admin/control.rst:562>)).
- The observed standalone output contains two groups—client records and server records—with lines such as `[C ] max_plan_cache_entries=1000 (1000)` and `[S ] max_clients=100 (100)`. This build emitted 272 tagged records, including duplicate names present in both groups.
- A `*` in the tag is possible, for example `[S*] task_worker=6 (-1)`, so the parser must accept `[C ]`, `[C*]`, `[S ]`, and `[S*]`.
- The installed `ini.sh` supports a write in the form `ini.sh -s SECTION CONFIG_FILE KEY VALUE`.
- `cubrid.conf` is located at `$CUBRID/conf/cubrid.conf`, and CUBRID supports `[common]`, `[@database]`, and `[standalone]` parameter sections ([manual](</home/vimkim/gh/cubrid-manual/en/admin/config.rst:426>)).
- The manual says persistent configuration changes require restarting both the database server and broker; the completion message must not imply that restarting only the server is sufficient for every client/server parameter ([manual](</home/vimkim/gh/cubrid-manual/en/admin/config.rst:122>)).

## Proposed User Flow

```text
cubrid-ini-fzf [--database DATABASE] [--section SECTION]
  -> validate environment and dependencies
  -> use database testdb and section common unless overridden
  -> verify that the target database is registered
  -> determine whether that exact database is running
  -> run paramdump in CS or SA mode
  -> fuzzy-search one deduplicated parameter
  -> prompt for its new value
  -> show database, section, parameter, old value, and new value
  -> confirm the edit
  -> back up cubrid.conf and update it with ini.sh
  -> verify the stored value and print restart guidance
```

Pressing `Ctrl-C` at the parameter picker, value prompt, or confirmation prompt must exit with status 130 and leave `cubrid.conf` unchanged. Cancelling the `fzf` picker with Escape should also exit without a write.

## Design Decisions

### 1. Command-line interface and database selection

- Support `cubrid-ini-fzf [--database DATABASE] [--section SECTION]` plus `-d`, `-s`, and `-h` short options.
- Default `DATABASE` to `testdb`.
- Default `SECTION` to `common`.
- Accept section names in the form expected by `ini.sh`, without square brackets: `common`, `standalone`, or `@<database>`. For example, `--section @testdb` updates `[@testdb]`.
- Reject unknown options, extra positional arguments, unsafe database names, and invalid section syntax before invoking CUBRID commands.
- Read `$CUBRID_DATABASES/databases.txt`, ignoring blank and comment lines, and verify that the requested database is registered. If it is absent, fail with a useful error before invoking `paramdump`.
- Parse `cubrid server status` once and compare complete database names, not substrings.
- If the requested database appears in the running set, invoke `cubrid paramdump <database>` (the requested normal/CS behavior).
- Otherwise invoke `cubrid paramdump -S <database>`.
- Capture output and exit status together. Never open the settings picker with partial output after a failed `paramdump`.

This makes a zero-argument run deterministic (`testdb` plus `[common]`) while retaining explicit overrides for other databases and sections. The database used by `paramdump` and the section receiving the edit are independent command-line choices; the confirmation summary must show both clearly.

### 2. Parameter parsing

- Accept only tagged parameter records matching the four observed tag forms.
- Split each record at the first `=` after the tag. The left side is the parameter name; keep the right side intact for display because values may contain quotes, spaces, commas, parentheses, or additional punctuation.
- Reject malformed or unsafe names; accepted names should match `[A-Za-z_][A-Za-z0-9_]*`.
- Deduplicate by parameter name. Aggregate its scope as `C`, `S`, or `C/S`; when both values exist, show both if they differ and prefer the server value as the edit summary’s current value.
- Preserve original order so the list remains stable across runs.
- Feed `fzf` a tab-separated internal record, but display only scope, parameter name, and current value. Search should cover at least the parameter name and current value.
- Abort with an explanatory error if parsing produces no parameters.

Do not parse `paramdump` by whitespace fields or by the final parenthesized value; either approach breaks valid string/list values.

### 3. Configuration target

Write to `[common]` by default. An explicit `--section` overrides the target, such as `--section @testdb` for a database-specific value or `--section standalone` for standalone utilities.

The concrete update call will be equivalent to:

```bash
ini.sh -s "$section" "$CUBRID/conf/cubrid.conf" "$parameter" -- "$new_value"
```

All arguments must be passed as quoted argv values. The `--` option terminator is required so valid negative settings such as `-1` are treated as values rather than `ini.sh` options. Do not use `eval`, construct a shell command string, or modify the INI file with `sed`/`awk`; `ini.sh` must perform the actual update.

An empty response at the value prompt will cancel the change. A user who intentionally wants an empty CUBRID string can enter `""` explicitly.

### 4. Running-server behavior

The tool will not stop a database automatically in the first version. Before writing a setting for a running database, it will:

1. explain that the current process continues using its existing effective value,
2. ask the user to confirm that they will stop/restart the affected database after the edit, and
3. cancel without writing if confirmation is declined.

After a successful write, print the relevant standard commands as guidance, for example `cubrid server stop <database>` and `cubrid server start <database>`, and mention that client-side changes may also require a broker restart. Do not run either command automatically.

### 5. Safe write and verification

- Require `$CUBRID` and `$CUBRID_DATABASES` to be set and resolve their referenced files explicitly.
- Require `cubrid`, `fzf`, and `ini.sh` on `PATH`; check `ini.sh` before any interactive work, as requested.
- Require the target `cubrid.conf` to exist and be writable.
- Immediately before editing, create a timestamped sibling backup while preserving file permissions.
- Invoke `ini.sh` exactly once for the write and honor its exit status.
- Read the parameter back with `ini.sh -s "$section" ...` and compare it with the requested value.
- On a failed write or failed verification, keep the backup, report its path, and exit nonzero. Do not silently claim success or automatically overwrite the file a second time.
- On success, print the updated file, section, key, value, and backup path.

## Implementation Structure

Create these files:

- `cubrid-ini-fzf` — Bash entry point and workflow.
- `tests/test-cubrid-ini-fzf.sh` — dependency-free shell test harness using temporary fixtures and stub commands.
- `README.md` — installation, dependencies, usage, database/section behavior, restart behavior, and limitations.

Keep the main script divided into small functions:

- `die` and `cleanup`
- `parse_arguments`
- `check_dependencies`
- `validate_environment`
- `validate_database_registration`
- `list_running_databases`
- `run_paramdump`
- `parse_parameters`
- `choose_parameter`
- `prompt_for_value`
- `confirm_change`
- `backup_and_update`
- `verify_update`

Use Bash explicitly because arrays, `[[ ... ]]`, `mapfile`, and predictable signal handling simplify safe parsing. Install a `trap` for `INT` that exits 130 and removes only tool-owned temporary files.

## Test Plan

Use stub `cubrid`, `fzf`, and `ini.sh` executables placed at the front of a temporary `PATH`. Each test gets isolated `CUBRID`, `CUBRID_DATABASES`, and configuration fixtures.

### Automated cases

1. Missing `ini.sh` fails before `cubrid server status`, `paramdump`, or `fzf` runs.
2. Missing `cubrid`, `fzf`, environment variables, database registry, or writable configuration produces a focused nonzero error.
3. A zero-argument run uses database `testdb` and INI section `common`.
4. `--database`, `-d`, `--section`, and `-s` override their respective defaults, and `--help` exits without running dependencies.
5. Unknown options, extra arguments, invalid names/sections, and an unregistered database fail without an edit.
6. A requested running database invokes `cubrid paramdump <database>` without `-S`.
7. A requested stopped database invokes `cubrid paramdump -S <database>`.
8. A similarly named running database does not cause a false positive (for example, `db` versus `db2`).
9. Nonzero `server status` and nonzero `paramdump` outcomes are handled without modifying the configuration.
10. All four record tags parse correctly.
11. Duplicate C/S records become one picker row with aggregated scope.
12. Quoted values, empty strings, lists, spaces, parentheses, and values containing `=` survive parsing and display.
13. Malformed output and an empty parsed list fail safely.
14. `fzf` cancellation and `Ctrl-C` at every interactive stage leave the fixture byte-for-byte unchanged.
15. Empty value input cancels, while `""` is passed literally as a value.
16. Declining the running-server confirmation prevents the write.
17. Confirming an edit calls `ini.sh` with the exact section, file, key, and value argv values.
18. A successful edit creates a permission-preserving backup and verifies the written value.
19. `ini.sh` failure or read-back mismatch returns nonzero, preserves the backup, and does not print success.

### Quality and integration checks

- Run `shellcheck cubrid-ini-fzf tests/test-cubrid-ini-fzf.sh`.
- Run the automated shell test suite.
- Against a stopped disposable local database, verify that the real `paramdump -S` output produces a searchable, deduplicated list.
- Perform the real write smoke test only on a copied `cubrid.conf`, pointing a controlled stub or test environment at that copy; do not mutate an active installation during verification.
- Confirm file permissions before and after the smoke test.

## Implementation Order

1. Add argument parsing, the executable skeleton, dependency/environment checks, and signal handling.
2. Implement database-registration validation, exact status parsing, and CS/SA command selection.
3. Implement robust tagged-record parsing and deduplication, then validate it against captured real `paramdump -S` output.
4. Add the parameter `fzf` interaction plus value input and cancellation behavior.
5. Add confirmation, backup, `ini.sh` update, read-back verification, and restart guidance.
6. Add stub-driven regression tests for every branch above.
7. Add concise user documentation and run lint, automated tests, and the controlled smoke test.

## Open Decisions

One behavior remains open before implementation:

- **Stopping behavior:** this plan warns and requires confirmation but does not run `cubrid server stop`; automatic stopping would be a separate, explicitly approved behavior.
