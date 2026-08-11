#!/bin/sh
. /home/jeryd/Projects/idlescreen/packages/install_audit.sh

fail=0
check() {
    expected="$1"
    actual="$2"
    desc="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ok   $desc"
    else
        echo "  FAIL $desc"
        echo "       expected: $expected"
        echo "       actual:   $actual"
        fail=$((fail + 1))
    fi
}

check 'null'        "$(echo    | _audit_json_scalar '')"        'empty → null'
check 'true'        "$(echo    | _audit_json_scalar 'true')"   'true literal'
check 'false'       "$(echo    | _audit_json_scalar 'false')"  'false literal'
check '42'          "$(echo    | _audit_json_scalar '42')"     'integer'
check '0'           "$(echo    | _audit_json_scalar '0')"      'zero'
check '"hello"'     "$(echo    | _audit_json_scalar 'hello')"  'string quoted'
check '"a\"b"'      "$(echo    | _audit_json_scalar 'a"b')"    'quote escaped'
check '"a\\\\b"'    "$(echo    | _audit_json_scalar 'a\\b')"   'backslash escaped'

# F-202 regression — JSON spec requires \n escape
nl_input=$(printf 'line1\nline2')
nl_output=$(_audit_json_scalar "$nl_input")
case "$nl_output" in
    *'line1\nline2'*) echo "  ok   newline escaped to \\n" ;;
    *) echo "  FAIL newline NOT escaped; got: $nl_output"; fail=$((fail + 1)) ;;
esac

tab_input=$(printf 'a\tb')
tab_output=$(_audit_json_scalar "$tab_input")
case "$tab_output" in
    *'a\tb'*) echo "  ok   tab escaped to \\t" ;;
    *) echo "  FAIL tab NOT escaped; got: $tab_output"; fail=$((fail + 1)) ;;
esac

cr_input=$(printf 'a\rb')
cr_output=$(_audit_json_scalar "$cr_input")
case "$cr_output" in
    *'a\rb'*) echo "  ok   CR escaped to \\r" ;;
    *) echo "  FAIL CR NOT escaped; got: $cr_output"; fail=$((fail + 1)) ;;
esac

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
    exit 0
else
    echo "$fail check(s) failed"
    exit 1
fi
