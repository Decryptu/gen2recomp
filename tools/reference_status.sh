#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOCK_FILE="$REPO_ROOT/references.lock"
REFERENCE_ROOT="${GEN2_REFERENCE_ROOT:-"$REPO_ROOT/.references"}"
CHECK_REMOTE=false

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    printf 'Usage: %s [--remote] [reference-root]\n' "$0"
    exit 0
fi
for argument in "$@"; do
    if [[ "$argument" == "--remote" ]]; then
        CHECK_REMOTE=true
    else
        REFERENCE_ROOT="$argument"
    fi
done

lock_value() {
    local key="$1"
    awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$LOCK_FILE"
}

print_status() {
    local name="$1"
    local repository="$2"
    local revision="$3"
    local branch="$4"
    local destination="$REFERENCE_ROOT/$name"
    local state="missing"
    local local_revision="-"
    local remote_revision="-"

    if [[ -d "$destination/.git" ]]; then
        local configured_url
        configured_url="$(git -C "$destination" remote get-url origin 2>/dev/null || true)"
        local_revision="$(git -C "$destination" rev-parse HEAD 2>/dev/null || printf 'invalid')"
        if [[ "$configured_url" != "$repository" ]]; then
            state="origin-mismatch"
        elif [[ "$local_revision" != "$revision" ]]; then
            state="wrong-revision"
        elif [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
            state="dirty"
        else
            state="ok"
        fi
    fi

    if [[ "$CHECK_REMOTE" == true ]]; then
        remote_revision="$(git ls-remote "$repository" "refs/heads/$branch" 2>/dev/null | awk 'NR == 1 { print $1 }')"
        if [[ -z "$remote_revision" ]]; then
            remote_revision="unavailable"
        elif [[ "$remote_revision" != "$revision" ]]; then
            state="$state/upstream-moved"
        fi
    fi

    printf '%-12s %-22s local=%s' "$name" "$state" "$local_revision"
    if [[ "$CHECK_REMOTE" == true ]]; then
        printf ' remote=%s' "$remote_revision"
    fi
    printf '\n'
}

if [[ ! -f "$LOCK_FILE" ]]; then
    printf 'Missing lock file: %s\n' "$LOCK_FILE" >&2
    exit 1
fi

printf 'Reference root: %s\n' "$REFERENCE_ROOT"
for source_name in $(lock_value sources); do
    print_status \
        "$source_name" \
        "$(lock_value "${source_name}_repo")" \
        "$(lock_value "${source_name}_ref")" \
        "$(lock_value "${source_name}_branch")"
done
