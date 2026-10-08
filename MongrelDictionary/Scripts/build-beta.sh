#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/release"
CONFIGURATION="Release"
BETA_NUMBER="6"
ARCHITECTURES="arm64 x86_64"
ARCH_LABEL="universal"
SIGNING_IDENTITY="${MONGREL_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${MONGREL_NOTARY_PROFILE:-}"
AD_HOC_SIGN=1
EDITION="evaluation"
EDITION_SUFFIX=""
APP_DISPLAY_NAME="Mongrel Dictionary"
URL_SCHEME="mongrel-dictionary"

usage() {
  cat <<'EOF'
Usage: build-beta.sh [options]

Builds a self-contained Mongrel Dictionary Beta as both ZIP and DMG.

Options:
  --beta-number NUMBER       Beta sequence number (default: 6)
  --edition public-core      Package the separately prepared English Core Beta
  --architecture universal  Build arm64 + x86_64 (default)
  --architecture arm64      Build Apple Silicon only
  --signing-identity NAME    Developer ID Application identity to use
  --notary-profile NAME      notarytool Keychain profile; requires Developer ID
  --output DIRECTORY         Artifact output directory
  --help                     Show this message

Environment equivalents:
  MONGREL_SIGNING_IDENTITY
  MONGREL_NOTARY_PROFILE

Without a Developer ID identity the script applies an ad-hoc signature. That
build is suitable for local Beta evaluation but macOS will identify it as an
unverified developer download. App-specific passwords are never accepted by
this script; store one in a notarytool Keychain profile instead.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --beta-number|--architecture|--signing-identity|--notary-profile|--output|--edition)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "$1 requires a value." >&2
        exit 2
      fi
      ;;
  esac
  case "$1" in
    --edition)
      if [[ "$2" != "public-core" && "$2" != "evaluation" ]]; then
        echo "Unknown edition: $2" >&2; exit 2
      fi
      EDITION="$2"
      shift 2
      ;;
    --beta-number)
      BETA_NUMBER="$2"
      shift 2
      ;;
    --architecture)
      case "$2" in
        universal)
          ARCHITECTURES="arm64 x86_64"
          ARCH_LABEL="universal"
          ;;
        arm64)
          ARCHITECTURES="arm64"
          ARCH_LABEL="arm64"
          ;;
        *)
          echo "Unsupported architecture: $2" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --signing-identity)
      SIGNING_IDENTITY="$2"
      AD_HOC_SIGN=0
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! "${BETA_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
  echo "--beta-number must be a positive integer." >&2
  exit 2
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  AD_HOC_SIGN=0
fi

if [[ -n "${NOTARY_PROFILE}" && "${AD_HOC_SIGN}" -eq 1 ]]; then
  echo "Notarization requires a Developer ID Application signing identity." >&2
  exit 2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required and must be selected with xcode-select." >&2
  exit 1
fi

cd "${PROJECT_ROOT}"
# XcodeGen expands the locally present, ignored corpus into the checked-in
# project. project.yml and all authored source must be committed; that generated
# resource list is deliberately not treated as an authored source change.
SOURCE_COMMIT="$(git rev-parse HEAD)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -n "${NOTARY_PROFILE}" && -n "$(git -C "${REPO_ROOT}" status --porcelain -- . ':(exclude)MongrelDictionary/MongrelDictionary.xcodeproj/project.pbxproj')" ]]; then
  echo "Commit source changes before producing a notarized release." >&2
  exit 1
fi
python3 "${SCRIPT_DIR}/verify-runtime.py" --edition "${EDITION}"
if [[ "${EDITION}" == "public-core" ]]; then
  EDITION_SUFFIX=".corebeta"
  APP_DISPLAY_NAME="Mongrel Dictionary Core Beta"
  URL_SCHEME="mongrel-dictionary-core"
fi
xcodegen generate >/tmp/mongrel_dictionary_beta_xcodegen.log 2>&1

xcodebuild -project MongrelDictionary.xcodeproj -scheme MongrelDictionary \
  -showBuildSettings >/tmp/mongrel_dictionary_beta_settings.log 2>&1
VERSION="$(awk '/ MARKETING_VERSION = / { print $3; exit }' /tmp/mongrel_dictionary_beta_settings.log)"
if [[ -z "${VERSION}" ]]; then
  echo "Could not determine MARKETING_VERSION." >&2
  exit 1
fi

PRODUCT_BASENAME="Mongrel-Dictionary-${VERSION}-beta.${BETA_NUMBER}-macOS-${ARCH_LABEL}"
if [[ "${EDITION}" == "public-core" ]]; then
  PRODUCT_BASENAME="Mongrel-Dictionary-Core-${VERSION}-beta.${BETA_NUMBER}-macOS-${ARCH_LABEL}"
fi
STAGING_ROOT="$(mktemp -d /tmp/mongrel-dictionary-beta.XXXXXX)"
DERIVED_DATA_PATH="${STAGING_ROOT}/derived"
APP_SOURCE="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/MongrelDictionary.app"
APP_STAGED="${STAGING_ROOT}/${APP_DISPLAY_NAME}.app"
DMG_ROOT="${STAGING_ROOT}/disk-image"
ZIP_PATH="${OUTPUT_DIR}/${PRODUCT_BASENAME}.zip"
DMG_PATH="${OUTPUT_DIR}/${PRODUCT_BASENAME}.dmg"

cleanup() {
  echo "Build staging retained for verification: ${STAGING_ROOT}"
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}" "${DMG_ROOT}"
if [[ -e "${ZIP_PATH}" || -e "${DMG_PATH}" ]]; then
  echo "This release already exists. Choose a new Beta number or output directory." >&2
  exit 2
fi

echo "[1/7] Building ${PRODUCT_BASENAME}"
xcodebuild \
  -project MongrelDictionary.xcodeproj \
  -scheme MongrelDictionary \
  -configuration "${CONFIGURATION}" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  ARCHS="${ARCHITECTURES}" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MONGREL_EDITION_SUFFIX="${EDITION_SUFFIX}" \
  MONGREL_DISPLAY_NAME="${APP_DISPLAY_NAME}" \
  MONGREL_URL_SCHEME="${URL_SCHEME}" \
  build >/tmp/mongrel_dictionary_beta_build.log 2>&1

if [[ ! -d "${APP_SOURCE}" ]]; then
  echo "Build succeeded but the app product was not found at ${APP_SOURCE}." >&2
  exit 1
fi

ditto "${APP_SOURCE}" "${APP_STAGED}"

# Identify the exact source used to produce the executable, before signing.
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_STAGED}/Contents/Info.plist")"
printf 'Source commit: %s\nBuild: %s\nArchitectures: %s\nEdition: %s\nMinimum macOS: 14.0\n' \
  "${SOURCE_COMMIT}" "${BUILD_NUMBER}" "${ARCHITECTURES}" "${EDITION}" \
  >"${APP_STAGED}/Contents/Resources/BUILD-INFO.txt"
cp "${APP_STAGED}/Contents/Resources/BUILD-INFO.txt" "${OUTPUT_DIR}/BUILD-INFO.txt"
cp "${REPO_ROOT}/LICENSE" "${APP_STAGED}/Contents/Resources/APP-LICENSE.txt"
cp "${REPO_ROOT}/NOTICE.md" "${APP_STAGED}/Contents/Resources/APP-NOTICE.txt"
if [[ "${EDITION}" == "public-core" ]]; then
  cp "${PROJECT_ROOT}/App/Data/OfflineArchives/PUBLIC-CORPUS.json" "${OUTPUT_DIR}/PUBLIC-CORPUS.json"
fi

echo "[2/7] Signing application"
if [[ "${AD_HOC_SIGN}" -eq 1 ]]; then
  SIGNING_LABEL="ad-hoc"
  SIGNING_ARGS=(--force --sign -)
else
  SIGNING_LABEL="Developer ID"
  SIGNING_ARGS=(--force --options runtime --timestamp --sign "${SIGNING_IDENTITY}")
fi

if [[ -d "${APP_STAGED}/Contents/Frameworks" ]]; then
  while IFS= read -r framework; do
    codesign "${SIGNING_ARGS[@]}" "${framework}"
  done < <(find "${APP_STAGED}/Contents/Frameworks" -type d -name '*.framework' -prune -print)
fi

codesign "${SIGNING_ARGS[@]}" \
  --entitlements "${PROJECT_ROOT}/App/MongrelDictionary.entitlements" \
  "${APP_STAGED}"
codesign --verify --deep --strict --verbose=2 "${APP_STAGED}"

for architecture in ${ARCHITECTURES}; do
  lipo "${APP_STAGED}/Contents/MacOS/MongrelDictionary" -verify_arch "${architecture}"
  lipo "${APP_STAGED}/Contents/Frameworks/MongrelDictionaryCore.framework/Versions/A/MongrelDictionaryCore" -verify_arch "${architecture}"
done

echo "[3/7] Preparing notarized application"
if [[ -n "${NOTARY_PROFILE}" ]]; then
  # Staple the app BEFORE copying it into the DMG. The installed app must carry
  # its own ticket when the first launch happens without an internet connection.
  NOTARY_ZIP="${STAGING_ROOT}/notarize-app.zip"
  ditto -c -k --sequesterRsrc --keepParent "${APP_STAGED}" "${NOTARY_ZIP}"
  xcrun notarytool submit "${NOTARY_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${APP_STAGED}"
  xcrun stapler validate "${APP_STAGED}"
  spctl --assess --type execute --verbose=2 "${APP_STAGED}"
else
  echo "      Notarization skipped (${SIGNING_LABEL} build)"
fi

echo "[4/7] Creating DMG"
ditto "${APP_STAGED}" "${DMG_ROOT}/${APP_DISPLAY_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
printf '%s\n' \
  'Mongrel Dictionary Beta' \
  '' \
  "Drag ${APP_DISPLAY_NAME} to Applications." \
  'This build works entirely offline after installation.' \
  '' \
  "Signing: ${SIGNING_LABEL}" \
  >"${DMG_ROOT}/README-FIRST.txt"
if [[ "${EDITION}" == "public-core" ]]; then
  cp "${PROJECT_ROOT}/App/Data/OfflineArchives/CORPUS-NOTICES.txt" "${DMG_ROOT}/CORPUS-NOTICES.txt"
  printf '\nCore Beta includes English definitions and synonyms only. It uses a separate app identity and does not replace the evaluation Dictionary.\n' >>"${DMG_ROOT}/README-FIRST.txt"
fi
hdiutil create \
  -volname "Mongrel Dictionary Beta" \
  -srcfolder "${DMG_ROOT}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DMG_PATH}" >/tmp/mongrel_dictionary_beta_dmg.log 2>&1

if [[ "${AD_HOC_SIGN}" -eq 0 ]]; then
  echo "Signing DMG container"
  codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"
  codesign --verify --strict --verbose=2 "${DMG_PATH}"
fi

if [[ -n "${NOTARY_PROFILE}" ]]; then
  echo "[5/7] Notarizing and stapling DMG"
  xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
else
  echo "[5/7] Notarization skipped (${SIGNING_LABEL} build)"
fi

echo "[6/7] Creating ZIP"
ditto -c -k --sequesterRsrc --keepParent "${APP_STAGED}" "${ZIP_PATH}"

echo "[7/7] Writing checksums"
(
  cd "${OUTPUT_DIR}"
  shasum -a 256 "$(basename "${ZIP_PATH}")" "$(basename "${DMG_PATH}")" >SHA256SUMS.txt
)

APP_SIZE="$(du -sh "${APP_STAGED}" | awk '{ print $1 }')"
ZIP_SIZE="$(du -h "${ZIP_PATH}" | awk '{ print $1 }')"
DMG_SIZE="$(du -h "${DMG_PATH}" | awk '{ print $1 }')"

echo
echo "Beta package complete"
echo "  App: ${APP_SIZE} (${ARCH_LABEL}, ${SIGNING_LABEL})"
echo "  ZIP: ${ZIP_PATH} (${ZIP_SIZE})"
echo "  DMG: ${DMG_PATH} (${DMG_SIZE})"
echo "  SHA: ${OUTPUT_DIR}/SHA256SUMS.txt"
echo "  Build log: /tmp/mongrel_dictionary_beta_build.log"
