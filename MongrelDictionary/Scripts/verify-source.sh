#!/usr/bin/env bash
set -euo pipefail

# Verify the public application source without implying corpus/release coverage.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_BUILD_ROOT="${MONGREL_SOURCE_BUILD_ROOT:-${PROJECT_ROOT}/build/source-verification}"
HOST_ARCH="$(uname -m)"

case "${HOST_ARCH}" in
  arm64|x86_64) ;;
  *) echo "This verification requires a supported Mac." >&2; exit 1 ;;
esac
command -v xcodegen >/dev/null || { echo "XcodeGen is required." >&2; exit 1; }
xcodebuild -version >/dev/null
mkdir -p "${SOURCE_BUILD_ROOT}"
SOURCE_BUILD_ROOT="$(cd "${SOURCE_BUILD_ROOT}" && pwd)"
cd "${PROJECT_ROOT}"
xcodegen generate

echo "Building optimized universal application source (no corpus or installer claim)."
xcodebuild -project MongrelDictionary.xcodeproj -scheme MongrelDictionary \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "${SOURCE_BUILD_ROOT}/universal" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build >"${SOURCE_BUILD_ROOT}/build.log" 2>&1 || {
    tail -n 80 "${SOURCE_BUILD_ROOT}/build.log"; exit 1;
  }
APP_PATH="${SOURCE_BUILD_ROOT}/universal/Build/Products/Release/MongrelDictionary.app"
lipo "${APP_PATH}/Contents/MacOS/MongrelDictionary" -verify_arch arm64 x86_64
lipo "${APP_PATH}/Contents/Frameworks/MongrelDictionaryCore.framework/MongrelDictionaryCore" \
  -verify_arch arm64 x86_64

echo "Running native Release XCTest coverage with isolated fixtures."
# The remaining reliability tests use their own temporary SQLite/bundle fixtures.
# Corpus benchmarks and coverage tests must run separately with cleared data.
xcodebuild -project MongrelDictionary.xcodeproj -scheme MongrelDictionary \
  -configuration Release -destination "platform=macOS,arch=${HOST_ARCH}" \
  -derivedDataPath "${SOURCE_BUILD_ROOT}/tests" \
  ARCHS="${HOST_ARCH}" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  -only-testing:MongrelDictionaryTests/DictionarySessionStartupTests \
  -only-testing:MongrelDictionaryTests/DictionaryLookupRequestTests \
  -only-testing:MongrelDictionaryTests/AppearanceContrastTests \
  -only-testing:MongrelDictionaryTests/ReadingMetricsTests \
  -only-testing:MongrelDictionaryTests/DictionaryReliabilityTests \
  -skip-testing:MongrelDictionaryTests/DictionaryReliabilityTests/testDiverseCorpusSoakReachesABoundedWorkingSet \
  -skip-testing:MongrelDictionaryTests/DictionaryReliabilityTests/testComposedAndDecomposedAccentedLookupsAgree \
  -skip-testing:MongrelDictionaryTests/DictionaryReliabilityTests/testRepeatedMixedLookupsRemainConsistentAndCachesStayBounded \
  test >"${SOURCE_BUILD_ROOT}/tests.log" 2>&1 || {
    tail -n 120 "${SOURCE_BUILD_ROOT}/tests.log"; exit 1;
  }
grep -E 'Executed [0-9]+ tests|\*\* TEST SUCCEEDED \*\*' "${SOURCE_BUILD_ROOT}/tests.log" | tail -n 4
echo "Verified source build: ${APP_PATH}"
echo "Logs: ${SOURCE_BUILD_ROOT}"
echo "This is an unsigned source-validation build, not a notarized public Dictionary release."
