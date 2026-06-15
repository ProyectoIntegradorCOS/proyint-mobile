#!/bin/bash
# build_release.sh — Incrementa build number y compila APK release
set -e

PUBSPEC="pubspec.yaml"

# Leer versión actual (ej: "1.0.0+5")
CURRENT=$(grep "^version:" "$PUBSPEC" | sed 's/version: //' | tr -d '[:space:]')
VERSION_NAME=$(echo "$CURRENT" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$CURRENT" | cut -d'+' -f2)

# Asegurar que BUILD_NUMBER sea un número válido
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  BUILD_NUMBER=1
fi

# Incrementar build number
NEW_BUILD=$((BUILD_NUMBER + 1))
NEW_VERSION="${VERSION_NAME}+${NEW_BUILD}"

# Actualizar pubspec.yaml
sed -i.bak "s/^version: .*/version: ${NEW_VERSION}/" "$PUBSPEC"
rm -f "${PUBSPEC}.bak"

echo "Compilando version $NEW_VERSION..."

flutter build apk --release \
  --build-number="$NEW_BUILD" \
  --dart-define=MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN} \
  --dart-define=MAPBOX_STYLE_ID=mapbox/streets-v12 \
  --dart-define=USE_MAPBOX_NATIVE_MAP=false \
  --dart-define=USE_NATIVE_NAVIGATION=true \
  --dart-define=API_BASE_URL=http://3.150.245.61:5511/api

echo "APK listo: build/app/outputs/flutter-apk/app-release.apk (v${NEW_VERSION})"
