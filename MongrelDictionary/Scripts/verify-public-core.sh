#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"
python3 "${SCRIPT_DIR}/verify-runtime.py" --edition public-core
python3 -m unittest discover -s Tests -p 'test_*.py' -v
xcodegen generate
mkdir -p build
xcodebuild -project MongrelDictionary.xcodeproj -scheme MongrelDictionary \
  -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build/core-verification \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  MONGREL_EDITION_SUFFIX=.corebeta 'MONGREL_DISPLAY_NAME=Mongrel Dictionary Core Beta' \
  MONGREL_URL_SCHEME=mongrel-dictionary-core \
  -only-testing:MongrelDictionaryTests/PublicCoreCorpusTests \
  -only-testing:MongrelDictionaryTests/DictionaryReliabilityTests \
  -only-testing:MongrelDictionaryTests/DictionarySessionStartupTests \
  -only-testing:MongrelDictionaryTests/DictionaryLookupRequestTests \
  -only-testing:MongrelDictionaryTests/AppearanceContrastTests \
  -only-testing:MongrelDictionaryTests/ReadingMetricsTests \
  test >build/core-verification.log 2>&1 || {
    tail -n 100 build/core-verification.log; exit 1;
  }
grep -E 'MONGREL_.*SOAK|Executed [0-9]+ tests|\*\* TEST SUCCEEDED \*\*' build/core-verification.log | tail -n 12
echo "Core corpus verification passed. This does not sign, install or publish an app."
