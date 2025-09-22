#!/usr/bin/env bash
set -euo pipefail

echo "▶ Schritt 1/6: Java 17 installieren (falls nötig)…"
if ! java -version 2>&1 | grep -q '17.'; then
  sudo apt-get update -y
  sudo apt-get install -y openjdk-17-jdk
fi
export JAVA_HOME="$(dirname $(dirname $(readlink -f $(which javac))))"
echo "JAVA_HOME=$JAVA_HOME"

echo "▶ Schritt 2/6: Android SDK einrichten…"
SDK_ROOT="$HOME/android-sdk"
mkdir -p "$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
export PATH="$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$PATH"

# cmdline-tools holen, wenn fehlen
if [ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "⤵ Lade Android commandline-tools…"
  cd "$SDK_ROOT"
  curl -L -o cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  mkdir -p cmdline-tools/latest
  unzip -q cmdline-tools.zip -d cmdline-tools
  # Google packt sie dummerweise in 'cmdline-tools/cmdline-tools'; wir wollen '.../latest'
  if [ -d "cmdline-tools/cmdline-tools" ]; then
    mv cmdline-tools/cmdline-tools/* cmdline-tools/latest/ || true
    rm -rf cmdline-tools/cmdline-tools
  fi
  rm -f cmdline-tools.zip
  cd - >/dev/null
fi

echo "▶ Schritt 3/6: Benötigte Pakete per sdkmanager installieren…"
yes | sdkmanager --licenses >/dev/null
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" >/dev/null

echo "▶ Schritt 4/6: Gradle Wrapper vorbereiten…"
# Falls kein Wrapper da ist, versuch einen zu erzeugen
if [ ! -f "./gradlew" ]; then
  if command -v gradle >/dev/null 2>&1; then
    gradle wrapper --gradle-version 8.7 --distribution-type all
  else
    echo "⤴ Installiere Gradle für Wrapper-Erzeugung…"
    sudo apt-get install -y gradle
    gradle wrapper --gradle-version 8.7 --distribution-type all
  fi
fi
chmod +x ./gradlew

echo "▶ Schritt 5/6: local.properties setzen…"
if [ ! -f local.properties ]; then
  printf "sdk.dir=%s\n" "$ANDROID_SDK_ROOT" > local.properties
else
  # überschreibe nur, wenn leer oder falsch
  if ! grep -q "sdk.dir=" local.properties; then
    printf "sdk.dir=%s\n" "$ANDROID_SDK_ROOT" >> local.properties
  fi
fi
echo "local.properties:"
cat local.properties

echo "▶ Schritt 6/6: Projekt bauen (Debug)…"
./gradlew --no-daemon --stacktrace clean :app:assembleDebug

APK_PATH="app/build/outputs/apk/debug"
echo "✅ Fertig. APK liegt unter: $APK_PATH"
ls -lah "$APK_PATH" || true
