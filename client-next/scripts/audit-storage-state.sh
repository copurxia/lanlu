#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODEL_FILE="${SCRIPT_DIR}/../src/app/model.cj"
readonly READER_MODEL_FILE="${SCRIPT_DIR}/../src/app/reader_model.cj"
readonly SETTINGS_FILE="${SCRIPT_DIR}/../src/app/settings.cj"
readonly EXPECTED_COLLECTION_STATES=18

actual="$(rg --count-matches 'State<(ArrayList|HashMap|HashSet)<' "${MODEL_FILE}")"

if [[ "${actual}" != "${EXPECTED_COLLECTION_STATES}" ]]; then
    echo "storage-state audit failed: expected ${EXPECTED_COLLECTION_STATES}, found ${actual}" >&2
    echo "Update the migration inventory and this baseline intentionally when a collection State changes." >&2
    exit 1
fi

if rg -q 'servers\s*=\s*ArrayList<ServerProfile>|writeName\("list"\)' "${SETTINGS_FILE}"; then
    echo "storage-state audit failed: ServerProfile regressed to an embedded array/table" >&2
    exit 1
fi

if rg -q 'State<ArrayList<PageInfo>>' "${MODEL_FILE}" ||
    rg -q 'private var pageList\s*=\s*ArrayList<PageInfo>' "${READER_MODEL_FILE}"; then
    echo "storage-state audit failed: PageInfo regressed to duplicated long-lived arrays" >&2
    exit 1
fi

if rg -q 'State<ArrayList<SearchItem>>' "${MODEL_FILE}" ||
    rg -q 'public var items\s*=\s*ArrayList<SearchItem>' "${MODEL_FILE}"; then
    echo "storage-state audit failed: SearchItem regressed to duplicated long-lived arrays" >&2
    exit 1
fi

if rg -q 'State<ArrayList<TankoubonInfo>>' "${MODEL_FILE}"; then
    echo "storage-state audit failed: TankoubonInfo regressed to duplicated long-lived arrays" >&2
    exit 1
fi

if rg -q 'detailTagTranslations\s*=\s*State<HashMap<String, String>>' "${MODEL_FILE}"; then
    echo "storage-state audit failed: TagTranslation regressed to a long-lived map" >&2
    exit 1
fi

echo "storage-state audit passed: ${actual} long-lived collection States; ServerProfile/PageInfo/SearchItem/TankoubonInfo/TagTranslation are repository-backed"
