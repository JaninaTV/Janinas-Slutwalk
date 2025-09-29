#!/usr/bin/env bash
set -euo pipefail

echo "==> Schritt 1/6: Java & Tools prüfen"
if ! java -version >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y openjdk-17-jdk
fi

echo "==> Schritt 2/6: ANDROID SDK einrichten"
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT"

# Commandline-Tools (falls fehlen)
if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "   • Lade cmdline-tools (latest)…"
  cd "$ANDROID_SDK_ROOT"
  curl -fsSL -o cmdline-tools.zip \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  mkdir -p cmdline-tools/latest
  unzip -q cmdline-tools.zip -d cmdline-tools/latest
  # Zip enthält den Ordner 'cmdline-tools'; wir wollen die Binärdateien direkt unter 'latest'
  if [ -d cmdline-tools/latest/cmdline-tools ]; then
    mv cmdline-tools/latest/cmdline-tools/* cmdline-tools/latest/ || true
    rmdir cmdline-tools/latest/cmdline-tools || true
  fi
  rm -f cmdline-tools.zip
fi

SDKMGR="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKMGR" --licenses >/dev/null || true

echo "==> Schritt 3/6: Fehlende Android-Pakete installieren"
PACKAGES=(
  "platform-tools"
  "platforms;android-34"
  "build-tools;34.0.0"
)
"$SDKMGR" "${PACKAGES[@]}"

echo "==> Schritt 4/6: local.properties setzen"
cat > local.properties <<PROP
sdk.dir=$ANDROID_SDK_ROOT
PROP

echo "==> Schritt 5/6: Gradle-Wrapper auf 8.7 setzen (Android-Plugin verlangt ≥8.7)"
if [ -d gradle/wrapper ]; then
  sed -i 's#distributionUrl=.*#distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-all.zip#' gradle/wrapper/gradle-wrapper.properties
fi

echo "==> Schritt 6/6: Projekt aufräumen & bauen"
if [ -x ./gradlew ]; then
  ./gradlew --stop >/dev/null 2>&1 || true
  ./gradlew -v >/dev/null || true
else
  echo "   • gradlew fehlt? Erzeuge Wrapper…"
  gradle wrapper --gradle-version 8.7 --distribution-type all
fi

# Build mit Logausgabe
set +e
./gradlew clean :app:assembleDebug --no-daemon --stacktrace
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "Build fehlgeschlagen (Exitcode $RC). Oben stehen die Ursachen."
  echo "Hilfreich ist oft: ./gradlew --stacktrace -i :app:assembleDebug"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  exit $RC
fi

echo ""
echo "========================================="
echo "✅ Build erfolgreich. APK sollte liegen in:"
echo "   app/build/outputs/apk/debug/*.apk"
echo "========================================="
