#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRONOTRIGGER="$REPO_ROOT/bin/cronotrigger"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cronotrigger-test.XXXXXX")"

cleanup() {
    [[ "$TEST_ROOT" == "${TMPDIR:-/tmp}/cronotrigger-test."* ]] || return 1
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
export CRONOTRIGGER_LUSHRC_ROOT="$REPO_ROOT"
export CRONOTRIGGER_CRONTAB_COMMAND="$REPO_ROOT/tests/fixtures/cronotrigger-crontab"
export CRONOTRIGGER_TEST_CRONTAB="$TEST_ROOT/crontab"
export CRONOTRIGGER_NOW="2026-08-12T08:00"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1" expected="$2"
    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

assert_not_contains() {
    local file="$1" unexpected="$2"
    ! grep -Fq -- "$unexpected" "$file" || fail "$file unexpectedly contains: $unexpected"
}

assert_equals() {
    local expected="$1" actual="$2"
    [[ "$expected" == "$actual" ]] || fail "expected '$expected', got '$actual'"
}

"$CRONOTRIGGER" --help >/dev/null
[[ -f "$XDG_CONFIG_HOME/cronotrigger/.enabled" ]] || fail ".enabled was not created"

"$CRONOTRIGGER" a daily \
    --every d --time 09:00 --command 'printf daily' >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" daily
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "0 9 * * *"
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "# cronotrigger:daily"

"$CRONOTRIGGER" add monthly \
    --every 1st,15th --time 10:30 --command 'printf monthly' >/dev/null
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "30 10 1,15 * *"

"$CRONOTRIGGER" add interval \
    --every 6d --time 09:00 \
    --command "printf run >> '$TEST_ROOT/interval-runs'" >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/interval.job" "anchor=2026-08-12T09:00"

export CRONOTRIGGER_NOW="2026-08-12T10:00"
"$CRONOTRIGGER" add delayed \
    --every 6d --time 09:00 --command true >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/delayed.job" "anchor=2026-08-13T09:00"

export CRONOTRIGGER_NOW="2026-08-12T08:00"
"$CRONOTRIGGER" add weekdays \
    --every mon,wed,fri --time 09:05 --command true >/dev/null
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "5 9 * * 1,3,5"

"$CRONOTRIGGER" add hourly \
    --every 6h \
    --command "printf hour >> '$TEST_ROOT/hour-runs'" >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/hourly.job" "anchor=2026-08-12T14:00"
export CRONOTRIGGER_NOW="2026-08-12T14:00"
"$CRONOTRIGGER" _run hourly
assert_equals hour "$(cat "$TEST_ROOT/hour-runs")"
export CRONOTRIGGER_NOW="2026-08-12T15:00"
"$CRONOTRIGGER" _run hourly
assert_equals hour "$(cat "$TEST_ROOT/hour-runs")"
export CRONOTRIGGER_NOW="2026-08-12T08:00"

list_output=$("$CRONOTRIGGER" ls)
[[ "$list_output" == *"daily"* ]] || fail "list omitted enabled jobs"

"$CRONOTRIGGER" disable daily >/dev/null
[[ -f "$XDG_CONFIG_HOME/cronotrigger/daily.job" ]] || fail "disable removed the job file"
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" daily
assert_not_contains "$CRONOTRIGGER_TEST_CRONTAB" "# cronotrigger:daily"
list_output=$(NO_COLOR=1 "$CRONOTRIGGER" list)
[[ "$list_output" == *"daily"* ]] || fail "list omitted disabled job"

"$CRONOTRIGGER" enable daily >/dev/null
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "# cronotrigger:daily"

printf 'every=day\ntime=12:00\ncommand=pwd\n' \
    > "$XDG_CONFIG_HOME/cronotrigger/manual.job"
"$CRONOTRIGGER" list >/dev/null
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" manual

printf 'every=3d\ntime=13:00\ncommand=true\n' \
    > "$XDG_CONFIG_HOME/cronotrigger/manual-interval.job"
"$CRONOTRIGGER" enable manual-interval >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/manual-interval.job" "anchor=2026-08-12T13:00"
assert_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" manual-interval

printf 'unknown=value\n' > "$XDG_CONFIG_HOME/cronotrigger/broken.job"
printf 'broken\n' >> "$XDG_CONFIG_HOME/cronotrigger/.enabled"
"$CRONOTRIGGER" disable broken >/dev/null 2>&1
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" broken

if "$CRONOTRIGGER" add bad --every 11st --time 09:00 --command true >/dev/null 2>&1; then
    fail "invalid ordinal was accepted"
fi
[[ ! -e "$XDG_CONFIG_HOME/cronotrigger/bad.job" ]] || fail "invalid add left a job file"

if "$CRONOTRIGGER" add bad-cwd --every day --time 09:00 --cwd /tmp --command true >/dev/null 2>&1; then
    fail "removed --cwd option was accepted"
fi

printf 'every=day\ntime=09:00\nworking_directory=/tmp\ncommand=true\n' \
    > "$XDG_CONFIG_HOME/cronotrigger/bad-working-directory.job"
if "$CRONOTRIGGER" enable bad-working-directory >/dev/null 2>&1; then
    fail "removed working_directory key was accepted"
fi

export VISUAL="$REPO_ROOT/tests/fixtures/cronotrigger-editor"
export CRONOTRIGGER_TEST_REPLACEMENT='printf edited'
"$CRONOTRIGGER" e daily >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/daily.job" "command=printf edited"
unset VISUAL CRONOTRIGGER_TEST_REPLACEMENT

export VISUAL="$REPO_ROOT/tests/fixtures/cronotrigger-editor"
export CRONOTRIGGER_TEST_FILE_CONTENT="every=day
time=14:00
command=true"
"$CRONOTRIGGER" edit broken >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/broken.job" "every=day"
unset VISUAL CRONOTRIGGER_TEST_FILE_CONTENT

export VISUAL="$REPO_ROOT/tests/fixtures/cronotrigger-editor"
export CRONOTRIGGER_TEST_REPLACEMENT='printf from-editor'
export CRONOTRIGGER_TEST_EXPECTED_NAME=editor-created
"$CRONOTRIGGER" add editor-created >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/editor-created.job" "command=printf from-editor"
assert_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" editor-created
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/editor-created.job" "name="
unset CRONOTRIGGER_TEST_REPLACEMENT CRONOTRIGGER_TEST_EXPECTED_NAME

export CRONOTRIGGER_TEST_FILE_CONTENT="name=no-name-argument
every=day
time=15:00
command=true"
"$CRONOTRIGGER" add >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/no-name-argument.job" "time=15:00"
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/no-name-argument.job" "name="
assert_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" no-name-argument
unset VISUAL CRONOTRIGGER_TEST_FILE_CONTENT

manual_output=$("$CRONOTRIGGER" run manual)
[[ "$manual_output" == *"$HOME"* ]] || fail "manual run did not execute from HOME"
assert_contains "$XDG_STATE_HOME/cronotrigger/logs/manual.log" "finish manual exit=0"

"$CRONOTRIGGER" _run interval
assert_equals run "$(cat "$TEST_ROOT/interval-runs")"
export CRONOTRIGGER_NOW="2026-08-13T09:00"
"$CRONOTRIGGER" _run interval
assert_equals run "$(cat "$TEST_ROOT/interval-runs")"

printf '5 5 * * * echo unrelated\n' > "$CRONOTRIGGER_TEST_CRONTAB"
"$CRONOTRIGGER" list >/dev/null
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "5 5 * * * echo unrelated"
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "# BEGIN cronotrigger"

"$CRONOTRIGGER" rm monthly --force >/dev/null
[[ ! -e "$XDG_CONFIG_HOME/cronotrigger/monthly.job" ]] || fail "remove kept the job file"
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" monthly
assert_not_contains "$CRONOTRIGGER_TEST_CRONTAB" "# cronotrigger:monthly"

cp "$CRONOTRIGGER_TEST_CRONTAB" "$TEST_ROOT/crontab-good"
printf '# BEGIN cronotrigger\n' > "$CRONOTRIGGER_TEST_CRONTAB"
if "$CRONOTRIGGER" list >/dev/null 2>&1; then
    fail "malformed managed block was accepted"
fi
assert_equals "# BEGIN cronotrigger" "$(cat "$CRONOTRIGGER_TEST_CRONTAB")"
printf '# END cronotrigger\nkeep me\n# BEGIN cronotrigger\n' > "$CRONOTRIGGER_TEST_CRONTAB"
if "$CRONOTRIGGER" list >/dev/null 2>&1; then
    fail "reversed managed block was accepted"
fi
assert_contains "$CRONOTRIGGER_TEST_CRONTAB" "keep me"
cp "$TEST_ROOT/crontab-good" "$CRONOTRIGGER_TEST_CRONTAB"

export CRONOTRIGGER_TEST_FAIL_INSTALL=true
if "$CRONOTRIGGER" add rollback \
    --every day --time 16:00 --command true >/dev/null 2>&1; then
    fail "add succeeded despite crontab installation failure"
fi
unset CRONOTRIGGER_TEST_FAIL_INSTALL
[[ ! -e "$XDG_CONFIG_HOME/cronotrigger/rollback.job" ]] || fail "failed add kept its job file"
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/.enabled" rollback

export VISUAL="$REPO_ROOT/tests/fixtures/cronotrigger-editor"
export CRONOTRIGGER_TEST_FILE_CONTENT="name=draft-add
every=99st
time=09:00
command=printf sentinel-add"
if "$CRONOTRIGGER" add draft-add >/dev/null 2>&1; then
    fail "invalid schedule was accepted on add"
fi
[[ ! -e "$XDG_CONFIG_HOME/cronotrigger/draft-add.job" ]] || fail "failed add left a job file"
[[ -f "$XDG_RUNTIME_DIR/drafts/draft-add.job" ]] || fail "failed add did not stash a draft"
unset CRONOTRIGGER_TEST_FILE_CONTENT

export CRONOTRIGGER_TEST_ASSERT_CONTAINS="printf sentinel-add"
export CRONOTRIGGER_TEST_REPLACEMENT='printf sentinel-add'
if "$CRONOTRIGGER" add draft-add >/dev/null 2>&1; then
    fail "resumed draft with untouched schedule was accepted"
fi
unset CRONOTRIGGER_TEST_ASSERT_CONTAINS

export CRONOTRIGGER_TEST_FILE_CONTENT="name=draft-add
every=day
time=09:00
command=printf sentinel-add"
"$CRONOTRIGGER" add draft-add >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/draft-add.job" "command=printf sentinel-add"
[[ ! -f "$XDG_RUNTIME_DIR/drafts/draft-add.job" ]] || fail "successful add left a stale draft"
unset VISUAL CRONOTRIGGER_TEST_FILE_CONTENT CRONOTRIGGER_TEST_REPLACEMENT

export VISUAL="$REPO_ROOT/tests/fixtures/cronotrigger-editor"
export CRONOTRIGGER_TEST_FILE_CONTENT="every=99st
time=09:00
command=printf sentinel-edit"
if "$CRONOTRIGGER" edit daily >/dev/null 2>&1; then
    fail "invalid schedule was accepted on edit"
fi
assert_not_contains "$XDG_CONFIG_HOME/cronotrigger/daily.job" "sentinel-edit"
unset CRONOTRIGGER_TEST_FILE_CONTENT

export CRONOTRIGGER_TEST_ASSERT_CONTAINS="printf sentinel-edit"
export CRONOTRIGGER_TEST_REPLACEMENT='printf sentinel-edit'
if "$CRONOTRIGGER" edit daily >/dev/null 2>&1; then
    fail "resumed edit draft with untouched schedule was accepted"
fi
unset CRONOTRIGGER_TEST_ASSERT_CONTAINS

export CRONOTRIGGER_TEST_FILE_CONTENT="every=day
time=09:00
command=printf sentinel-edit"
"$CRONOTRIGGER" edit daily >/dev/null
assert_contains "$XDG_CONFIG_HOME/cronotrigger/daily.job" "command=printf sentinel-edit"
unset VISUAL CRONOTRIGGER_TEST_FILE_CONTENT CRONOTRIGGER_TEST_REPLACEMENT

echo "cronotrigger tests passed"
