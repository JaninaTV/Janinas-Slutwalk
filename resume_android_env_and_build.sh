#!/usr/bin/env bash
set -euo pipefail

echo "==> Diagnose…"
JAVA_BIN="$(command -v java || true)"
echo "JAVA  : ${JAVA_BIN:-not found}"
echo "PWD   : $(pwd)"

# Prefer $HOME/android-sdk (wie im vorherigen Setup)
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

mkdir -p "$ANDROID_HOME"

need_cmdline_tools=0
if ! command -v sdkmanager >/dev/null 2>&1; then
  echo "==> sdkmanager fehlt – cmdline-tools werden installiert…"
  need_cmdline_tools=1
fi

if [ "$need_cmdline_tools" -eq 1 ]; then
  sudo apt-get update -y
  sudo apt-get install -y unzip curl
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  tmpdir="$(mktemp -d)"
  echo "==> Lade Android cmdline-tools…"
  curl -L -o "$tmpdir/commandlinetools.zip" \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -qo "$tmpdir/commandlinetools.zip" -d "$tmpdir"
  # in Struktur …/cmdline-tools/latest/ verschieben
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
  mv "$tmpdir/cmdline-tools/"* "$ANDROID_HOME/cmdline-tools/latest/"
  rm -rf "$tmpdir"
fi

echo "==> sdkmanager Version:"
sdkmanager --version || true

echo "==> Akzeptiere Lizenzen…"
yes | sdkmanager --licenses >/dev/null

echo "==> Installiere/aktualisiere SDK Pakete…"
sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34" >/dev/null

# local.properties sichern/setzen
if [ ! -f local.properties ]; then
  echo "==> Schreibe local.properties…"
  echo "sdk.dir=${ANDROID_HOME}" > local.properties
fi

# Gradle Wrapper sicherstellen
if [ -x ./gradlew ]; then
  echo "==> gradlew ist ausführbar."
else
  if [ -f ./gradlew ]; then
    echo "==> Setze Ausführungsrecht für gradlew…"
    chmod +x ./gradlew
  else
    echo "==> gradlew fehlt – erzeuge Wrapper…"
    # Falls gradle CLI nicht vorinstalliert ist, installieren
    if ! command -v gradle >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y gradle
    fi
    gradle wrapper
    chmod +x ./gradlew
  fi
fi

echo "==> Clean & Build (Debug)…"
mkdir -p build/reports
set +e
./gradlew --stop >/dev/null 2>&1
./gradlew -S -i clean :app:assembleDebug | tee build/reports/build_last.log
status="${PIPESTATUS[0]}"
set -e

if [ "$status" -ne 0 ]; then
  echo "==> Build FEHLGESCHLAGEN. Zeige letzte 120 Zeilen:"
  tail -n 120 build/reports/build_last.log || true
  exit "$status"
fi

APK="app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$APK" ]; then
  echo "==> BUILD OK ✔  APK: $APK"
else
  echo "==> Build gemeldet OK, aber APK nicht gefunden. Prüfe Modulnamen & Ausgaben."
  find app -maxdepth 4 -type f -name "*.apk"
fi
