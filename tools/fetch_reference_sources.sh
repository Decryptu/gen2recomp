#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LOCK_FILE="$REPO_ROOT/references.lock"
REFERENCE_ROOT="${GEN2_REFERENCE_ROOT:-"$REPO_ROOT/.references"}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    printf 'Usage: %s [reference-root]\n' "$0"
    exit 0
fi
if [[ $# -ge 1 ]]; then
    REFERENCE_ROOT="$1"
fi

if [[ ! -f "$LOCK_FILE" ]]; then
    printf 'Missing lock file: %s\n' "$LOCK_FILE" >&2
    exit 1
fi

lock_value() {
    local key="$1"
    awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$LOCK_FILE"
}

sync_source() {
    local name="$1"
    local repository="$2"
    local revision="$3"
    local destination="$REFERENCE_ROOT/$name"
    local local_revision

    if [[ -e "$destination" && ! -d "$destination/.git" ]]; then
        printf 'Refusing non-repository path: %s\n' "$destination" >&2
        exit 1
    fi

    if [[ ! -d "$destination/.git" ]]; then
        mkdir -p "$REFERENCE_ROOT"
        printf 'Cloning %s into %s\n' "$name" "$destination"
        git clone --filter=blob:none --no-checkout "$repository" "$destination"
    else
        local configured_url
        configured_url="$(git -C "$destination" remote get-url origin)"
        if [[ "$configured_url" != "$repository" ]]; then
            printf 'Origin mismatch for %s: %s\n' "$name" "$configured_url" >&2
            exit 1
        fi
        if [[ -n "$(git -C "$destination" status --porcelain)" ]]; then
            printf 'Refusing checkout with local edits: %s\n' "$destination" >&2
            exit 1
        fi
    fi

    git -C "$destination" fetch --prune origin "$revision"
    git -C "$destination" checkout --detach "$revision"
    local_revision="$(git -C "$destination" rev-parse HEAD)"
    if [[ "$local_revision" != "$revision" ]]; then
        printf 'Revision mismatch for %s: expected %s, got %s\n' \
            "$name" "$revision" "$local_revision" >&2
        exit 1
    fi
    printf '%s %s\n' "$name" "$local_revision"
}

for source_name in $(lock_value sources); do
    sync_source \
        "$source_name" \
        "$(lock_value "${source_name}_repo")" \
        "$(lock_value "${source_name}_ref")"
done
