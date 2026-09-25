#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="/tmp/mongrel_dictionary_startup_derived_data"
STATE_DIR="/tmp/mongrel_dictionary_startup_state"
PROJECT_FILE="${PROJECT_ROOT}/MongrelDictionary.xcodeproj/project.pbxproj"
BUILD_STAMP="${STATE_DIR}/build_for_testing.stamp"
BENCH_LOG="/tmp/mongrel_dictionary_startup_benchmark.log"
BENCH_JSON="/tmp/mongrel_dictionary_startup_benchmark.json"
HAS_XCODEGEN=1
FORCE_REBUILD=0

cd "${PROJECT_ROOT}"

usage() {
  cat <<'EOF'
Usage: benchmark-startup.sh [--force] [--help]

Runs a deterministic local startup benchmark for Mongrel Dictionary and prints
launch-to-ready and launch-to-first-result timings for the session startup seam.

Options:
  --force   Rebuild test artifacts and regenerate Xcode project.
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
    --help|-h)
      usage
      exit 0
      ;;
    --force)
      FORCE_REBUILD=1
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${STATE_DIR}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is unavailable with the active developer directory."
  echo "Install/select full Xcode, then rerun."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  HAS_XCODEGEN=0
fi

echo "[1/4] Preparing project files"
if [[ "${FORCE_REBUILD}" -eq 1 ]] || any_newer_than "${PROJECT_FILE}" \
  "${PROJECT_ROOT}/project.yml" \
  "${PROJECT_ROOT}/App" \
  "${PROJECT_ROOT}/Tests"; then
  if [[ "${HAS_XCODEGEN}" -eq 0 ]]; then
    echo "xcodegen is required to regenerate the project. Install with: brew install xcodegen"
    exit 1
  fi
  xcodegen generate >/tmp/mongrel_dictionary_startup_xcodegen.log 2>&1
  echo "      regenerated"
else
  echo "      unchanged"
fi

XCTESTRUN_PATH="$(first_xctestrun_path || true)"

echo "[2/4] Building tests (if needed)"
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
    build-for-testing >/tmp/mongrel_dictionary_startup_build.log 2>&1
  touch "${BUILD_STAMP}"
  XCTESTRUN_PATH="$(first_xctestrun_path)"
  echo "      build passed"
else
  echo "      build cache reused"
fi

if [[ -z "${XCTESTRUN_PATH}" ]]; then
  echo "Could not locate .xctestrun output under ${DERIVED_DATA_PATH}"
  exit 1
fi

echo "[3/4] Running startup benchmark test"
xcodebuild \
  -xctestrun "${XCTESTRUN_PATH}" \
  -destination 'platform=macOS' \
  test-without-building \
  -only-testing:MongrelDictionaryTests/DictionaryStartupBenchmarkTests \
  >"${BENCH_LOG}" 2>&1

echo "[4/4] Summarizing results"
python3 - "${BENCH_LOG}" "${BENCH_JSON}" <<'PY'
import json
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])

payload = None
for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if "MONGREL_STARTUP_BENCHMARK::" in line:
        payload = line.split("MONGREL_STARTUP_BENCHMARK::", 1)[1].strip()

if not payload:
    print(f"Failed to find benchmark payload in {log_path}")
    sys.exit(1)

report = json.loads(payload)
json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

print(f"Timestamp: {report['timestamp']}")
print(f"Rounds per metric: {report['rounds']}")
print("")
print("metric                           cold  median  p95  min  max  n")
for metric in report["metrics"]:
    print(
        f"{metric['name']:<32}"
        f"{metric['coldMS']:>5}ms"
        f"{metric['medianMS']:>7}ms"
        f"{metric['p95MS']:>6}ms"
        f"{metric['minMS']:>5}ms"
        f"{metric['maxMS']:>5}ms"
        f"{metric['samples']:>4}"
    )

print("")
print(f"Raw benchmark log: {log_path}")
print(f"JSON summary: {json_path}")
PY
