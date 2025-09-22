#!/usr/bin/env bash
set -euo pipefail

APP_DIR="app/src/main"
PKG_PATH="com/example/outfitguard"
JAVA_DIR="${APP_DIR}/java/${PKG_PATH}"
RES_DIR="${APP_DIR}/res"

echo "==> Erzeuge Verzeichnisse…"
mkdir -p "${JAVA_DIR}/scenario" \
         "${JAVA_DIR}/integration/tasker" \
         "${JAVA_DIR}/route" \
         "${JAVA_DIR}/checks" \
         "${JAVA_DIR}/session" \
         "${RES_DIR}/xml" \
         "${RES_DIR}/values"

############################################
# 0) Strings (App-Name, Konstanten)
############################################
cat > "${RES_DIR}/values/strings.xml" <<'XML'
<resources>
    <string name="app_name">OutfitGuard</string>
    <string name="scenario_micro_tartan">Micro Tartan Session</string>
</resources>
XML

############################################
# 1) Manifest minimal patch (Service + FileProvider)
############################################
MANIFEST="${APP_DIR}/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "==> Erzeuge minimales AndroidManifest.xml"
  cat > "$MANIFEST" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.outfitguard">

    <application android:name="android.app.Application">
        <activity
            android:name=".session.MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <service
            android:name=".session.SessionForegroundService"
            android:exported="false"
            android:foregroundServiceType="location|dataSync" />

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
</manifest>
XML
fi

cat > "${RES_DIR}/xml/file_paths.xml" <<'XML'
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="imgs" path="imgs/"/>
    <files-path name="vault" path="vault/"/>
</paths>
XML

############################################
# 2) Szenario-Modelle & Policy
############################################
cat > "${JAVA_DIR}/scenario/ScenarioConfig.kt" <<'KOT'
package com.example.outfitguard.scenario

data class DurationSpec(
    val baseHours: Int = 6,
    val maxPenaltyHours: Int = 4
)

data class RoutePolicy(
    val showOnlyNextStep: Boolean = true,
    val corridorMeters: Int = 15,
    val minPaceKmh: Double = 1.5,
    val allowDynamicHotspots: Boolean = true,
    val allowRandomDoubling: Boolean = true
)

enum class ViolationType {
    ROUTE_OFF, PAUSE, REVERSE, PACE_LOW, OUTFIT_MISMATCH, APP_BACKGROUND
}

data class OutfitPreset(
    val name: String,
    val requiresSkirtOrDress: Boolean = true,
    val maxSkirtRule: String, // textuell: „micro / zufällig / <= Pofalte“
    val tightsGlossBlack: Boolean = true,
    val socksWhiteOverTights: Boolean = true,
    val sockPatternAllowed: Boolean = true,
    val heelsMinCm: Int = 10,
    val noPlateau: Boolean = true,
    val skirtBiasMicro: Boolean = true, // Fortuna bias
    val forced65MicroAndHigherHeels: Boolean = true // 65% sofort Micro + höhere Heels
)

data class CheckPolicy(
    val referenceShots: Int = 50,
    val prepMinutes: Int = 5,
    val outfitCheckIntervalMin: Int = 30,
    val outfitCheckIntervalMax: Int = 45,
    val shadowCheckChance: Double = 0.25,      // 25% extra Check kurz danach
    val frontThenSideDelaySec: Int = 5,
    val appForegroundLock: Boolean = true
)

data class CrowdPolicy(
    val highCrowdExtraLoops: Boolean = true,
    val updateSeconds: Int = 10
)

data class StrictPack(
    val streakMinutesTargets: List<Int> = listOf(30, 60),
    val penaltyTimePerFailMin: Int = 6,   // Beispiel: Min-Verlängerung je Fail (steuerbar via Tasker)
    val maxPenaltyHours: Int = 4
)

data class MicroTartanScenario(
    val title: String = "Micro Tartan Session",
    val startLabel: String = "Parkhaus-Dach Lüneburg (Start/Ziel fix)",
    val duration: DurationSpec = DurationSpec(),
    val route: RoutePolicy = RoutePolicy(),
    val outfit: OutfitPreset = OutfitPreset(
        name = "Micro-Tartan",
        maxSkirtRule = "randomisiert mit Bias zu Micro; Max = Höhe Pofalte",
        heelsMinCm = 10
    ),
    val checks: CheckPolicy = CheckPolicy(),
    val crowd: CrowdPolicy = CrowdPolicy(),
    val strict: StrictPack = StrictPack()
)
KOT

############################################
# 3) Tasker-Bridge (Broadcast Intents)
############################################
cat > "${JAVA_DIR}/integration/tasker/TaskerBridge.kt" <<'KOT'
package com.example.outfitguard.integration.tasker

import android.content.Context
import android.content.Intent

object TaskerBridge {
    private const val ACTION = "com.example.outfitguard.TASKER_EVENT"
    // Profilempfehlung in Tasker: Event → "Intent Received" mit Aktion ACTION
    // Extras werden als String übergeben.

    fun sessionStart(ctx: Context, scenario: String) =
        send(ctx, "session_start", mapOf("scenario" to scenario))

    fun sessionEnd(ctx: Context, status: String) =
        send(ctx, "session_end", mapOf("status" to status))

    fun violation(ctx: Context, type: String, severity: Int, details: String = "") =
        send(ctx, "violation", mapOf("type" to type, "severity" to severity.toString(), "details" to details))

    fun streakUpdate(ctx: Context, minutes: Int) =
        send(ctx, "streak_update", mapOf("minutes" to minutes.toString()))

    fun penaltyAdded(ctx: Context, minutes: Int, reason: String) =
        send(ctx, "penalty_added", mapOf("minutes" to minutes.toString(), "reason" to reason))

    private fun send(ctx: Context, evt: String, extras: Map<String,String>) {
        val i = Intent(ACTION).apply {
            putExtra("event", evt)
            extras.forEach { (k,v) -> putExtra(k, v) }
        }
        ctx.sendBroadcast(i)
    }
}
KOT

############################################
# 4) Checks & Scheduler (Stubs)
############################################
cat > "${JAVA_DIR}/checks/OutfitCheckManager.kt" <<'KOT'
package com.example.outfitguard.checks

import android.content.Context
import com.example.outfitguard.integration.tasker.TaskerBridge
import com.example.outfitguard.scenario.ViolationType

class OutfitCheckManager(private val ctx: Context) {

    fun scheduleRandomCheck(minMinutes: Int, maxMinutes: Int, frontThenSideDelaySec: Int) {
        // Stub: hier würdest du WorkManager/AlarmManager einsetzen.
        // Diese Methode plant (pseudo) einen Check und informiert Tasker nicht,
        // bis ein Verstoß erkannt wird.
    }

    fun evaluateWithReferences(): Boolean {
        // Stub: vergleicht Referenzfotos und aktuelle Shots (Front/Seite).
        // return true wenn ok, false bei Abweichung.
        return true
    }

    fun onMismatch() {
        TaskerBridge.violation(ctx, ViolationType.OUTFIT_MISMATCH.name, severity = 35, details = "outfit-check failed")
    }
}
KOT

cat > "${JAVA_DIR}/checks/CrowdScheduler.kt" <<'KOT'
package com.example.outfitguard.checks

import android.content.Context
import com.example.outfitguard.integration.tasker.TaskerBridge

class CrowdScheduler(private val ctx: Context) {
    private var lastScore: Float = 0f

    fun start(updateSeconds: Int, enableExtraLoops: Boolean) {
        // Stub: regelmäßige Crowd-Level Erfassung (z. B. Sensorik/ML oder API).
        // Bei hohem Crowd-Level, wenn enableExtraLoops == true, kannst du in der Route
        // einen "Extra-Schritt" einplanen und Tasker informieren.
    }

    fun onTick(score: Float) {
        lastScore = score
        if (score >= 0.7f) { // Beispiel: hoher Wert
            TaskerBridge.penaltyAdded(ctx, minutes = 6, reason = "crowd-extra-loop")
        }
    }
}
KOT

############################################
# 5) Route- & Session-Logik (stark vereinfacht)
############################################
cat > "${JAVA_DIR}/route/RouteGuard.kt" <<'KOT'
package com.example.outfitguard.route

import android.content.Context
import com.example.outfitguard.integration.tasker.TaskerBridge
import com.example.outfitguard.scenario.ViolationType
import kotlin.math.abs

class RouteGuard(private val ctx: Context) {
    private var corridorMeters: Int = 15
    private var minPaceKmh: Double = 1.5

    fun configure(corridor: Int, minPace: Double) {
        corridorMeters = corridor
        minPaceKmh = minPace
    }

    fun onPositionUpdate(distanceOffMeters: Int, paceKmh: Double, isReversing: Boolean, isPaused: Boolean) {
        if (distanceOffMeters > corridorMeters) {
            TaskerBridge.violation(ctx, ViolationType.ROUTE_OFF.name, severity = 85, details = "off=${distanceOffMeters}m")
        }
        if (isPaused) {
            TaskerBridge.violation(ctx, ViolationType.PAUSE.name, severity = 65, details = "pause")
        }
        if (isReversing) {
            TaskerBridge.violation(ctx, ViolationType.REVERSE.name, severity = 85, details = "reverse")
        }
        if (paceKmh + 1e-6 < minPaceKmh) {
            TaskerBridge.violation(ctx, ViolationType.PACE_LOW.name, severity = 65, details = "pace=${"%.2f".format(paceKmh)}")
        }
    }
}
KOT

############################################
# 6) Session Service + MainActivity (Stubs)
############################################
cat > "${JAVA_DIR}/session/SessionForegroundService.kt" <<'KOT'
package com.example.outfitguard.session

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.outfitguard.R
import com.example.outfitguard.integration.tasker.TaskerBridge
import com.example.outfitguard.route.RouteGuard
import com.example.outfitguard.checks.OutfitCheckManager
import com.example.outfitguard.scenario.MicroTartanScenario

class SessionForegroundService : Service() {

    private val scenario = MicroTartanScenario()
    private lateinit var routeGuard: RouteGuard
    private lateinit var outfitChecks: OutfitCheckManager

    override fun onCreate() {
        super.onCreate()
        routeGuard = RouteGuard(this).apply {
            configure(scenario.route.corridorMeters, scenario.route.minPaceKmh)
        }
        outfitChecks = OutfitCheckManager(this)

        startInForeground()
        TaskerBridge.sessionStart(this, scenario.title)
        // Plan: Referenzfotos nach prepMinutes (nur UI-Hinweis im Main).
        // Outfitchecks zufällig im Intervall:
        outfitChecks.scheduleRandomCheck(
            scenario.checks.outfitCheckIntervalMin,
            scenario.checks.outfitCheckIntervalMax,
            scenario.checks.frontThenSideDelaySec
        )
    }

    override fun onDestroy() {
        TaskerBridge.sessionEnd(this, "completed_or_aborted")
        super.onDestroy()
    }

    private fun startInForeground() {
        val id = "session_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(id, "Session", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
        val n: Notification = NotificationCompat.Builder(this, id)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Session läuft…")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .build()
        startForeground(1, n)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
KOT

cat > "${JAVA_DIR}/session/MainActivity.kt" <<'KOT'
package com.example.outfitguard.session

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.example.outfitguard.R
import com.example.outfitguard.scenario.MicroTartanScenario

class MainActivity : AppCompatActivity() {

    private val scenario = MicroTartanScenario()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(makeSimpleLayout())

        findViewById<TextView>(1001).text = scenario.title

        findViewById<Button>(1002).setOnClickListener {
            startForegroundService(Intent(this, SessionForegroundService::class.java))
        }
    }

    private fun makeSimpleLayout(): TextView {
        // Minimales Layout zur Laufzeit konstruieren, um XML zu sparen
        val tv = TextView(this)
        tv.id = 1001
        tv.textSize = 18f
        tv.setPadding(32, 48, 32, 48)

        val b = Button(this)
        b.id = 1002
        b.text = "Session starten"

        // Einfache LinearLayout-Erstellung:
        val root = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            addView(tv)
            addView(b)
        }
        setContentView(root)
        return tv
    }
}
KOT

############################################
# 7) README-Hinweise
############################################
cat > "README.md" <<'MD'
# Micro-Tartan Szenario (Blueprint)

Dieses Projekt enthält die technische Logik für:
- **RoutePolicy** (Korridor, Pace, nur nächster Schritt sichtbar)
- **OutfitPreset Micro-Tartan** (Rock/Kleid Pflicht, glänzende schwarze Strumpfhose/Halterlose, weiße Kniestrümpfe darüber, Heels >= 10 cm, kein Plateau, Bias zu Micro/Länge <= Pofalte)
- **Checks**: Referenzfotos (app-seitig zu ergänzen), Outfitchecks Front+Seite, Shadow-Checks
- **CrowdScheduler**: Option für Extra-Loops bei hohem Crowd-Score
- **Strikt**: Streak-Pflicht/Fail-Counter (in Tasker abbildbar)
- **Tasker-Bridge**: Broadcast-Intents `com.example.outfitguard.TASKER_EVENT` mit `event` + Extras

## Tasker-Profil-Beispiele (ohne Details):
- **Event**: Intent Received → Action: `com.example.outfitguard.TASKER_EVENT`
- **Variablen**: `%event`, `%type`, `%severity`, `%details`, `%minutes`, `%scenario`, `%status`
- **Profile**:
  - Bei `event=violation` → führe die Strafe/Verlängerung aus
  - Bei `event=penalty_added` → erhöhe Countdown/Strafzeit
  - Bei `event=streak_update` → belohne/entsperre
  - Bei `event=session_start|session_end` → Start/Stop Flows

> **Hinweis:** Heikle Inhalte sind **nicht** Teil des Codes. Dieser Blueprint liefert nur die technische Struktur, die du privat konfigurierst.

MD

############################################
# 8) Optional: Build versuchen, wenn gradlew existiert
############################################
if [ -f "./gradlew" ]; then
  echo "==> Versuche Debug-Build…"
  chmod +x ./gradlew || true
  ./gradlew --no-daemon :app:assembleDebug || true
else
  echo "(!) Kein gradlew gefunden – Build übersprungen. Dateien wurden angelegt."
fi

echo "==> Fertig. Szenario/Code ist angelegt."
