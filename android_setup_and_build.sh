#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
APP_NAME="OutfitGuardian"
KOTLIN_VERSION="1.9.24"
AGP_VERSION="8.5.2"
COMPILE_SDK=34
MIN_SDK=24
TARGET_SDK=34

echo "==> Verzeichnisse anlegen"
mkdir -p app/src/main/java/${APP_ID//.//}
mkdir -p app/src/main/res/layout
mkdir -p app/src/main/res/values

echo "==> settings.gradle.kts"
cat > settings.gradle.kts <<SET
pluginManagement {
  repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
  }
}
dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    google()
    mavenCentral()
  }
}
rootProject.name = "${APP_NAME}"
include(":app")
SET

echo "==> Root build.gradle.kts"
cat > build.gradle.kts <<ROOT
plugins {
  id("com.android.application") version "${AGP_VERSION}" apply false
  kotlin("android") version "${KOTLIN_VERSION}" apply false
}
ROOT

echo "==> app/build.gradle.kts"
cat > app/build.gradle.kts <<APP
plugins {
  id("com.android.application")
  kotlin("android")
}

android {
  namespace = "${APP_ID}"
  compileSdk = ${COMPILE_SDK}

  defaultConfig {
    applicationId = "${APP_ID}"
    minSdk = ${MIN_SDK}
    targetSdk = ${TARGET_SDK}
    versionCode = 1
    versionName = "1.0"
  }

  buildTypes {
    release {
      isMinifyEnabled = false
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
  }

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
  kotlinOptions { jvmTarget = "17" }

  buildFeatures { viewBinding = true }
}

dependencies {
  implementation("androidx.core:core-ktx:1.13.1")
  implementation("androidx.appcompat:appcompat:1.7.0")
  implementation("com.google.android.material:material:1.12.0")
  implementation("androidx.activity:activity-ktx:1.9.2")
  implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
  implementation("com.google.android.gms:play-services-location:21.3.0")
}
APP

echo "==> AndroidManifest.xml"
cat > app/src/main/AndroidManifest.xml <<MAN
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  <application
    android:allowBackup="true"
    android:label="${APP_NAME}"
    android:theme="@style/Theme.Material3.DayNight.NoActionBar">
    <activity
      android:name=".MainActivity"
      android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
MAN

echo "==> TaskerEvents.kt"
cat > app/src/main/java/${APP_ID//.//}/TaskerEvents.kt <<KOT
package ${APP_ID}.integration.tasker

import android.content.Context
import android.content.Intent
import java.util.UUID

object TaskerEvents {

  const val ACTION_VIOLATION_START = "${APP_ID}.ACTION_VIOLATION_START"
  const val ACTION_VIOLATION_END   = "${APP_ID}.ACTION_VIOLATION_END"

  object Type {
    const val ROUTE = "ROUTE"
    const val CORRIDOR = "CORRIDOR"
    const val SPEED = "SPEED"
    const val STOP = "STOP"
    const val BACKTRACK = "BACKTRACK"
    const val RED_ZONE = "RED_ZONE"
    const val OUTFIT = "OUTFIT"
  }

  fun startViolation(
    context: Context,
    type: String,
    severity: Int,
    message: String
  ): String {
    val id = UUID.randomUUID().toString()
    val i = Intent(ACTION_VIOLATION_START).apply {
      putExtra("violation_id", id)
      putExtra("type", type)
      putExtra("severity", severity.coerceIn(0, 100))
      putExtra("message", message)
      putExtra("ts", System.currentTimeMillis())
    }
    context.sendBroadcast(i)
    return id
  }

  fun endViolation(
    context: Context,
    violationId: String,
    type: String,
    message: String = "resolved"
  ) {
    val i = Intent(ACTION_VIOLATION_END).apply {
      putExtra("violation_id", violationId)
      putExtra("type", type)
      putExtra("message", message)
      putExtra("ts", System.currentTimeMillis())
    }
    context.sendBroadcast(i)
  }
}
KOT

echo "==> RouteMonitor.kt (einfacher Checker: Korridor/Tempo/Stillstand/Backtrack + rote Zone)"
cat > app/src/main/java/${APP_ID//.//}/RouteMonitor.kt <<KOT
package ${APP_ID}.logic

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import com.google.android.gms.location.*
import kotlin.math.abs
import kotlin.math.max

data class CorridorConfig(
  val corridorMeters: Double = 20.0,
  val corridorReturnMeters: Double = 10.0,
  val minSpeedMps: Double = 0.8,       // Trödeln-Schwelle
  val stopSpeedMps: Double = 0.3,      // Stillstand-Schwelle
  val stopSeconds: Int = 10,
  val backtrackHeadingDeg: Double = 120.0,
)

class RouteMonitor(
  private val context: Context,
  private val cfg: CorridorConfig = CorridorConfig(),
  private val onEvent: (RouteEvent) -> Unit
) {
  private val fused by lazy { LocationServices.getFusedLocationProviderClient(context) }
  private var callback: LocationCallback? = null

  private var lastLoc: Location? = null
  private var stopStartMs: Long? = null
  private var corridorId: String? = null
  private var speedId: String? = null
  private var stopId: String? = null
  private var backtrackId: String? = null
  private var redZoneId: String? = null

  // Dummy: Rote Zone als 50m Kreis um Start
  private var startPoint: Location? = null
  private val redZoneRadius = 50.0

  // Dummy-Route: nur Startpunkt => Korridor prüft Distanz zu Startlinie (vereinfachte Näherung)
  fun setStart(loc: Location) { startPoint = loc }

  @SuppressLint("MissingPermission")
  fun start() {
    val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2000L)
      .setMinUpdateIntervalMillis(1000L)
      .setWaitForAccurateLocation(false)
      .build()
    callback = object : LocationCallback() {
      override fun onLocationResult(result: LocationResult) {
        result.lastLocation?.let { onLocation(it) }
      }
    }
    fused.requestLocationUpdates(req, callback!!, context.mainLooper)
  }

  fun stop() {
    callback?.let { fused.removeLocationUpdates(it) }
    callback = null
  }

  private fun onLocation(loc: Location) {
    if (startPoint == null) startPoint = loc
    val prev = lastLoc
    lastLoc = loc

    // — Rote Zone (Startkreis) —
    val dStart = startPoint?.distanceTo(loc)?.toDouble() ?: 0.0
    if (dStart <= redZoneRadius) {
      if (redZoneId == null) {
        redZoneId = "PENDING"
        onEvent(RouteEvent.Start(RouteEvent.Type.RED_ZONE, 50, "In roter Zone (Startbereich)"))
      }
    } else if (redZoneId != null) {
      onEvent(RouteEvent.End(RouteEvent.Type.RED_ZONE, "Rote Zone verlassen"))
      redZoneId = null
    }

    // — Korridor (vereinfachte Distanz zur „Route“: hier nur Startlinie) —
    val corridorDist = dStart // Demo: Entfernung vom Start als Näherung
    if (corridorDist > cfg.corridorMeters) {
      if (corridorId == null) {
        corridorId = "PENDING"
        onEvent(RouteEvent.Start(RouteEvent.Type.CORRIDOR, 60, "Korridor überschritten (> ${cfg.corridorMeters} m)"))
      }
    } else if (corridorId != null && corridorDist < cfg.corridorReturnMeters) {
      onEvent(RouteEvent.End(RouteEvent.Type.CORRIDOR, "Zurück im Korridor (< ${cfg.corridorReturnMeters} m)"))
      corridorId = null
    }

    // — Tempo / Stillstand —
    val speed = max(0f, loc.speed).toDouble() // m/s
    if (speed < cfg.stopSpeedMps) {
      if (stopStartMs == null) stopStartMs = System.currentTimeMillis()
      val elapsed = (System.currentTimeMillis() - (stopStartMs ?: 0)) / 1000
      if (elapsed >= cfg.stopSeconds && stopId == null) {
        stopId = "PENDING"
        onEvent(RouteEvent.Start(RouteEvent.Type.STOP, 70, "Stillstand > ${cfg.stopSeconds}s"))
      }
    } else {
      stopStartMs = null
      if (stopId != null) {
        onEvent(RouteEvent.End(RouteEvent.Type.STOP, "Bewegung wieder aufgenommen"))
        stopId = null
      }
    }

    if (speed > 0.01 && speed < cfg.minSpeedMps) {
      if (speedId == null) {
        speedId = "PENDING"
        onEvent(RouteEvent.Start(RouteEvent.Type.SPEED, 40, "Tempo zu niedrig (< ${cfg.minSpeedMps} m/s)"))
      }
    } else if (speedId != null && speed >= cfg.minSpeedMps) {
      onEvent(RouteEvent.End(RouteEvent.Type.SPEED, "Tempo ok (≥ ${cfg.minSpeedMps} m/s)"))
      speedId = null
    }

    // — Rückwärts (Heading stark abweichend) —
    if (prev != null && prev.hasBearing() && loc.hasBearing()) {
      val diff = abs(prev.bearing - loc.bearing).toDouble()
      val norm = if (diff > 180) 360 - diff else diff
      if (norm >= cfg.backtrackHeadingDeg) {
        if (backtrackId == null) {
          backtrackId = "PENDING"
          onEvent(RouteEvent.Start(RouteEvent.Type.BACKTRACK, 80, "Richtung stark abweichend (Backtrack)"))
        }
      } else if (backtrackId != null) {
        onEvent(RouteEvent.End(RouteEvent.Type.BACKTRACK, "Richtung wieder korrekt"))
        backtrackId = null
      }
    }
  }
}

sealed class RouteEvent {
  enum class Type { ROUTE, CORRIDOR, SPEED, STOP, BACKTRACK, RED_ZONE, OUTFIT }
  data class Start(val type: Type, val severity: Int, val message: String) : RouteEvent()
  data class End(val type: Type, val message: String) : RouteEvent()
}
KOT

echo "==> MainActivity.kt (UI + Simulation + Hook zum RouteMonitor)"
cat > app/src/main/java/${APP_ID//.//}/MainActivity.kt <<KOT
package ${APP_ID}

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import ${APP_ID}.integration.tasker.TaskerEvents
import ${APP_ID}.logic.*

class MainActivity : ComponentActivity() {

  private var monitor: RouteMonitor? = null

  private val reqPerms = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
  ) { startAfterPerms() }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)

    findViewById<android.view.View>(R.id.btnStart).setOnClickListener {
      ensurePermsAndStart()
    }
    findViewById<android.view.View>(R.id.btnStop).setOnClickListener {
      monitor?.stop()
    }

    // Demo-Buttons für Tasker-Events (Outfit/Backtrack etc.)
    findViewById<android.view.View>(R.id.btnSimOutfitStart).setOnClickListener {
      TaskerEvents.startViolation(this, TaskerEvents.Type.OUTFIT, 35, "Outfit-Check nicht bestanden")
    }
    findViewById<android.view.View>(R.id.btnSimOutfitEnd).setOnClickListener {
      // In echt würdest du die violationId merken – hier nur End mit Typ
      TaskerEvents.endViolation(this, "demo", TaskerEvents.Type.OUTFIT, "Outfit-Check ok")
    }
  }

  private fun ensurePermsAndStart() {
    val needed = listOf(
      Manifest.permission.ACCESS_FINE_LOCATION,
      Manifest.permission.ACCESS_COARSE_LOCATION
    ).filter {
      ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
    }
    if (needed.isNotEmpty()) reqPerms.launch(needed.toTypedArray()) else startAfterPerms()
  }

  private fun startAfterPerms() {
    val cfg = CorridorConfig()
    monitor = RouteMonitor(this, cfg) { ev ->
      when (ev) {
        is RouteEvent.Start -> {
          TaskerEvents.startViolation(
            this,
            mapType(ev.type),
            ev.severity,
            ev.message
          )
        }
        is RouteEvent.End -> {
          // In einem echten System würdest du die erzeugte violationId persistieren
          TaskerEvents.endViolation(this, "auto", mapType(ev.type), ev.message)
        }
      }
    }
    // fiktiver Startpunkt (falls direkt noch keine GPS-Position)
    monitor?.setStart(Location("init").apply {
      latitude = 0.0; longitude = 0.0; bearing = 0f; speed = 0f
    })
    monitor?.start()
  }

  private fun mapType(t: RouteEvent.Type): String = when (t) {
    RouteEvent.Type.ROUTE -> TaskerEvents.Type.ROUTE
    RouteEvent.Type.CORRIDOR -> TaskerEvents.Type.CORRIDOR
    RouteEvent.Type.SPEED -> TaskerEvents.Type.SPEED
    RouteEvent.Type.STOP -> TaskerEvents.Type.STOP
    RouteEvent.Type.BACKTRACK -> TaskerEvents.Type.BACKTRACK
    RouteEvent.Type.RED_ZONE -> TaskerEvents.Type.RED_ZONE
    RouteEvent.Type.OUTFIT -> TaskerEvents.Type.OUTFIT
  }
}
KOT

echo "==> activity_main.xml (kleines Bedienpanel)"
cat > app/src/main/res/layout/activity_main.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="match_parent"
  android:orientation="vertical"
  android:padding="16dp">

  <Button
    android:id="@+id/btnStart"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Session starten" />

  <Button
    android:id="@+id/btnStop"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Session stoppen"
    android:layout_marginTop="8dp" />

  <View
    android:layout_width="match_parent"
    android:layout_height="1dp"
    android:background="#DDDDDD"
    android:layout_marginTop="16dp"
    android:layout_marginBottom="16dp" />

  <Button
    android:id="@+id/btnSimOutfitStart"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Sim: Outfit-Verstoß START" />

  <Button
    android:id="@+id/btnSimOutfitEnd"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Sim: Outfit-Verstoß ENDE"
    android:layout_marginTop="8dp" />
</LinearLayout>
XML

echo "==> colors/strings/styles (einfach)"
cat > app/src/main/res/values/strings.xml <<STR
<resources>
  <string name="app_name">${APP_NAME}</string>
</resources>
STR

echo "==> proguard-rules.pro"
cat > app/proguard-rules.pro <<PRO
# leer
PRO

echo "==> Gradle Wrapper (falls nicht vorhanden)"
if [ ! -f gradlew ]; then
  echo "Lade Gradle Wrapper…"
  gradle -v >/dev/null 2>&1 || true
  ./gradlew -v >/dev/null 2>&1 || true
  if [ ! -f gradlew ]; then
    # Fallback: Wrapper über Gradle-Task anlegen, wenn gradle vorhanden
    if command -v gradle >/dev/null 2>&1; then
      gradle wrapper --gradle-version 8.7
    else
      echo "Hinweis: Falls kein Wrapper vorhanden ist, bitte lokal 'gradle wrapper --gradle-version 8.7' ausführen."
    fi
  fi
fi

echo "==> Fertig. Build ausführen mit:"
echo "   ./gradlew :app:assembleDebug  (oder im Gradle-Panel)"
