#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "==> Setze Java 17 (Temurin falls vorhanden)…"
if command -v /usr/lib/jvm/temurin-17-jdk-amd64/bin/java >/dev/null 2>&1; then
  export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
elif command -v /usr/lib/jvm/java-17-openjdk-amd64/bin/java >/dev/null 2>&1; then
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
else
  sudo apt-get update -y
  sudo apt-get install -y openjdk-17-jdk
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
fi
export PATH="$JAVA_HOME/bin:$PATH"
java -version

SDK_ROOT="/usr/local/android-sdk"
CMD_TOOLS_ZIP="commandlinetools-linux-11076708_latest.zip"
CMD_TOOLS_URL="https://dl.google.com/android/repository/${CMD_TOOLS_ZIP}"

echo "==> Stelle Android SDK Verzeichnisse bereit…"
sudo mkdir -p "${SDK_ROOT}/cmdline-tools"
sudo chown -R "$(id -u)":"$(id -g)" "${SDK_ROOT}"

if ! command -v sdkmanager >/dev/null 2>&1; then
  echo "==> Lade Android cmdline-tools…"
  curl -L -o /tmp/${CMD_TOOLS_ZIP} "${CMD_TOOLS_URL}"
  unzip -q /tmp/${CMD_TOOLS_ZIP} -d /tmp/cmdtools
  # Struktur nach ${SDK_ROOT}/cmdline-tools/latest verschieben
  mkdir -p "${SDK_ROOT}/cmdline-tools/latest"
  rsync -a /tmp/cmdtools/cmdline-tools/* "${SDK_ROOT}/cmdline-tools/latest/"
  rm -rf /tmp/${CMD_TOOLS_ZIP} /tmp/cmdtools
fi

export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="${SDK_ROOT}/cmdline-tools/latest/bin:${SDK_ROOT}/platform-tools:${PATH}"

echo "==> Akzeptiere SDK-Lizenzen…"
yes | sdkmanager --licenses >/dev/null

echo "==> Installiere benötigte Pakete (kann ein paar Minuten dauern)…"
sdkmanager \
  "platform-tools" \
  "platforms;android-34" \
  "build-tools;34.0.0" \
  >/dev/null

echo "==> Schreibe local.properties…"
mkdir -p "${ROOT}"
cat > "${ROOT}/local.properties" <<PROP
sdk.dir=${SDK_ROOT}
PROP

echo "==> Persistiere Umgebungsvariablen für künftige Shells…"
if ! grep -q "ANDROID_SDK_ROOT" "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo "export JAVA_HOME=${JAVA_HOME}"
    echo "export ANDROID_HOME=${SDK_ROOT}"
    echo "export ANDROID_SDK_ROOT=${SDK_ROOT}"
    echo "export PATH=\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:\$JAVA_HOME/bin:\$PATH"
  } >> "${HOME}/.bashrc"
fi

echo "==> Gradle Wrapper prüfen…"
if [ ! -x "${ROOT}/gradlew" ]; then
  echo "   Kein gradlew gefunden – initialisiere Wrapper…"
  if command -v gradle >/dev/null 2>&1; then
    gradle wrapper
  else
    # Minimaler Fallback: lade Wrapper-Distribution on-the-fly
    curl -s https://raw.githubusercontent.com/gradle/gradle/master/gradle/wrapper/gradle-wrapper.properties \
      -o gradle/wrapper/gradle-wrapper.properties
  fi
fi
chmod +x "${ROOT}/gradlew" || true

echo "==> Bereinige & baue Debug-APK…"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug

echo
echo "✅ Fertig! APK findest du unter:"
echo "   $(pwd)/app/build/outputs/apk/debug/"
