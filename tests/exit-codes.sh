#!/bin/bash
#
# Integration test for Cli.Program's Outcome -> exit-code mapping.
#
# Cli.Program isn't covered by the pure gren-lang/test suite (it does I/O and
# sets the process exit code), so we exercise it through the with-permissions
# example, which routes all three outcomes through one `count` command:
#
#   * non-empty file -> Cli.Program.Succeeded -> exit 0
#   * empty file     -> Cli.Program.Failed    -> exit 1, note on stderr
#   * missing file   -> task fails             -> exit 1, error on stderr
#
# Run from anywhere: ./exit-codes.sh

set -u

cd "$(dirname "$0")/../examples/with-permissions"
gren make Main --output=app >/dev/null

failures=0

# check <label> <expected-code> <expected-stream:out|err> <command...>
check() {
    local label="$1" expected_code="$2" stream="$3"
    shift 3

    local out err code
    out="$(node app "$@" 2>/tmp/cli-exit-codes.err)"
    code=$?
    err="$(cat /tmp/cli-exit-codes.err)"

    if [ "$code" -ne "$expected_code" ]; then
        echo "FAIL: $label — expected exit $expected_code, got $code"
        failures=$((failures + 1))
        return
    fi

    if [ "$stream" = "out" ] && { [ -z "$out" ] || [ -n "$err" ]; }; then
        echo "FAIL: $label — expected output on stdout only (out=[$out] err=[$err])"
        failures=$((failures + 1))
        return
    fi

    if [ "$stream" = "err" ] && { [ -n "$out" ] || [ -z "$err" ]; }; then
        echo "FAIL: $label — expected output on stderr only (out=[$out] err=[$err])"
        failures=$((failures + 1))
        return
    fi

    echo "ok: $label (exit $code)"
}

check "non-empty file succeeds" 0 out count gren.json
check "empty file fails quietly"  1 err count /dev/null
check "missing file errors"       1 err count /no/such/file

rm -f /tmp/cli-exit-codes.err

if [ "$failures" -ne 0 ]; then
    echo
    echo "EXIT-CODE TESTS FAILED ($failures)"
    exit 1
fi

echo
echo "EXIT-CODE TESTS PASSED"
