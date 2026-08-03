#!/usr/bin/env bash

set -o nounset

log_call ()
{
  local argument

  printf 'ini.sh' >> "$STUB_LOG"
  for argument in "$@"; do
    printf ' <%s>' "$argument" >> "$STUB_LOG"
  done
  printf '\n' >> "$STUB_LOG"
}

log_call "$@"

[[ ${1-} == -s && $# -ge 4 ]] || exit 6

section=$2
config_file=$3
key=$4
state_file=$STUB_STATE/${section//@/_at_}__$key

if (( $# == 6 )) && [[ $5 == -- ]]; then
  if [[ ${INI_FAIL_WRITE:-0} == 1 ]]; then
    printf 'simulated ini.sh write failure\n' >&2
    exit 5
  fi

  value=$6
  printf '%s\n' "$value" > "$state_file"
  printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >> "$config_file"
  exit 0
fi

if [[ ${INI_FAIL_READ:-0} == 1 ]]; then
  printf 'simulated ini.sh read failure\n' >&2
  exit 4
fi

if [[ ${INI_READ_MISMATCH:-0} == 1 ]]; then
  printf 'different-value\n'
elif [[ -f $state_file ]]; then
  /bin/cat -- "$state_file"
fi
