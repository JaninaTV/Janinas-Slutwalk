#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
BASE="app/src/main/java/${APP_ID//.//}"
PKG_RULES="$BASE/rules"
PKG_OUTFIT="$BASE/outfit"
PKG_ROUTE="$BASE/route"
PKG_SESSION="$BASE/session"
PKG_SCHED="$BASE/scheduler"
PKG_INTEG="$BASE/integration/tasker"
RES="app/src/main/res"

mkdir -p "$PKG_RULES" "$PKG_OUTFIT" "$PKG_ROUTE" "$PKG_SESSION" "$PKG_SCHED" "$PKG_INTEG" "$RES/layout"

############################################
# 1) TaskerIntegration: einheitliche Events + Extras
############################################
cat > "$PKG_INTEG/TaskerBus.kt" <<'KOT'
package com.example.outfitguardian.integration.tasker

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Einheitlicher Event-Bus zu Tasker.
 * - Broadcast-Intent: action "com.example.outfitguardian.TASKER_EVENT"
 * - Optional HTTP POST an Tasker REST (konfigurierbar)
 *
 * Event-Namen (EVENT):
 *  - OUTFIT_PASS, OUTFIT_FAIL
 *  - ROUTE_PASS, ROUTE_FAIL
 *  - CHECK_START, CHECK_PASS, CHECK_FAIL
 *  - AUDIT_START, AUDIT_PASS, AUDIT_FAIL
 *  - STREAK_UPDATE
 *  - SESSION_TIME_ADD, SESSION_TIME_FREEZE
 *  - HOTSPOT_MOD
 *
 * Extras (Strings):
 *  - type: Kategorie (GLANZ|ABSATZ|SAUM|HOSIERY|KORRIDOR|TURN|STOP|SHADOW|AUDIT|GENERAL)
 *  - detail: Freitext kurz
 *  - severity: LOW|MEDIUM|HIGH|CRITICAL
 *  - minutes_delta: (+/-) Minutenänderung (als String)
 *  - corridor_m: neuer Korridor in Metern (als String)
 *  - action: ADD_LOOP|DOUBLE_HOTSPOT|SHRINK_CORRIDOR|NONE
 *  - counter_fail: gesamt Fails (als String)
 *  - counter_streak: aktuelle Streak (als String)
 */
object TaskerBus {
  private const val ACTION = "com.example.outfitguardian.TASKER_EVENT"
  @Volatile private var restUrl: String? = null

  fun configureRest(url: String?) { restUrl = url }

  fun send(
    ctx: Context,
    event: String,
    type: String = "GENERAL",
    detail: String = "",
    severity: String = "LOW",
    minutesDelta: Int? = null,
    corridorM: Int? = null,
    action: String? = null,
    counterFail: Int? = null,
    counterStreak: Int? = null
  ) {
    // Broadcast
    val i = Intent(ACTION).apply {
      putExtra("event", event)
      putExtra("type", type)
      putExtra("detail", detail)
      putExtra("severity", severity)
      minutesDelta?.let { putExtra("minutes_delta", it.toString()) }
      corridorM?.let { putExtra("corridor_m", it.toString()) }
      action?.let { putExtra("action", it) }
      counterFail?.let { putExtra("counter_fail", it.toString()) }
      counterStreak?.let { putExtra("counter_streak", it.toString()) }
    }
    ctx.sendBroadcast(i)

    // Optional REST
    restUrl?.let { url ->
      kotlin.runCatching {
        val payload = JSONObject().apply {
          put("event", event); put("type", type); put("detail", detail); put("severity", severity)
          if (minutesDelta!=null) put("minutes_delta", minutesDelta)
          if (corridorM!=null) put("corridor_m", corridorM)
          if (action!=null) put("action", action)
          if (counterFail!=null) put("counter_fail", counterFail)
          if (counterStreak!=null) put("counter_streak", counterStreak)
        }.toString()
        val con = (URL(url).openConnection() as HttpURLConnection).apply {
          requestMethod = "POST"
          doOutput = true
          setRequestProperty("Content-Type","application/json")
        }
        con.outputStream.use { it.write(payload.toByteArray()) }
        con.inputStream.use { it.readBytes() }
        con.disconnect()
      }.onFailure { Log.w("TaskerBus","REST send failed: ${it.message}") }
    }
  }
}
KOT

############################################
# 2) StreakManager + FailCounter HUD
############################################
cat > "$PKG_SESSION/StreakManager.kt" <<'KOT'
package com.example.outfitguardian.session

import android.content.Context
import com.example.outfitguardian.integration.tasker.TaskerBus

object StreakManager {
  private const val SP="streak_mgr"
  private const val K_STREAK="streak"
  private const val K_FAILS="fails"
  private const val K_FREEZE_UNTIL="freeze_until"

  fun reset(ctx: Context) {
    ctx.getSharedPreferences(SP,0).edit().clear().apply()
  }

  fun getStreak(ctx: Context): Int = ctx.getSharedPreferences(SP,0).getInt(K_STREAK,0)
  fun getFails(ctx: Context): Int = ctx.getSharedPreferences(SP,0).getInt(K_FAILS,0)

  fun isFrozen(ctx: Context, now: Long = System.currentTimeMillis()): Boolean =
    now < ctx.getSharedPreferences(SP,0).getLong(K_FREEZE_UNTIL, 0L)

  fun freezeFor(ctx: Context, minutes: Int) {
    val until = System.currentTimeMillis() + minutes*60_000L
    ctx.getSharedPreferences(SP,0).edit().putLong(K_FREEZE_UNTIL, until).apply()
    TaskerBus.send(ctx, event="SESSION_TIME_FREEZE", type="GENERAL", detail="Freeze ${minutes}m", severity="MEDIUM")
  }

  fun recordPass(ctx: Context) {
    val sp = ctx.getSharedPreferences(SP,0)
    val s = sp.getInt(K_STREAK,0)+1
    sp.edit().putInt(K_STREAK, s).apply()
    TaskerBus.send(ctx, event="STREAK_UPDATE", type="GENERAL", detail="PASS", counterStreak=s, counterFail=sp.getInt(K_FAILS,0))
  }

  fun recordFail(ctx: Context) {
    val sp = ctx.getSharedPreferences(SP,0)
    val f = sp.getInt(K_FAILS,0)+1
    sp.edit().putInt(K_FAILS, f).putInt(K_STREAK, 0).apply()
    TaskerBus.send(ctx, event="STREAK_UPDATE", type="GENERAL", detail="FAIL", counterStreak=0, counterFail=f)
  }
}
KOT

cat > "$RES/layout/view_fail_counter.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="wrap_content"
  android:layout_height="wrap_content"
  android:padding="6dp">
  <TextView
    android:id="@+id/tvFailCounter"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:text="Fails: 0 | Streak: 0"
    android:textStyle="bold"
    android:textSize="14sp"
    android:textColor="#FFFFFF"/>
</FrameLayout>
XML

############################################
# 3) Absatz-Präzision ±0,5 cm (gegen Max-Heels-Referenz)
############################################
python3 - <<'PY'
from pathlib import Path, re as _re
p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitCheckManager.kt")
s = p.read_text()

# Absatzprüfung (wenn nicht schon vorhanden) – strengere Toleranz
if "HEEL_PRECISION_ENFORCE" not in s:
  s = s.replace("val reasons = mutableListOf<String>()",
r'''val reasons = mutableListOf<String>()

        // HEEL_PRECISION_ENFORCE: ±0,5 cm gegen Referenz
        try {
          val need = com.example.outfitguardian.rules.HeelsMonotony.required(ctx)
          if (need > 0f) {
            val have = OutfitHeuristics.estimateHeelHeightCm(bmp)
            if (have + 0.5f < need) {
              reasons += "Absatz zu niedrig (Pflicht: ≥ %.1f cm, erkannt: %.1f cm)".format(need, have)
            }
          }
        } catch (_:Throwable) {}
''', 1)
  Path(p).write_text(s)
  print("OutfitCheckManager patched: heel precision")
else:
  print("Heel precision already present")
PY

############################################
# 4) ShadowChecks Scheduler (ruhige Stelle -> Check -> zurück)
############################################
cat > "$PKG_SCHED/ShadowChecks.kt" <<'KOT'
package com.example.outfitguardian.scheduler

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.outfitguardian.integration.tasker.TaskerBus
import kotlin.random.Random

/**
 * Sehr einfache Heuristik: wenn CrowdScore länger niedrig ist, plane einen Shadow-Check
 * (Front+Seite) in den nächsten 2–4 Minuten. Danach normal weiter.
 * Erwartet, dass CrowdScheduler onCrowdScore liefert (0..1).
 */
object ShadowChecks {
  private var lowSince: Long = 0
  private var armed = false
  private val h = Handler(Looper.getMainLooper())

  fun onCrowdScore(ctx: Context, score: Float, now: Long = System.currentTimeMillis(), trigger: ()->Unit) {
    if (score < 0.25f) {
      if (lowSince == 0L) lowSince = now
      if (!armed && now - lowSince > 60_000L) {
        // in 2–4 min auslösen
        armed = true
        val delay = (120_000L + Random.nextLong(0,120_000L))
        h.postDelayed({
          TaskerBus.send(ctx, event="CHECK_START", type="SHADOW", detail="ShadowCheck", severity="LOW")
          trigger()
          armed = false
          lowSince = 0
        }, delay)
      }
    } else {
      lowSince = 0
      armed = false
    }
  }
}
KOT

# Hook in CrowdScheduler -> ShadowChecks
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/example/outfitguardian/scheduler/CrowdScheduler.kt")
s = p.read_text()
if "ShadowChecks" not in s:
  s = s.replace("import com.example.outfitguardian.route.SessionNavigator",
                "import com.example.outfitguardian.route.SessionNavigator\nimport com.example.outfitguardian.scheduler.ShadowChecks")
  s = s.replace("monitor = CrowdMonitor(ctx) { score ->",
                "monitor = CrowdMonitor(ctx) { score ->\n      // Shadow checks bei low-crowd\n      ShadowChecks.onCrowdScore(ctx, score) { navProvider()?.requestOutfitCheckNow() }")
  Path(p).write_text(s)
  print("CrowdScheduler wired to ShadowChecks")
else:
  print("ShadowChecks already wired")
PY

############################################
# 5) Hotspot-Modifier & Korridor-Shrink bei Fails
############################################
python3 - <<'PY'
from pathlib import Path, re as _re
p = Path("app/src/main/java/com/example/outfitguardian/route/SessionNavigator.kt")
s = p.read_text()

if "FAIL_REACTION_BLOCK" not in s:
  s = s.replace("class SessionNavigator(", "class SessionNavigator(\n  private val ctx: android.content.Context,\n  private val plan: RoutePlan\n) {\n  // FAIL_REACTION_BLOCK\n  private var corridorM: Int = 15\n", 1)

  s = s.replace("fun onOutfitFail()", 
r'''fun onOutfitFail() {
    // 1) Doppel-Hotspot: setze nächsten Hotspot-Zähler zurück (erneut umrunden)
    val idx = nearestHotspotIndex(currentLatLng())
    if (idx != null) {
      hotspotPathMeters[idx] = 0.0
      com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
        event="HOTSPOT_MOD", type="GENERAL", detail="DOUBLE_HOTSPOT", severity="MEDIUM", action="DOUBLE_HOTSPOT")
    } else {
      // 2) Bonus-Loop 250m
      insertBonusLoop(250.0)
      com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
        event="HOTSPOT_MOD", type="GENERAL", detail="ADD_LOOP 250m", severity="MEDIUM", action="ADD_LOOP")
    }
    // 3) Korridor shrink um 2m bis min 8m
    corridorM = kotlin.math.max(8, corridorM - 2)
    com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
      event="ROUTE_FAIL", type="KORRIDOR", detail="Shrink to ${'$'}corridorM m", severity="MEDIUM", corridorM=corridorM)
  }''')

  # Hilfsfunktionen, falls fehlen
  if "insertBonusLoop" not in s:
    s = s.replace("private fun nearestHotspotIndex", 
r'''private fun insertBonusLoop(lenM: Double) {
    val a = currentLatLng()
    val b = offset(a, lenM/3, 45.0)
    val c = offset(b, lenM/3, -120.0)
    val d = a
    val leg = Leg(listOf(a,b,c,d), isMystery = true)
    val insertAt = (currentLegIndex+1).coerceAtMost(plan.legs.size)
    plan.legs.add(insertAt, leg)
  }

  private fun nearestHotspotIndex''')
  Path(p).write_text(s)
  print("SessionNavigator fail reactions patched")
else:
  print("Fail reactions already present")
PY

############################################
# 6) Benachrichtigungs-Blocker (App-Intern + optional DND)
############################################
cat > "$PKG_SESSION/NotificationGuard.kt" <<'KOT'
package com.example.outfitguardian.session

import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * Blockt eigene Non-Critical-Notifications; optional kann der Nutzer DND freigeben.
 * Systemweite Blockade geht nur mit user consent (Policy access).
 */
object NotificationGuard {
  fun enableInAppQuiet(ctx: Context) {
    // Deine App: keine Non-Critical Notifications während Session
    ctx.getSharedPreferences("notif_guard",0).edit().putBoolean("quiet", true).apply()
  }
  fun disableInAppQuiet(ctx: Context) {
    ctx.getSharedPreferences("notif_guard",0).edit().putBoolean("quiet", false).apply()
  }
  fun requestSystemDnd(ctx: Context) {
    if (Build.VERSION.SDK_INT >= 23) {
      val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      // Hinweis: tatsächliche Freigabe erfordert Settings-Intent, hier nur Platzhalter-Aufruf
      // ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
  }
}
KOT

############################################
# 7) MainActivity: HUD einbinden & Hooks
############################################
python3 - <<'PY'
from pathlib import Path
am = Path("app/src/main/res/layout/activity_main.xml")
if am.exists():
  a = am.read_text()
  if "view_fail_counter" not in a:
    a = a.replace("</LinearLayout>", '  <include layout="@layout/view_fail_counter"/>\n</LinearLayout>\n')
    am.write_text(a)

p = Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
s = p.read_text()
if "updateFailCounter" not in s:
  s += """

  private fun updateFailCounter() {
    val tv = findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvFailCounter)
    if (tv != null) {
      val fails = com.example.outfitguardian.session.StreakManager.getFails(this)
      val streak = com.example.outfitguardian.session.StreakManager.getStreak(this)
      tv.text = "Fails: %d | Streak: %d".format(fails, streak)
    }
  }
"""
  s = s.replace("startForegroundSession()", 
                "startForegroundSession()\n      com.example.outfitguardian.session.NotificationGuard.enableInAppQuiet(this)")
  s = s.replace("stopForegroundSession();", 
                "stopForegroundSession(); com.example.outfitguardian.session.NotificationGuard.disableInAppQuiet(this);")
  Path(p).write_text(s)
PY

############################################
# 8) Streak-Pflicht: in OutfitCheckManager Pass/Fail melden + Tasker-Strafen
############################################
python3 - <<'PY'
from pathlib import Path, re as _re
p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitCheckManager.kt")
s = p.read_text()

# Nach Ermittlung "reasons" -> Streak & Tasker
if "STREAK_AND_TASKER_REPORT" not in s:
  s = s.replace("return Evaluation(reasons.isEmpty(), reasons)",
r'''// STREAK_AND_TASKER_REPORT
        val ok = reasons.isEmpty()
        if (ok) {
          com.example.outfitguardian.session.StreakManager.recordPass(ctx)
          com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
            event="OUTFIT_PASS", type="GENERAL", detail="Check OK", severity="LOW")
        } else {
          com.example.outfitguardian.session.StreakManager.recordFail(ctx)
          com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
            event="OUTFIT_FAIL", type="GENERAL", detail=reasons.joinToString("; "), severity="HIGH")
          // Reaktionen: Zeit/Route via Tasker
          com.example.outfitguardian.integration.tasker.TaskerBus.send(ctx,
            event="SESSION_TIME_ADD", type="GENERAL", detail="Auto add by fail", severity="MEDIUM", minutesDelta=20)
          // Navigator Fail-Reaktion (Doppel-Hotspot/Korridor-Shrink)
          try { navigator?.onOutfitFail() } catch (_:Throwable) {}
        }
        return Evaluation(ok, reasons)''', 1)
  Path(p).write_text(s)
  print("OutfitCheckManager streak+tasker reporting patched")
else:
  print("Already patched streak/tasker reporting")
PY

############################################
# 9) Build
############################################
echo "==> Build"
if [ -x ./gradlew ]; then
  ./gradlew --stop >/dev/null 2>&1 || true
  ./gradlew -i :app:assembleDebug
else
  gradle --stop >/dev/null 2>&1 || true
  gradle -i :app:assembleDebug
fi

echo "✅ Strict Pack aktiv: Streak, Fail-HUD, Shadow-Checks, Heel-Precision, Hotspot-Mods, Notification-Guard, Tasker-Bus."
echo "   APK: app/build/outputs/apk/debug/"
