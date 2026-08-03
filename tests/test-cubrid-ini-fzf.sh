#!/usr/bin/env bash

set -o nounset
set -o pipefail

TESTS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly TESTS_DIR
PROJECT_DIR=$(cd -- "$TESTS_DIR/.." && pwd -P)
readonly PROJECT_DIR
readonly TOOL=$PROJECT_DIR/cubrid-ini-fzf
readonly STUBS_DIR=$TESTS_DIR/stubs
TEST_TMP_ROOT=$(mktemp -d /tmp/cubrid-ini-fzf-tests.XXXXXX)
readonly TEST_TMP_ROOT

tests_run=0
tests_failed=0
case_number=0
case_dir=
output_file=
tool_status=0

cleanup ()
{
  if (( tests_failed > 0 )); then
    printf '# failed-test artifacts retained at %s\n' "$TEST_TMP_ROOT" >&2
    return
  fi

  if [[ $TEST_TMP_ROOT == /tmp/cubrid-ini-fzf-tests.* && -d $TEST_TMP_ROOT ]]; then
    chmod -R u+w "$TEST_TMP_ROOT" 2>/dev/null || true
    rm -r -- "$TEST_TMP_ROOT"
  fi
}

trap cleanup EXIT

fail ()
{
  printf '    %s\n' "$*" >&2
  return 1
}

assert_status ()
{
  local expected=$1

  [[ $tool_status == "$expected" ]] \
    || fail "expected status $expected, got $tool_status; output: $(< "$output_file")"
}

assert_contains ()
{
  local file=$1
  local expected=$2

  /usr/bin/grep -Fq -- "$expected" "$file" \
    || fail "expected '$expected' in $file"
}

assert_not_contains ()
{
  local file=$1
  local unexpected=$2

  if /usr/bin/grep -Fq -- "$unexpected" "$file"; then
    fail "did not expect '$unexpected' in $file"
  fi
}

assert_equal ()
{
  local expected=$1
  local actual=$2

  [[ $actual == "$expected" ]] \
    || fail "expected '$expected', got '$actual'"
}

setup_case ()
{
  case_number=$((case_number + 1))
  case_dir=$TEST_TMP_ROOT/case-$case_number
  /usr/bin/mkdir -p "$case_dir/cubrid/conf" "$case_dir/databases" "$case_dir/state"
  output_file=$case_dir/output

  printf '[common]\nmax_clients=100\n' > "$case_dir/cubrid/conf/cubrid.conf"
  chmod 640 "$case_dir/cubrid/conf/cubrid.conf"
  printf '#db-name vol-path db-host log-path lob-base-path\n' \
    > "$case_dir/databases/databases.txt"
  printf 'testdb %s localhost %s file:%s/lob\n' \
    "$case_dir/testdb" "$case_dir/testdb" "$case_dir/testdb" \
    >> "$case_dir/databases/databases.txt"
  printf 'db2 %s localhost %s file:%s/lob\n' \
    "$case_dir/db2" "$case_dir/db2" "$case_dir/db2" \
    >> "$case_dir/databases/databases.txt"
  : > "$case_dir/log"
  : > "$case_dir/fzf-input"

  export PATH=$STUBS_DIR:/usr/bin:/bin
  export CUBRID=$case_dir/cubrid
  export CUBRID_DATABASES=$case_dir/databases
  export STUB_LOG=$case_dir/log
  export STUB_STATE=$case_dir/state
  export FZF_CAPTURE=$case_dir/fzf-input
  export FZF_SELECT_NAME=max_clients
  unset CUBRID_STATUS_FAIL STUB_RUNNING_DATABASES PARAMDUMP_FAIL
  unset PARAMDUMP_FIXTURE FZF_EXIT INI_FAIL_WRITE INI_FAIL_READ INI_READ_MISMATCH
}

run_tool ()
{
  local input=$1
  shift

  printf '%s' "$input" | "$TOOL" "$@" > "$output_file" 2>&1
  tool_status=${PIPESTATUS[1]}
}

run_tool_with_path ()
{
  local path=$1
  local input=$2
  shift 2

  printf '%s' "$input" | env PATH="$path" "$TOOL" "$@" > "$output_file" 2>&1
  tool_status=${PIPESTATUS[1]}
}

run_test ()
{
  local name=$1
  local test_function=$2

  tests_run=$((tests_run + 1))
  if "$test_function"; then
    printf 'ok %d - %s\n' "$tests_run" "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'not ok %d - %s\n' "$tests_run" "$name"
    printf '    artifacts: %s\n' "$case_dir" >&2
  fi
}

test_help_without_dependencies ()
{
  setup_case
  run_tool_with_path /usr/bin:/bin '' --help
  assert_status 0 || return
  assert_contains "$output_file" 'Usage: cubrid-ini-fzf [OPTIONS]' || return
  [[ ! -s $STUB_LOG ]] || fail 'help unexpectedly invoked a dependency'
}

test_ini_is_checked_first ()
{
  local reduced_path

  setup_case
  reduced_path=$case_dir/reduced-bin
  /usr/bin/mkdir -p "$reduced_path"
  /usr/bin/ln -s "$STUBS_DIR/cubrid" "$reduced_path/cubrid"
  /usr/bin/ln -s "$STUBS_DIR/fzf" "$reduced_path/fzf"
  /usr/bin/ln -s /usr/bin/bash "$reduced_path/bash"
  run_tool_with_path "$reduced_path" ''
  assert_status 1 || return
  assert_contains "$output_file" 'ini.sh is required but was not found on PATH' || return
  [[ ! -s $STUB_LOG ]] || fail 'cubrid or fzf ran before the ini.sh check'
}

test_other_dependencies_and_environment ()
{
  local reduced_path

  setup_case
  reduced_path=$case_dir/no-cubrid-bin
  /usr/bin/mkdir -p "$reduced_path"
  /usr/bin/ln -s "$STUBS_DIR/ini.sh" "$reduced_path/ini.sh"
  /usr/bin/ln -s "$STUBS_DIR/fzf" "$reduced_path/fzf"
  /usr/bin/ln -s /usr/bin/bash "$reduced_path/bash"
  run_tool_with_path "$reduced_path" ''
  assert_status 1 || return
  assert_contains "$output_file" 'cubrid is required but was not found on PATH' || return

  setup_case
  reduced_path=$case_dir/no-fzf-bin
  /usr/bin/mkdir -p "$reduced_path"
  /usr/bin/ln -s "$STUBS_DIR/ini.sh" "$reduced_path/ini.sh"
  /usr/bin/ln -s "$STUBS_DIR/cubrid" "$reduced_path/cubrid"
  /usr/bin/ln -s /usr/bin/bash "$reduced_path/bash"
  run_tool_with_path "$reduced_path" ''
  assert_status 1 || return
  assert_contains "$output_file" 'fzf is required but was not found on PATH' || return

  setup_case
  CUBRID=
  export CUBRID
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" 'CUBRID is not set'
}

test_environment_files_are_validated ()
{
  setup_case
  /usr/bin/mv "$CUBRID_DATABASES/databases.txt" "$CUBRID_DATABASES/databases.txt.away"
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" 'database registry not found' || return
  [[ ! -s $STUB_LOG ]] || fail 'missing database registry invoked cubrid or fzf'

  setup_case
  /usr/bin/mv "$CUBRID/conf/cubrid.conf" "$CUBRID/conf/cubrid.conf.away"
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" 'configuration file not found' || return
  [[ ! -s $STUB_LOG ]] || fail 'missing configuration invoked cubrid or fzf'
}

test_default_stopped_database_update ()
{
  local backup_count
  local backup_mode

  setup_case
  run_tool $'250\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" 'cubrid <paramdump> <-S> <testdb>' || return
  assert_contains "$STUB_LOG" "ini.sh <-s> <common> <$CUBRID/conf/cubrid.conf> <max_clients> <--> <250>" || return
  assert_contains "$output_file" 'Updated max_clients in [common].' || return
  assert_contains "$output_file" 'cubrid server stop testdb' || return
  backup_count=$(/usr/bin/find "$CUBRID/conf" -maxdepth 1 -name 'cubrid.conf.bak.*' | /usr/bin/wc -l)
  assert_equal 1 "$backup_count" || return
  backup_mode=$(/usr/bin/stat -c '%a' "$CUBRID/conf"/cubrid.conf.bak.*)
  assert_equal 640 "$backup_mode"
}

test_running_database_uses_normal_paramdump ()
{
  setup_case
  export STUB_RUNNING_DATABASES='db2 testdb-extra testdb'
  run_tool $'300\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" 'cubrid <paramdump> <testdb>' || return
  assert_not_contains "$STUB_LOG" 'cubrid <paramdump> <-S> <testdb>' || return
  assert_contains "$output_file" 'Database testdb is running.' || return
  assert_contains "$output_file" 'restart the affected processes afterward'
}

test_similar_database_name_is_not_running ()
{
  setup_case
  export STUB_RUNNING_DATABASES='testdb-extra db2'
  run_tool $'300\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" 'cubrid <paramdump> <-S> <testdb>'
}

test_database_and_section_overrides ()
{
  setup_case
  run_tool $'42\ny\n' -d db2 --section @db2
  assert_status 0 || return
  assert_contains "$STUB_LOG" 'cubrid <paramdump> <-S> <db2>' || return
  assert_contains "$STUB_LOG" "ini.sh <-s> <@db2> <$CUBRID/conf/cubrid.conf> <max_clients> <--> <42>" || return
  assert_contains "$output_file" 'Section:  [@db2]' || return

  setup_case
  run_tool $'43\ny\n' --database=db2 -s standalone
  assert_status 0 || return
  assert_contains "$STUB_LOG" 'cubrid <paramdump> <-S> <db2>' || return
  assert_contains "$STUB_LOG" "ini.sh <-s> <standalone> <$CUBRID/conf/cubrid.conf> <max_clients> <--> <43>"
}

test_invalid_and_unregistered_arguments ()
{
  setup_case
  run_tool '' --section service
  assert_status 1 || return
  assert_contains "$output_file" "invalid section 'service'" || return
  [[ ! -s $STUB_LOG ]] || fail 'invalid section invoked a dependency'

  setup_case
  run_tool '' --database missingdb
  assert_status 1 || return
  assert_contains "$output_file" "database 'missingdb' is not registered" || return
  [[ ! -s $STUB_LOG ]] || fail 'unregistered database invoked cubrid or fzf' || return

  setup_case
  run_tool '' --unknown
  assert_status 1 || return
  assert_contains "$output_file" 'unknown option: --unknown' || return
  [[ ! -s $STUB_LOG ]] || fail 'unknown option invoked a dependency' || return

  setup_case
  run_tool '' extra
  assert_status 1 || return
  assert_contains "$output_file" 'unexpected argument: extra' || return
  [[ ! -s $STUB_LOG ]] || fail 'extra argument invoked a dependency' || return

  setup_case
  run_tool '' --database 'bad/name'
  assert_status 1 || return
  assert_contains "$output_file" 'invalid database name: bad/name' || return
  [[ ! -s $STUB_LOG ]] || fail 'invalid database name invoked a dependency'
}

test_paramdump_parsing_and_deduplication ()
{
  local max_clients_count

  setup_case
  export FZF_EXIT=130
  run_tool ''
  assert_status 130 || return
  assert_contains "$FZF_CAPTURE" $'C/S\tmax_clients\tC: 100 (100) | S: 200 (100)' || return
  assert_contains "$FZF_CAPTURE" $'C\tcomplex_value\t"a=b (c)" ("")' || return
  assert_contains "$FZF_CAPTURE" $'S\tserver_only\t-1 (-1)' || return
  max_clients_count=$(/usr/bin/awk -F '\t' '$2 == "max_clients" { count++ } END { print count + 0 }' "$FZF_CAPTURE")
  assert_equal 1 "$max_clients_count"
}

test_cancellation_paths_do_not_write ()
{
  local before
  local after

  setup_case
  before=$(/usr/bin/sha256sum "$CUBRID/conf/cubrid.conf")
  before=${before%% *}
  export FZF_EXIT=130
  run_tool ''
  assert_status 130 || return
  after=$(/usr/bin/sha256sum "$CUBRID/conf/cubrid.conf")
  after=${after%% *}
  assert_equal "$before" "$after" || return
  assert_not_contains "$STUB_LOG" 'ini.sh' || return

  setup_case
  run_tool $'\n'
  assert_status 0 || return
  assert_not_contains "$STUB_LOG" 'ini.sh' || return

  setup_case
  run_tool $'250\nn\n'
  assert_status 0 || return
  assert_not_contains "$STUB_LOG" 'ini.sh'
}

test_ctrl_c_at_text_prompts_does_not_write ()
{
  local input_fifo

  setup_case
  input_fifo=$case_dir/input-fifo
  /usr/bin/mkfifo "$input_fifo"
  exec 9<> "$input_fifo"
  /usr/bin/timeout --preserve-status --signal=INT --kill-after=1s 0.3s \
    "$TOOL" < "$input_fifo" > "$output_file" 2>&1
  tool_status=$?
  exec 9>&-
  assert_status 130 || return
  assert_not_contains "$STUB_LOG" 'ini.sh' || return
  assert_contains "$output_file" 'cancelled; cubrid.conf was not changed' || return

  setup_case
  input_fifo=$case_dir/input-fifo
  /usr/bin/mkfifo "$input_fifo"
  exec 9<> "$input_fifo"
  printf '250\n' >&9
  /usr/bin/timeout --preserve-status --signal=INT --kill-after=1s 0.3s \
    "$TOOL" < "$input_fifo" > "$output_file" 2>&1
  tool_status=$?
  exec 9>&-
  assert_status 130 || return
  assert_not_contains "$STUB_LOG" 'ini.sh' || return
  assert_contains "$output_file" 'cancelled; cubrid.conf was not changed'
}

test_status_and_paramdump_failures_do_not_write ()
{
  setup_case
  export CUBRID_STATUS_FAIL=1
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" 'could not determine database server status' || return
  assert_not_contains "$STUB_LOG" 'ini.sh' || return

  setup_case
  export PARAMDUMP_FAIL=1
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" "paramdump failed for database 'testdb'" || return
  assert_not_contains "$STUB_LOG" 'ini.sh'
}

test_malformed_paramdump_fails_safely ()
{
  setup_case
  printf 'not a parameter dump\n' > "$case_dir/malformed-paramdump"
  export PARAMDUMP_FIXTURE=$case_dir/malformed-paramdump
  run_tool ''
  assert_status 1 || return
  assert_contains "$output_file" 'paramdump returned no recognizable system parameters' || return
  assert_not_contains "$STUB_LOG" 'ini.sh'
}

test_literal_empty_string_and_spaced_value ()
{
  setup_case
  run_tool $'""\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" '<max_clients> <--> <"">' || return

  setup_case
  run_tool $'value with spaces = yes\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" '<max_clients> <--> <value with spaces = yes>' || return

  setup_case
  run_tool $'-1\ny\n'
  assert_status 0 || return
  assert_contains "$STUB_LOG" '<max_clients> <--> <-1>'
}

test_ini_failures_retain_backup ()
{
  local backup_count

  setup_case
  export INI_FAIL_WRITE=1
  run_tool $'250\ny\n'
  assert_status 1 || return
  assert_contains "$output_file" 'ini.sh failed while updating' || return
  backup_count=$(/usr/bin/find "$CUBRID/conf" -maxdepth 1 -name 'cubrid.conf.bak.*' | /usr/bin/wc -l)
  assert_equal 1 "$backup_count" || return

  setup_case
  export INI_READ_MISMATCH=1
  run_tool $'250\ny\n'
  assert_status 1 || return
  assert_contains "$output_file" 'read-back verification failed' || return
  assert_contains "$output_file" 'backup retained at'
}

printf '1..16\n'
run_test 'help works without runtime dependencies' test_help_without_dependencies
run_test 'ini.sh is checked before other dependencies run' test_ini_is_checked_first
run_test 'other missing dependencies and environment fail clearly' test_other_dependencies_and_environment
run_test 'missing configuration and registry files fail early' test_environment_files_are_validated
run_test 'default stopped testdb update uses common and SA mode' test_default_stopped_database_update
run_test 'running testdb uses normal paramdump and warns' test_running_database_uses_normal_paramdump
run_test 'similarly named running database does not match testdb' test_similar_database_name_is_not_running
run_test 'database and section overrides reach cubrid and ini.sh' test_database_and_section_overrides
run_test 'invalid and unregistered arguments fail early' test_invalid_and_unregistered_arguments
run_test 'all tags parse and duplicate C/S records collapse' test_paramdump_parsing_and_deduplication
run_test 'picker, empty-value, and confirmation cancellation do not write' test_cancellation_paths_do_not_write
run_test 'Ctrl-C at value and confirmation prompts exits 130 without a write' test_ctrl_c_at_text_prompts_does_not_write
run_test 'status and paramdump failures do not write' test_status_and_paramdump_failures_do_not_write
run_test 'malformed paramdump fails safely' test_malformed_paramdump_fails_safely
run_test 'literal empty and spaced values reach ini.sh unchanged' test_literal_empty_string_and_spaced_value
run_test 'ini.sh failures retain a backup' test_ini_failures_retain_backup

if (( tests_failed > 0 )); then
  printf '# %d of %d tests failed\n' "$tests_failed" "$tests_run" >&2
  exit 1
fi

printf '# all %d tests passed\n' "$tests_run"
