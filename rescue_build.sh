#!/usr/bin/env bash
set -euo pipefail

log(){ printf "\n\033[1;36m[%s]\033[0m %s\n" "$(date +%H:%M:%S)" "$*"; }

ROOT="$(pwd)"
SDK_DIR="$HOME/android-sdk"
CMDLINE_DIR="$SDK_DIR/cmdline-tools/latest"
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
export PATH="$CMDLINE_DIR/bin:$SDK_DIR/platform-tools:$PATH"

log "1/6 Java 17 prüfen/aktivieren"
if ! java -version 2>&1 | grep -q 'version "17'; then
  sudo apt-get update -y
  sudo apt-get install -y openjdk-17-jdk
  sudo update-alternatives --set java "$(update-alternatives --list java | grep -m1 'java-17')"
fi
java -version

log "2/6 Android cmdline-tools installieren (falls fehlen)"
mkdir -p "$SDK_DIR"
if [ ! -x "$CMDLINE_DIR/bin/sdkmanager" ]; then
  TMP="$(mktemp -d)"
  # stabile Quelle via Google
  curl -fsSL -o "$TMP/cmdline-tools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  mkdir -p "$SDK_DIR/cmdline-tools"
  unzip -q "$TMP/cmdline-tools.zip" -d "$SDK_DIR/cmdline-tools"
  # Entpackt als "cmdline-tools"; wir wollen "latest"
  mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$CMDLINE_DIR"
  rm -rf "$TMP"
fi

log "SDK-Manager Version:"
sdkmanager --version || true

log "3/6 Benötigte Android-Pakete holen + Lizenzen akzeptieren"
yes | sdkmanager --licenses > /dev/null || true
yes | sdkmanager \
  "platform-tools" \
  "build-tools;34.0.0" \
  "platforms;android-34" \
  "cmdline-tools;latest" \
  > /dev/null

# kein patcher;v4 – wird nicht mehr benötigt
# yes | sdkmanager "patcher;v4" >/dev/null 2>&1 || true

log "4/6 Gradle Wrapper auf 8.7 anheben (falls Projekt-Wrapper existiert)"
if [ -f "./gradlew" ]; then
  chmod +x ./gradlew
  ./gradlew wrapper --gradle-version 8.7 --distribution-type all --no-daemon || true
else
  log "Warnung: ./gradlew fehlt – bitte sicherstellen, dass das Projekt ein Android-Gradle-Projekt ist."
fi

log "5/6 Android Gradle Plugin (AGP) & Kotlin-Plugin Versionen angleichen"
# Kotlin 1.9.24, AGP 8.4.2 sind kompatibel zu Gradle 8.7
# KTS (settings.gradle.kts) Variante
if [ -f "settings.gradle.kts" ]; then
  sed -i 's/id("com\.android\.application") version ".*"/id("com.android.application") version "8.4.2"/' settings.gradle.kts || true
  sed -i 's/id("com\.android\.library") version ".*"/id("com.android.library") version "8.4.2"/' settings.gradle.kts || true
  sed -i 's/id("org\.jetbrains\.kotlin\.android") version ".*"/id("org.jetbrains.kotlin.android") version "1.9.24"/' settings.gradle.kts || true
fi
# Groovy (build.gradle) Top-Level classpath Variante
if grep -Rql 'com.android.tools.build:gradle' .; then
  grep -RIl 'com.android.tools.build:gradle' . | xargs -r sed -i 's/com\.android\.tools\.build:gradle:[0-9.]\+/com.android.tools.build:gradle:8.4.2/g'
fi
if grep -Rql 'org.jetbrains.kotlin:kotlin-gradle-plugin' .; then
  grep -RIl 'org.jetbrains.kotlin:kotlin-gradle-plugin' . | xargs -r sed -i 's/org\.jetbrains\.kotlin:kotlin-gradle-plugin:[0-9.]\+/org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.24/g'
fi

log "6/6 Build starten (:app:assembleDebug)"
if [ -f "./gradlew" ]; then
  ./gradlew --no-daemon --stacktrace clean :app:assembleDebug
else
  log "Fehler: Kein Gradle-Wrapper gefunden. Abbruch."
  exit 1
fi

APK_PATH="$(ls -1 app/build/outputs/apk/debug/*.apk 2>/dev/null | tail -n1 || true)"
if [ -n "$APK_PATH" ]; then
  log "FERTIG ✅  APK gefunden:"
  echo "$APK_PATH"
else
  log "⚠️  Kein APK gefunden. Bitte prüfe Build-Logs unter app/build/outputs/logs oder die Gradle-Ausgabe oben."
  exit 1
fi
