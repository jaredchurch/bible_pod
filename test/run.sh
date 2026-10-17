#!/bin/bash
set -e

compare_files() {
    local failed=0

    echo "Test Results:"
    for expected in "test"/tniv_*.xml; do
        base=$(basename "$expected")
        if [ -f "./$base" ]; then
            if diff -q "$expected" "./$base" > /dev/null 2>&1; then
                echo "PASS: $base matches"
            else
                echo "FAIL: $base differs"
                # diff "$expected" "./$base" || true
                failed=1
            fi
        else
            echo "FAIL: $base not found"
            failed=1
        fi
    done

    return $failed
}

cd "$(dirname "$0")/.."

# pwsh ./src/run.ps1 -noUpload
compare_files
