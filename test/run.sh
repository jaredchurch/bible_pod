#!/bin/bash
set -e

compare_files() {
    local folder="$1"
    local failed=0

    echo "Test: ${folder}"
    for expected in "test/$folder"/tniv_*.xml; do
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

pwsh ./src/run.ps1 -noUpload
compare_files "today"

pwsh ./src/run.ps1 -noUpload -allYear
compare_files "full_year"

