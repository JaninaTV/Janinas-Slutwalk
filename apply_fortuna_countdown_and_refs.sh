#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
BASE="app/src/main/java/${APP_ID//.//}"
RES="app/src/main/res"

mkdir -p "$BASE/session" "$BASE/rules" "$BASE/scheduler" "$RES/layout"

############################################
# 1) Fortuna Countdown Manager (5 Minuten)
############################################
cat > "$BASE/session/FortunaCountdown.kt" <<'KOT'
package com.example.outfitguardian.session

import android.content.Context
import android.os.CountDownTimer
import android.util.Log
import com.example.outfitguardian.rules.FortunaPreset
import com.example.outfitguardian.scheduler.ReferenceCaptureOrchestrator

object FortunaCountdown {
  private const val SP = "fortuna_countdown"
  private const val KEY_END = "end_at_ms"
  private const val KEY_ACTIVE = "active"
  private var timer: CountDownTimer? = null

  fun isActive(ctx: Context): Boolean =
    ctx.getSharedPreferences(SP, 0).getBoolean(KEY_ACTIVE, false)

  fun remainingMs(ctx: Context): Long {
    val end = ctx.getSharedPreferences(SP,0).getLong(KEY_END, 0L)
    val now = System.currentTimeMillis()
    return (end - now).coerceAtLeast(0L)
  }

  /**
   * Startet die 5-Minuten-Wechselphase nach Fortuna-Ziehung.
   * Nach Ablauf werden automatisch die Referenzfotos gestartet.
   * @param minutes Dauer, default 5
   * @param refCount Anzahl Referenzfotos (default 50)
   * @param intervalMs Intervall zwischen Referenzaufnahmen (default 4000ms)
   */
  fun start(ctx: Context, minutes: Int = 5, refCount: Int = 50, intervalMs: Long = 4000L, frontFirst: Boolean = true) {
    stop()
    // Stelle sicher, dass Fortuna gezogen wurde (persistiert die Auswahl)
    FortunaPreset.draw(ctx)

    val endAt = System.currentTimeMillis() + minutes*60_000L
    ctx.getSharedPreferences(SP,0).edit()
      .putLong(KEY_END, endAt)
      .putBoolean(KEY_ACTIVE, true)
      .apply()

    timer = object: CountDownTimer(minutes*60_000L, 1000L) {
      override fun onTick(msLeft: Long) {
        // Option: UI kann remainingMs() pullen; keine Broadcasts nötig
      }
      override fun onFinish() {
        try {
          ctx.getSharedPreferences(SP,0).edit().putBoolean(KEY_ACTIVE, false).apply()
          // Starte Referenzfotos automatisch
          ReferenceCaptureOrchestrator.start(ctx, total = refCount, intervalMs = intervalMs, frontFirst = frontFirst)
        } catch (t: Throwable) {
          Log.e("FortunaCountdown", "Failed to start reference captures", t)
        }
      }
    }.start()
  }

  fun stop() {
    timer?.cancel()
    timer = null
  }
}
KOT

############################################
# 2) Orchestrator: Referenzfotos automatisch schießen
#    (ohne deine App zu blockieren) via WorkManager
############################################
cat > "$BASE/scheduler/ReferenceCaptureOrchestrator.kt" <<'KOT'
package com.example.outfitguardian.scheduler

import android.content.Context
import android.content.Intent
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * Startet N Aufnahmen, jeweils über eine Activity deiner App
 * (z. B. AutoCameraActivity), ohne UI zuzumüllen.
 * Erwartung: AutoCameraActivity macht 1 Shot, speichert ins Tresor-System
 * und schließt sich selbst wieder (bestehendes Verhalten).
 */
object ReferenceCaptureOrchestrator {
  private const val UNIQUE = "reference_captures"

  fun start(ctx: Context, total: Int = 50, intervalMs: Long = 4000L, frontFirst: Boolean = true) {
    val wm = WorkManager.getInstance(ctx)
    wm.cancelUniqueWork(UNIQUE)

    val reqs = mutableListOf<OneTimeWorkRequest>()
    repeat(total) { i ->
      val delay = i * intervalMs
      val data = workDataOf(
        "index" to i,
        "front" to if (frontFirst) (i % 2 == 0) else (i % 2 == 1)
      )
      val w = OneTimeWorkRequestBuilder<CaptureKickWorker>()
        .setInitialDelay(delay, TimeUnit.MILLISECONDS)
        .setInputData(data)
        .build()
      reqs += w
    }
    wm.beginUniqueWork(UNIQUE, ExistingWorkPolicy.REPLACE, reqs.first())
      .then(reqs.drop(1))
      .enqueue()
  }

  class CaptureKickWorker(ctx: Context, params: WorkerParameters): CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
      val idx = inputData.getInt("index", -1)
      val front = inputData.getBoolean("front", true)
      // Deine Kamera-Activity muss den Intent interpretieren (z. B. Front/Back wählen)
      val i = Intent().apply {
        setClassName(applicationContext, "com.example.outfitguardian.AutoCameraActivity")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        putExtra("ref_mode", true)
        putExtra("index", idx)
        putExtra("lens_facing", if (front) "front" else "back")
      }
      return try {
        applicationContext.startActivity(i)
        Result.success()
      } catch (t: Throwable) {
        Result.retry()
      }
    }
  }
}
KOT

############################################
# 3) Mini View für Countdown (optional, simpel)
############################################
cat > "$RES/layout/view_fortuna_countdown.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="wrap_content"
  android:padding="8dp">
  <TextView
    android:id="@+id/tvFortunaCountdown"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:text="Fortuna: 05:00"
    android:textStyle="bold"
    android:textSize="18sp"
    android:textColor="#FFFFFF"/>
</FrameLayout>
XML

############################################
# 4) MainActivity patchen:
#    - Bei Sessionstart: Fortuna ziehen, 5-Minuten-Timer starten
#    - Countdownanzeige optional aktualisieren
############################################
python3 - <<'PY'
from pathlib import Path, re as _re
p = Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
s = p.read_text()

# Imports
if "FortunaPreset" not in s:
  s = s.replace("import com.example.outfitguardian.rules",
                "import com.example.outfitguardian.rules")
if "FortunaCountdown" not in s:
  s = s.replace("import com.example.outfitguardian.scheduler.StrictCheckScheduler",
                "import com.example.outfitguardian.scheduler.StrictCheckScheduler\nimport com.example.outfitguardian.session.FortunaCountdown\nimport com.example.outfitguardian.rules.FortunaPreset")

# Include Countdown View in activity_main, wenn nicht vorhanden
am = Path("app/src/main/res/layout/activity_main.xml")
if am.exists():
  a = am.read_text()
  if "view_fortuna_countdown" not in a:
    a = a.replace("</LinearLayout>", '  <include layout="@layout/view_fortuna_countdown"/>\n</LinearLayout>\n')
    am.write_text(a)

# Hook bei Sessionstart: Fortuna ziehen + Countdown starten
if "startForegroundSession()" in s and "FortunaPreset.draw" not in s:
  s = s.replace("startForegroundSession()",
                "startForegroundSession()\n      // Fortuna: ziehe Rocklänge und starte 5-Minuten-Wechselfenster\n      com.example.outfitguardian.rules.FortunaPreset.draw(this)\n      com.example.outfitguardian.session.FortunaCountdown.start(this, minutes = 5, refCount = 50, intervalMs = 4000L, frontFirst = true)")

# Optionale UI-Aktualisierung jede Sekunde (wenn du schon einen Ticker hast – hier minimaler Handler Loop)
if "updateFortunaCountdownLabel" not in s:
  s += """

  private fun updateFortunaCountdownLabel() {
    val tv = findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvFortunaCountdown)
    if (tv != null) {
      val ms = com.example.outfitguardian.session.FortunaCountdown.remainingMs(this)
      val sec = (ms / 1000).toInt()
      val m = sec / 60
      val s = sec % 60
      tv.text = "Fortuna: %02d:%02d".format(m, s)
    }
  }
"""
Path(p).write_text(s)
print("MainActivity patched for Fortuna countdown")
PY

############################################
# 5) Manifest: WorkManager braucht default config (i. d. R. schon vorhanden)
############################################
# Kein spezieller Manifest-Patch nötig, Activities existieren bereits in deinem Projekt-Setup.

############################################
# 6) Build
############################################
echo "==> Build"
if [ -x ./gradlew ]; then
  ./gradlew --stop >/dev/null 2>&1 || true
  ./gradlew -i :app:assembleDebug
else
  gradle --stop >/dev/null 2>&1 || true
  gradle -i :app:assembleDebug
fi

echo "✅ Fortuna-Modus aktiv: 5-Minuten-Countdown nach Sessionstart, danach automatische Referenzfotos (50 Shots)."
