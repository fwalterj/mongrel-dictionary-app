#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="/tmp/mongrel_dictionary_derived_data"
STATE_DIR="/tmp/mongrel_dictionary_smoke_state"
TIER="daily"
FORCE_REBUILD=0
FORCE_CLEAN=0
REBUILD_CORPUS=0

cd "${PROJECT_ROOT}"

usage() {
  cat <<'EOF'
Usage: smoke-test.sh [--tier quick|daily|deep|editorial|full] [--force] [--clean] [--rebuild-corpus] [--help]

Tiers:
  quick
    Small canary pass for rapid confidence. Runs:
    - quick_canary

  daily
    Fast confidence pass for day-to-day utility work. Runs:
    - inventory
    - note_behavior

  deep
    Heavier search-quality pass for fuzzy lookup, suggestions, and note-mesh behavior. Runs:
    - deep_behavior

  editorial
    Broader corpus and content-verification pass. Runs:
    - regional_coverage
    - longman_coverage
    - glossary_coverage

  full
    Runs daily, deep, and editorial shards.

Options:
  --force
    Re-run validation, Xcode project generation, and build steps
    even if the runner believes cached outputs are still fresh.

  --clean
    Remove cached derived data and smoke state before running.

  --rebuild-corpus
    Regenerate lexical archives from local upstream inputs (not included in Git).
    Ordinary tests and CI use the checked-in runtime archives without modifying them.
EOF
}

any_newer_than() {
  local target="$1"
  shift

  if [[ ! -e "${target}" ]]; then
    return 0
  fi

  local path
  for path in "$@"; do
    [[ -e "${path}" ]] || continue
    if [[ -d "${path}" ]]; then
      if find "${path}" -type f -newer "${target}" -print -quit | grep -q .; then
        return 0
      fi
    else
      if [[ "${path}" -nt "${target}" ]]; then
        return 0
      fi
    fi
  done

  return 1
}

first_xctestrun_path() {
  find "${DERIVED_DATA_PATH}" -name '*.xctestrun' -print -quit 2>/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      if [[ $# -lt 2 ]]; then
        echo "--tier requires a value"
        usage
        exit 1
      fi
      TIER="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --force)
      FORCE_REBUILD=1
      shift
      ;;
    --clean)
      FORCE_CLEAN=1
      shift
      ;;
    --rebuild-corpus)
      REBUILD_CORPUS=1
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

case "${TIER}" in
  quick|daily|deep|editorial|full)
    ;;
  *)
    echo "Unsupported tier: ${TIER}"
    usage
    exit 1
    ;;
esac

mkdir -p "${STATE_DIR}"

if [[ "${FORCE_CLEAN}" -eq 1 ]]; then
  xcrun swift "${SCRIPT_DIR}/trash-items.swift" "${DERIVED_DATA_PATH}" "${STATE_DIR}"
  mkdir -p "${STATE_DIR}"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to validate reference notes"
  exit 1
fi

REFERENCE_VALIDATION_STAMP="${STATE_DIR}/reference_notes_validation.stamp"
REFERENCE_ARCHIVE="${PROJECT_ROOT}/App/Data/OfflineArchives/ReferenceNotes.mgrt"
RUNTIME_ARCHIVE_SENTINEL="${PROJECT_ROOT}/App/Data/OfflineArchives/SearchLexicon.mgrt"
PROJECT_FILE="${PROJECT_ROOT}/MongrelDictionary.xcodeproj/project.pbxproj"
BUILD_STAMP="${STATE_DIR}/build_for_testing.stamp"
HAS_XCODEGEN=1

if ! command -v xcodegen >/dev/null 2>&1; then
  HAS_XCODEGEN=0
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is unavailable with the active developer directory."
  echo "Install full Xcode and select it, for example:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "[1/6] Validating reference notes"
if [[ "${FORCE_REBUILD}" -eq 1 ]] || any_newer_than "${REFERENCE_VALIDATION_STAMP}" \
  "${PROJECT_ROOT}/Scripts/validate-reference-notes.py" \
  "${PROJECT_ROOT}/ReferenceNotesAuthoring"; then
  python3 "${PROJECT_ROOT}/Scripts/validate-reference-notes.py"
  touch "${REFERENCE_VALIDATION_STAMP}"
  echo "      notes passed"
else
  echo "      notes validation unchanged; skipping"
fi

echo "[2/6] Compiling reference-note archive"
if [[ "${REBUILD_CORPUS}" -eq 1 ]]; then
  python3 "${PROJECT_ROOT}/Scripts/compile-reference-notes.py"
  echo "      notes archive built"
else
  echo "      using checked-in notes archive"
fi

echo "[3/6] Compiling offline runtime archives"
if [[ "${REBUILD_CORPUS}" -eq 1 ]]; then
  python3 "${PROJECT_ROOT}/Scripts/compile-offline-runtime.py"
  echo "      runtime archives built"
else
  echo "      using checked-in runtime archives"
fi
python3 "${PROJECT_ROOT}/Scripts/verify-runtime.py"

echo "[4/6] Regenerating Xcode project"
if [[ "${FORCE_REBUILD}" -eq 1 ]] || any_newer_than "${PROJECT_FILE}" \
  "${PROJECT_ROOT}/project.yml" \
  "${PROJECT_ROOT}/App" \
  "${PROJECT_ROOT}/Tests"; then
  if [[ "${HAS_XCODEGEN}" -eq 0 ]]; then
    echo "xcodegen is required to regenerate the project. Install with: brew install xcodegen"
    exit 1
  fi
  xcodegen generate >/tmp/mongrel_dictionary_xcodegen.log 2>&1
  echo "      done"
else
  if [[ "${HAS_XCODEGEN}" -eq 0 ]]; then
    echo "      xcodegen not installed; using existing generated project"
  fi
  echo "      project unchanged; skipping"
fi

XCTESTRUN_PATH="$(first_xctestrun_path || true)"

echo "[5/6] Building MongrelDictionary for testing"
if [[ "${FORCE_REBUILD}" -eq 1 ]] || [[ ! -f "${BUILD_STAMP}" ]] || [[ -z "${XCTESTRUN_PATH}" ]] || any_newer_than "${BUILD_STAMP}" \
  "${PROJECT_ROOT}/project.yml" \
  "${PROJECT_ROOT}/MongrelDictionary.xcodeproj/project.pbxproj" \
  "${PROJECT_ROOT}/App" \
  "${PROJECT_ROOT}/Tests" \
  "${PROJECT_ROOT}/Scripts"; then
  xcrun swift "${SCRIPT_DIR}/trash-items.swift" "${DERIVED_DATA_PATH}"
  xcodebuild -project MongrelDictionary.xcodeproj \
    -scheme MongrelDictionary \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build-for-testing >/tmp/mongrel_dictionary_build.log 2>&1
  touch "${BUILD_STAMP}"
  XCTESTRUN_PATH="$(first_xctestrun_path)"
  echo "      build passed"
else
  echo "      build outputs unchanged; skipping"
fi

if [[ -z "${XCTESTRUN_PATH}" ]]; then
  echo "Could not locate .xctestrun output under ${DERIVED_DATA_PATH}"
  exit 1
fi

echo "[6/6] Running ${TIER} smoke tier"

declare -a QUICK_SHARDS=(
  "quick_canary:MongrelDictionaryTests/DictionaryQuickCanarySmokeTests"
)

declare -a DAILY_SHARDS=(
  "session:MongrelDictionaryTests/DictionarySessionStartupTests|MongrelDictionaryTests/DictionaryReliabilityTests"
  "appearance:MongrelDictionaryTests/AppearanceContrastTests|MongrelDictionaryTests/ReadingMetricsTests"
  "integration:MongrelDictionaryTests/DictionaryLookupRequestTests"
  "inventory:MongrelDictionaryTests/DictionaryInventorySmokeTests"
  "note_behavior:MongrelDictionaryTests/DictionaryReferenceNoteBehaviorSmokeTests|MongrelDictionaryTests/DictionaryPhraseBehaviorSmokeTests"
)

declare -a DEEP_SHARDS=(
  "deep_behavior:MongrelDictionaryTests/DictionaryDeepLookupSmokeTests|MongrelDictionaryTests/DictionaryLexicalIngestionDeepSmokeTests|MongrelDictionaryTests/DictionaryLexicalBehaviorDeepSmokeTests"
)

declare -a EDITORIAL_SHARDS=(
  "regional_coverage:MongrelDictionaryTests/DictionaryRegionalCoverageSmokeTests"
  "longman_coverage:MongrelDictionaryTests/DictionaryLongmanCoverageSmokeTests"
  "glossary_coverage:MongrelDictionaryTests/DictionaryGlossaryCoverageSmokeTests"
)

declare -a TEST_SHARDS=()
case "${TIER}" in
  quick)
    TEST_SHARDS=("${QUICK_SHARDS[@]}")
    ;;
  daily)
    TEST_SHARDS=("${DAILY_SHARDS[@]}")
    ;;
  deep)
    TEST_SHARDS=("${DEEP_SHARDS[@]}")
    ;;
  editorial)
    TEST_SHARDS=("${EDITORIAL_SHARDS[@]}")
    ;;
  full)
    TEST_SHARDS=("${DAILY_SHARDS[@]}" "${DEEP_SHARDS[@]}" "${EDITORIAL_SHARDS[@]}")
    ;;
esac

: >/tmp/mongrel_dictionary_test.log

echo "      selected shards:"
for shard in "${TEST_SHARDS[@]}"; do
  echo "        - ${shard%%:*}"
done

for shard in "${TEST_SHARDS[@]}"; do
  shard_name="${shard%%:*}"
  shard_target="${shard#*:}"
  shard_log="/tmp/mongrel_dictionary_test_${shard_name}.log"
  IFS='|' read -r -a shard_targets <<< "${shard_target}"
  xcodebuild_args=(
    -xctestrun "${XCTESTRUN_PATH}"
    -destination 'platform=macOS'
    test-without-building
  )
  for target in "${shard_targets[@]}"; do
    xcodebuild_args+=(-only-testing:"${target}")
  done

  echo "      shard ${shard_name}"
  if ! xcodebuild "${xcodebuild_args[@]}" >"${shard_log}" 2>&1; then
    cat "${shard_log}" >>/tmp/mongrel_dictionary_test.log
    echo "Shard '${shard_name}' failed. See ${shard_log}"
    grep -E 'error:|failed -|Executed .+ tests?|\*\* TEST SUCCEEDED \*\*|\*\* TEST FAILED \*\*|Test Case .+ passed|Test Case .+ failed' "${shard_log}" || true
    exit 1
  fi

  cat "${shard_log}" >>/tmp/mongrel_dictionary_test.log
  grep -E '\*\* TEST SUCCEEDED \*\*|Test Case .+ passed' "${shard_log}" | tail -n 5 || true
done

echo "Smoke run complete."
echo "Logs:"
echo "  /tmp/mongrel_dictionary_xcodegen.log"
echo "  /tmp/mongrel_dictionary_build.log"
echo "  /tmp/mongrel_dictionary_test.log"
for shard in "${TEST_SHARDS[@]}"; do
  shard_name="${shard%%:*}"
  echo "  /tmp/mongrel_dictionary_test_${shard_name}.log"
done
