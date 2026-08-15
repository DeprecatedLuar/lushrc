#!/usr/bin/env bash

# Two layers:
#   1. pure    — sources the modules, stubs the systemd probes, asserts on logic
#   2. systemd — drives the real binary against the real user manager
#
# Layer 2 cannot be mocked away. The bug this suite exists for is that
# systemd-run resolves argv[0] against the *caller's* PATH while the manager
# resolves ExecStart= against its own; a fake systemctl has one PATH, so the
# mismatch — and the bug — would vanish under it.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../../.." && pwd)"
BIGBROTHER="$REPO_ROOT/bin/lib/bigbrother/main.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bigbrother-test.XXXXXX")"

# Every unit this suite creates starts with this, and cleanup touches nothing
# else — these units live in the caller's real ~/.config/systemd/user, because
# that is the only directory the running user manager reads.
TEST_PREFIX="bbtest-$$"

export BIGBROTHER_LUSHRC_ROOT="$REPO_ROOT"

cleanup() {
    local unit name
    if [[ -n "${BIGBROTHER_UNIT_DIR:-}" ]]; then
        for unit in "$BIGBROTHER_UNIT_DIR/$TEST_PREFIX"*.service; do
            [[ -f "$unit" ]] || continue
            name=$(basename "$unit" .service)
            systemctl --user disable --now "$name.service" &>/dev/null || true
            rm -f -- "$unit"
        done
    fi
    # Transients have no file; find them by prefix in the loaded unit list.
    while read -r name; do
        [[ -n "$name" ]] || continue
        systemctl --user stop "$name" &>/dev/null || true
        systemctl --user reset-failed "$name" &>/dev/null || true
    done < <(systemctl --user list-units --type=service --all --no-legend --plain 2>/dev/null |
        awk '{print $1}' | grep "^$TEST_PREFIX" || true)
    systemctl --user daemon-reload &>/dev/null || true

    [[ "$TEST_ROOT" == "${TMPDIR:-/tmp}/bigbrother-test."* ]] || return 1
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1" actual="$2" what="${3:-value}"
    [[ "$expected" == "$actual" ]] || fail "$what: expected '$expected', got '$actual'"
}

assert_contains() {
    local haystack="$1" needle="$2" what="${3:-output}"
    [[ "$haystack" == *"$needle"* ]] || fail "$what does not contain '$needle': $haystack"
}

assert_file_contains() {
    local file="$1" expected="$2"
    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

# ---------------------------------------------------------------- layer 1

(
    # shellcheck source=/dev/null
    source "$REPO_ROOT/bin/lib/bigbrother/paths.sh"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/bin/lib/bigbrother/unit.sh"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/bin/lib/bigbrother/commands.sh"

    # Stubs stand in for the two systemd probes name allocation depends on, so
    # none of this layer needs a manager — and production code needs no
    # indirection bolted on for testability.
    BB_TAKEN=""
    bigbrother_is_defined() { [[ " $BB_TAKEN " == *" $1 "* ]]; }
    bigbrother_is_transient() { return 1; }

    # free_name: walks past collisions instead of refusing
    BB_TAKEN="agentctl"
    assert_equals "agentctl.1" "$(bigbrother_free_name agentctl)" "first collision"
    BB_TAKEN="agentctl agentctl.1 agentctl.2"
    assert_equals "agentctl.3" "$(bigbrother_free_name agentctl)" "third collision"
    BB_TAKEN="free-name"
    assert_equals "untaken" "$(bigbrother_free_name untaken)" "no collision"

    # free_name: bounded rather than looping forever
    bigbrother_is_defined() { return 0; }
    if bigbrother_free_name always-taken >/dev/null 2>&1; then
        fail "free_name did not give up when every candidate was taken"
    fi
    bigbrother_is_defined() { [[ " $BB_TAKEN " == *" $1 "* ]]; }

    # derive_name: basename, and a refusal rather than a silent mangling
    assert_equals "agentctl" "$(bigbrother_derive_name /home/luar/bin/agentctl)" "abs path"
    assert_equals "agentctl" "$(bigbrother_derive_name agentctl)" "bare name"
    assert_equals "deploy.sh" "$(bigbrother_derive_name ./deploy.sh)" "relative path"
    if bigbrother_derive_name ./Deploy.sh >/dev/null 2>&1; then
        fail "derive_name accepted a name that validate_name rejects"
    fi
    derive_error=$(bigbrother_derive_name ./Deploy.sh 2>&1 || true)
    assert_contains "$derive_error" "-n" "derive_name error points at the -n escape hatch"

    # parse_launch_args, command-positional (run): the second word of
    # `bb run agentctl run` must survive as part of the command line
    bigbrother_parse_launch_args command agentctl run
    assert_equals "agentctl run" "${BB_ARG_COMMAND[*]}" "run command"
    assert_equals "" "$BB_ARG_NAME" "run name"

    bigbrother_parse_launch_args command -n master-agent agentctl run
    assert_equals "master-agent" "$BB_ARG_NAME" "run -n"
    assert_equals "agentctl run" "${BB_ARG_COMMAND[*]}" "run -n command"

    bigbrother_parse_launch_args command --name=master-agent --workdir=/tmp agentctl run
    assert_equals "master-agent" "$BB_ARG_NAME" "run --name="
    assert_equals "/tmp" "$BB_ARG_WORKDIR" "run --workdir="

    # flags after -c belong to the command, not to bigbrother
    bigbrother_parse_launch_args command -c agentctl run --verbose -n nope
    assert_equals "agentctl run --verbose -n nope" "${BB_ARG_COMMAND[*]}" "-c swallows the rest"
    assert_equals "" "$BB_ARG_NAME" "-c did not leak a name"

    # parse_launch_args, name-positional (add)
    bigbrother_parse_launch_args name master-agent -c agentctl run
    assert_equals "master-agent" "$BB_ARG_NAME" "add positional name"
    assert_equals "agentctl run" "${BB_ARG_COMMAND[*]}" "add command"

    bigbrother_parse_launch_args name -n master-agent -c agentctl run
    assert_equals "master-agent" "$BB_ARG_NAME" "add -n name"

    bigbrother_parse_launch_args name lonely
    assert_equals "lonely" "$BB_ARG_NAME" "add with no command"
    assert_equals "0" "${#BB_ARG_COMMAND[@]}" "add with no command has no command"

    if bigbrother_parse_launch_args name one two >/dev/null 2>&1; then
        fail "add accepted a second positional argument"
    fi
    if bigbrother_parse_launch_args command --bogus x >/dev/null 2>&1; then
        fail "unknown flag was accepted"
    fi
    if bigbrother_parse_launch_args command -c >/dev/null 2>&1; then
        fail "-c with no command was accepted"
    fi
    if bigbrother_parse_launch_args command -n >/dev/null 2>&1; then
        fail "-n with no value was accepted"
    fi

    # add refuses to guess a name, and never reaches systemd to do it
    if bigbrother_cmd_add -c agentctl run >/dev/null 2>&1; then
        fail "add without a name was accepted"
    fi
    if bigbrother_cmd_add ./deploy.sh >/dev/null 2>&1; then
        fail "add accepted a path as a service name"
    fi

    # set_description: first Description= only, everything else byte-identical
    unit="$TEST_ROOT/desc.service"
    printf '[Unit]\nDescription=agentctl\n\n[Service]\nExecStart=/bin/true\nEnvironment=Description=keep-me\n' > "$unit"
    bigbrother_set_description "$unit" master-agent
    assert_equals "Description=master-agent" "$(grep -m1 '^Description=' "$unit")" "rewritten description"
    assert_file_contains "$unit" "Environment=Description=keep-me"
    assert_file_contains "$unit" "ExecStart=/bin/true"
    assert_equals "6" "$(wc -l < "$unit")" "line count unchanged"

    # a unit with no Description= is left alone rather than corrupted
    printf '[Unit]\n\n[Service]\nExecStart=/bin/true\n' > "$unit"
    bigbrother_set_description "$unit" whatever
    assert_equals "4" "$(wc -l < "$unit")" "no-description unit line count"
    assert_file_contains "$unit" "ExecStart=/bin/true"

    echo "  layer 1 (pure) passed"
)

# ---------------------------------------------------------------- layer 2

if [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null; then
    echo "bigbrother tests passed (layer 2 skipped: no systemd user manager)"
    exit 0
fi

BIGBROTHER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
export BIGBROTHER_UNIT_DIR

bb() { bash "$BIGBROTHER" "$@"; }
unit_file() { printf '%s/%s.service\n' "$BIGBROTHER_UNIT_DIR" "$1"; }
exec_start() { systemctl --user show -p ExecStart --value "$1.service" 2>/dev/null; }
active_state() { systemctl --user show -p ActiveState --value "$1.service" 2>/dev/null; }

# A binary the *caller* can resolve but the manager cannot: this directory is on
# our PATH and on nothing else's. Passing it to -c by bare name is exactly the
# shape that used to persist `ExecStart=<bare name>` and 203/EXEC forever.
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/$TEST_PREFIX" <<'EOF'
#!/usr/bin/env bash
exec sleep 300
EOF
cat > "$TEST_ROOT/bin/$TEST_PREFIX-die" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TEST_ROOT/bin/$TEST_PREFIX" "$TEST_ROOT/bin/$TEST_PREFIX-die"
export PATH="$TEST_ROOT/bin:$PATH"

# --- the regression: a verified command and a persisted one must not differ
service="$TEST_PREFIX-add"
# Invoked from TEST_ROOT on purpose: WorkingDirectory must follow the caller,
# not the directory the binary happens to live in.
(cd "$TEST_ROOT" && bb add "$service" -c "$TEST_PREFIX" >/dev/null) || fail "add -c failed"
[[ -f "$(unit_file "$service")" ]] || fail "add -c wrote no unit file"
assert_file_contains "$(unit_file "$service")" "ExecStart=$TEST_ROOT/bin/$TEST_PREFIX"
case "$(exec_start "$service")" in
    *"argv[]=$TEST_ROOT/bin/$TEST_PREFIX"*) ;;
    *) fail "persisted ExecStart is not the absolute path systemd resolved: $(exec_start "$service")" ;;
esac
assert_equals "active" "$(active_state "$service")" "regression service state"
assert_file_contains "$(unit_file "$service")" "Description=$service"

# workdir defaults to where you invoked from, not where the binary lives
assert_file_contains "$(unit_file "$service")" "WorkingDirectory=$TEST_ROOT"

# --- rm: verified teardown of a live, enabled service
bb rm "$service" >/dev/null || fail "rm failed"
[[ ! -e "$(unit_file "$service")" ]] || fail "rm kept the unit file"
assert_equals "inactive" "$(active_state "$service")" "state after rm"

# --- run: derived names step aside instead of colliding
bb run "$TEST_PREFIX" >/dev/null || fail "first run failed"
assert_equals "active" "$(active_state "$TEST_PREFIX")" "first run state"
run_output=$(bb run "$TEST_PREFIX")
assert_contains "$run_output" "~ $TEST_PREFIX.1" "second run auto-suffixed"
assert_equals "active" "$(active_state "$TEST_PREFIX.1")" "second run state"

# --- rm: a transient has no file, but must still be removable
bb rm "$TEST_PREFIX.1" >/dev/null || fail "rm of a transient failed"
assert_equals "inactive" "$(active_state "$TEST_PREFIX.1")" "transient state after rm"
bb rm "$TEST_PREFIX" >/dev/null || fail "rm of first transient failed"

# --- run: a command that dies is reported and leaves nothing behind
if bb run "$TEST_PREFIX-die" >/dev/null 2>&1; then
    fail "run of a failing command reported success"
fi
[[ ! -e "$(unit_file "$TEST_PREFIX-die")" ]] || fail "failed run persisted a unit file"
assert_equals "inactive" "$(active_state "$TEST_PREFIX-die")" "failed run left a failed unit"

# --- run: an explicit name is honoured, and refused when taken
bb run -n "$TEST_PREFIX-named" "$TEST_PREFIX" >/dev/null || fail "run -n failed"
assert_equals "active" "$(active_state "$TEST_PREFIX-named")" "run -n state"
if bb run -n "$TEST_PREFIX-named" "$TEST_PREFIX" >/dev/null 2>&1; then
    fail "run -n reused a taken name instead of refusing"
fi

# --- enable: promotes that transient, absolute ExecStart intact
bb enable "$TEST_PREFIX-named" >/dev/null || fail "enable of a transient failed"
assert_file_contains "$(unit_file "$TEST_PREFIX-named")" "ExecStart=$TEST_ROOT/bin/$TEST_PREFIX"
assert_equals "active" "$(active_state "$TEST_PREFIX-named")" "promoted service state"

# --- mv: the journal must stop announcing the old name
bb mv "$TEST_PREFIX-named" "$TEST_PREFIX-moved" >/dev/null || fail "mv failed"
assert_file_contains "$(unit_file "$TEST_PREFIX-moved")" "Description=$TEST_PREFIX-moved"
[[ ! -e "$(unit_file "$TEST_PREFIX-named")" ]] || fail "mv kept the old unit file"
assert_equals "active" "$(active_state "$TEST_PREFIX-moved")" "state preserved across mv"
bb rm "$TEST_PREFIX-moved" >/dev/null || fail "rm after mv failed"

# --- the $EDITOR draft path still defines and enables
export VISUAL="$TEST_DIR/fixtures/bigbrother-editor"
export BIGBROTHER_TEST_BODY="[Unit]
Description=$TEST_PREFIX-draft

[Service]
ExecStart=$TEST_ROOT/bin/$TEST_PREFIX
WorkingDirectory=$TEST_ROOT

[Install]
WantedBy=default.target"
bb add "$TEST_PREFIX-draft" >/dev/null || fail "editor draft add failed"
assert_equals "active" "$(active_state "$TEST_PREFIX-draft")" "draft service state"
bb rm "$TEST_PREFIX-draft" >/dev/null || fail "rm of drafted service failed"
unset VISUAL BIGBROTHER_TEST_BODY

# --- a path is only ever a command now
if bb add "./$TEST_PREFIX" >/dev/null 2>&1; then
    fail "add accepted a bare path as a name"
fi
if bb enable "./$TEST_PREFIX" >/dev/null 2>&1; then
    fail "enable accepted a bare path"
fi

echo "  layer 2 (systemd) passed"
echo "bigbrother tests passed"
