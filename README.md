# cubrid-ini-fzf

`cubrid-ini-fzf` is an interactive Bash tool for finding a CUBRID system
parameter and persisting a new value in `cubrid.conf`.

It asks CUBRID for the available parameters, uses `fzf` to select one, and
delegates every configuration write to `ini.sh`.

## Requirements

The following commands must be available on `PATH`:

- `cubrid`
- `fzf`
- `ini.sh`

The CUBRID environment must also define:

- `CUBRID`, containing `conf/cubrid.conf`
- `CUBRID_DATABASES`, containing `databases.txt`

The script deliberately checks for `ini.sh` before starting any interactive
work.

## Installation

For a local checkout, the recommended installation is a symlink in
`~/.local/bin`:

```bash
just install
```

The recipe is idempotent when the correct symlink already exists and refuses
to overwrite an unrelated file or symlink. Override the destination when
needed:

```bash
CUBRID_INI_FZF_BIN_DIR=/another/directory just install
```

Ensure the selected directory is on `PATH`. A symlink is convenient during
development because changes in this checkout are available immediately. Keep
the checkout at a stable path; moving or deleting it breaks the command.

For a versioned or self-contained installation, copy the executable instead:

```bash
install -m 0755 cubrid-ini-fzf "$HOME/.local/bin/cubrid-ini-fzf"
```

## Usage

```text
cubrid-ini-fzf [OPTIONS]

Options:
  -d, --database DATABASE  Database used for status and paramdump (default: testdb)
  -s, --section SECTION    ini.sh section: common, standalone, or @DATABASE
                           (default: common)
  -h, --help               Show help
```

The zero-argument form reads parameters for `testdb` and writes to `[common]`:

```bash
cubrid-ini-fzf
```

Use another database for `paramdump`:

```bash
cubrid-ini-fzf --database demodb
```

Write a database-specific setting instead of `[common]`:

```bash
cubrid-ini-fzf --database demodb --section @demodb
```

Section names are passed without square brackets. Supported targets are
`common`, `standalone`, and `@DATABASE`.

## Behavior

The tool performs these steps:

1. Verifies its dependencies, environment, configuration file, and database
   registration.
2. Runs `cubrid server status` and matches the requested database name exactly.
3. Uses `cubrid paramdump DATABASE` when it is running, or
   `cubrid paramdump -S DATABASE` when it is stopped.
4. Parses and deduplicates client (`C`) and server (`S`) parameter records.
5. Opens the result in `fzf` and prompts for a new value.
6. Shows the complete change and asks for confirmation.
7. Creates a permission-preserving sibling backup of `cubrid.conf`.
8. Writes and reads the value back through `ini.sh`.

Empty input at the value prompt cancels the edit. To set an explicit empty
CUBRID string, enter `""`.

`Ctrl-C`, Escape in `fzf`, or declining confirmation exits without performing
an INI write. If `ini.sh` fails after the backup has been created, the backup is
retained and its path is printed.

## Applying a change

The tool edits persistent configuration; it does not stop processes
automatically. When the selected database is running, it warns before the
write and asks for confirmation. After a successful edit, stop and start the
database to apply server settings:

```bash
cubrid server stop DATABASE
cubrid server start DATABASE
```

Client-side parameters may also require a broker restart.

## Limitations

- “Available parameters” means the parameters emitted by the installed
  `cubrid paramdump`. The tool does not maintain its own parameter catalog.
- `paramdump` does not provide complete allowed-value domains, so values are
  not type- or range-validated before they are passed to `ini.sh`.
- This version changes one parameter per invocation.
- The tool targets Bash and Unix-like CUBRID installations.

## Tests

The test suite uses isolated stub commands and never modifies an installed
CUBRID configuration:

```bash
tests/test-cubrid-ini-fzf.sh
```

For additional static checks, run:

```bash
shellcheck cubrid-ini-fzf tests/test-cubrid-ini-fzf.sh tests/stubs/*
```
