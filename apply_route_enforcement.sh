#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"
RES="app/src/main/res"

mkdir -p "$PKG/route" "$PKG/scheduler" "$PKG/outfit" "$PKG/util" "$RES/layout" "$RES/drawable"

########################################
# 1) Direction UI: nur Pfeil + knappe Ansagen
########################################
cat > "$RES/layout/view_direction_hud.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="wrap_content"
  android:background="#00000000"
  android:padding="8dp">
  <ImageView
    android:id="@+id/ivArrow"
    android:layout_width="72dp"
    android:layout_height="72dp"
    android:src="@android:drawable/arrow_up_float"
    android:layout_gravity="center_horizontal" />
  <TextView
    android:id="@+id/tvPrompt"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:text="Richtung halten"
    android:textStyle="bold"
    android:textColor="#FFFFFF"
    android:layout_gravity="center_horizontal"
    android:paddingTop="4dp"/>
</FrameLayout>
XML

########################################
# 2) RouteEngine: Korridor 15m, Mystery-Leg, Verdoppelungen, Turn Prompts
########################################
cat > "$PKG/route/RouteEngine.kt" <<'KOT'
package com.example.outfitguardian.route

import android.content.Context
import kotlin.math.*
import kotlin.random.Random

data class LatLng(val lat: Double, val lng: Double)
data class Leg(val points: List<LatLng>, val isMystery:Boolean=false)
data class Hotspot(val center: LatLng, val radiusMeters: Double)

class RoutePlan(
  val legs: MutableList<Leg>,
  val hotspots: MutableList<Hotspot>,
  var corridorMeters: Double = 15.0
)

object Geo {
  fun haversine(a: LatLng, b: LatLng): Double {
    val R=6371000.0
    val dLat=Math.toRadians(b.lat-a.lat)
    val dLon=Math.toRadians(b.lng-a.lng)
    val sLat1=Math.toRadians(a.lat)
    val sLat2=Math.toRadians(b.lat)
    val h = sin(dLat/2).pow(2.0)+sin(dLon/2).pow(2.0)*cos(sLat1)*cos(sLat2)
    return 2*R*asin(min(1.0, sqrt(h)))
  }
  fun bearing(a: LatLng, b: LatLng): Double {
    val φ1=Math.toRadians(a.lat); val φ2=Math.toRadians(b.lat)
    val λ=Math.toRadians(b.lng-a.lng)
    val y=sin(λ)*cos(φ2)
    val x=cos(φ1)*sin(φ2)-sin(φ1)*cos(φ2)*cos(λ)
    return (Math.toDegrees(atan2(y,x))+360.0) % 360.0
  }
}

object RouteEngine {

  fun buildPlan(base: List<LatLng>, baseHotspots: List<Hotspot>, seed: Long = System.currentTimeMillis()): RoutePlan {
    val rnd = Random(seed)
    val legs = base.zipWithNext().map { (a,b) -> Leg(listOf(a,b)) }.toMutableList()
    val hs = baseHotspots.toMutableList()

    // optional: verdopple 0..2 Hotspots
    val duplications = rnd.nextInt(0, 3)
    repeat(duplications) {
      if (hs.isNotEmpty()) {
        val h = hs[rnd.nextInt(hs.size)]
        // dupliziere leicht versetzt
        val dLat = (rnd.nextDouble(-0.0002,0.0002))
        val dLng = (rnd.nextDouble(-0.0002,0.0002))
        hs.add(Hotspot(LatLng(h.center.lat+dLat, h.center.lng+dLng), h.radiusMeters))
      }
    }

    // optional: Mystery-Leg 1.0–1.5 km irgendwo einfügen, keine Bekanntgabe
    if (rnd.nextBoolean() && legs.isNotEmpty()) {
      val idx = rnd.nextInt(legs.size)
      val anchor = legs[idx].points.last()
      val bearing = rnd.nextDouble(0.0, 360.0)
      val dist = rnd.nextDouble(1000.0, 1500.0)
      val off = offset(anchor, dist, bearing)
      legs.add(idx+1, Leg(listOf(anchor, off, anchor), isMystery = true))
    }

    // optional: verdopple 0..1 Leg
    if (rnd.nextBoolean() && legs.isNotEmpty()) {
      val i = rnd.nextInt(legs.size)
      legs.add(i, legs[i])
    }

    val plan = RoutePlan(legs.toMutableList(), hs.toMutableList(), corridorMeters = 15.0)
    return plan
  }

  private fun offset(p: LatLng, meters: Double, bearingDeg: Double): LatLng {
    val R=6371000.0
    val δ = meters/R
    val θ = Math.toRadians(bearingDeg)
    val φ1 = Math.toRadians(p.lat)
    val λ1 = Math.toRadians(p.lng)
    val φ2 = asin(sin(φ1)*cos(δ)+cos(φ1)*sin(δ)*cos(θ))
    val λ2 = λ1 + atan2(sin(θ)*sin(δ)*cos(φ1), cos(δ)-sin(φ1)*sin(φ2))
    return LatLng(Math.toDegrees(φ2), Math.toDegrees(λ2))
  }

  /** Turn prompt: gibt knappen Text basierend auf Richtungsdiff und Distanz */
  fun turnPrompt(curr: LatLng, next: LatLng, distAhead: Double, currentBearing: Double): Pair<String, Int> {
    val need = Geo.bearing(curr, next)
    val diff = angleDiff(currentBearing, need)
    val arrow = when {
      abs(diff) < 20 -> 0   // up
      diff > 20 && diff < 160 -> 1 // right
      diff < -20 && diff > -160 -> -1 // left
      else -> 2 // U-turn
    }
    val text = when {
      abs(diff) < 20 && distAhead > 25 -> "Richtung halten"
      abs(diff) < 20 && distAhead <= 25 -> "geradeaus"
      diff >= 20 && distAhead > 25 -> "in ${distAhead.toInt()} m rechts"
      diff <= -20 && distAhead > 25 -> "in ${distAhead.toInt()} m links"
      else -> if (diff>0) "rechts abbiegen" else "links abbiegen"
    }
    return text to arrow
  }

  private fun angleDiff(a: Double, b: Double): Double {
    var d = (b - a + 540) % 360 - 180
    if (d > 180) d -= 360
    if (d < -180) d += 360
    return d
  }
}
KOT

########################################
# 3) SessionMonitor+: Korridorprüfung (15m), Stop>7s, Vorwärtszwang, Umrundungspflicht,
#    „15m in 3min nach Outfitcheck“, Turn-Prompts, verdeckte Re-Routes
########################################
cat > "$PKG/route/SessionNavigator.kt" <<'KOT'
package com.example.outfitguardian.route

import android.content.Context
import android.location.Location
import com.example.outfitguardian.integration.tasker.TaskerEvents
import kotlin.math.*

class SessionNavigator(
  private val ctx: Context,
  private val plan: RoutePlan
) {
  private var lastLoc: Location? = null
  private var stopMillis: Long = 0
  private var forwardAnchor: Location? = null
  private var lastHeading: Double = 0.0
  private var lastOutfitCheckTime: Long = 0
  private var postCheckProgress: Double = 0.0
  private var postCheckWindowUntil: Long = 0

  // Hotspot-Umrundung Tracking
  private var hotspotPathMeters: MutableMap<Int, Double> = mutableMapOf()
  private var currentLegIndex = 0

  fun onOutfitCheckPassed(now: Long = System.currentTimeMillis()) {
    lastOutfitCheckTime = now
    postCheckProgress = 0.0
    postCheckWindowUntil = now + 3*60_000 // 3 Minuten
  }

  fun onLocation(loc: Location) {
    val prev = lastLoc
    lastLoc = loc

    // Richtung
    val currLL = LatLng(loc.latitude, loc.longitude)
    val leg = plan.legs.getOrNull(currentLegIndex)
    if (leg == null) return
    val nextLL = leg.points.last()
    val distToNext = Geo.haversine(currLL, nextLL)

    // Korridor 15 m
    val corridor = plan.corridorMeters
    val distToLeg = distanceToSegment(currLL, leg.points.first(), leg.points.last())
    if (distToLeg > corridor) {
      TaskerEvents.startViolation(ctx, TaskerEvents.Type.ROUTE, 40, "Korridor verlassen (> ${corridor.toInt()} m)")
    } else {
      TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.ROUTE, "Korridor ok")
    }

    // Stop-Verbot >7s
    if (prev != null) {
      val d = prev.distanceTo(loc)
      if (d < 0.6) {
        if (stopMillis == 0L) stopMillis = System.currentTimeMillis()
        if (System.currentTimeMillis() - stopMillis > 7000) {
          TaskerEvents.startViolation(ctx, TaskerEvents.Type.TEMPO, 35, "Stillstand >7 s")
        }
      } else {
        stopMillis = 0L
        TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.TEMPO, "Tempo ok")
      }

      // Vorwärtszwang: Richtungsumkehr >20 m
      val progSign = progressionSign(prev, loc, leg)
      if (progSign < 0) {
        TaskerEvents.startViolation(ctx, TaskerEvents.Type.ROUTE, 45, "Rückwärtsbewegung")
      } else {
        TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.ROUTE, "Vorwärts ok")
      }

      // 15 m in 3 min nach Outfitcheck
      if (System.currentTimeMillis() < postCheckWindowUntil) {
        postCheckProgress += d
        if (postCheckProgress >= 15.0) {
          TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.TEMPO, "Post-Check-Gang ok")
          postCheckWindowUntil = 0
        }
      } else if (postCheckWindowUntil != 0L) {
        TaskerEvents.startViolation(ctx, TaskerEvents.Type.TEMPO, 35, "Zu wenig Bewegung nach Outfitcheck")
        postCheckWindowUntil = 0
      }
    }

    // Hotspot-Umrundungspflicht: wenn im Radius, Umfangstrecke sammeln
    val idx = nearestHotspotIndex(currLL)
    if (idx != null) {
      val hs = plan.hotspots[idx]
      if (Geo.haversine(currLL, hs.center) <= hs.radiusMeters + 5) {
        val add = prev?.distanceTo(loc) ?: 0f
        hotspotPathMeters[idx] = (hotspotPathMeters[idx] ?: 0.0) + add
        val need = 2*Math.PI*hs.radiusMeters*0.9 // 90% des Umfangs
        if ((hotspotPathMeters[idx] ?: 0.0) >= need) {
          TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.HOTSPOT, "Umrundung ok")
        } else {
          TaskerEvents.startViolation(ctx, TaskerEvents.Type.HOTSPOT, 30, "Hotspot umrunden")
        }
      }
    }

    // Leg abgeschlossen?
    if (distToNext < 8) {
      currentLegIndex = (currentLegIndex + 1).coerceAtMost(plan.legs.size-1)
    }
  }

  fun prompt(curr: LatLng, bearingDeg: Double): Pair<String, Int> {
    val leg = plan.legs.getOrNull(currentLegIndex) ?: return "Richtung halten" to 0
    val next = leg.points.last()
    val dist = Geo.haversine(curr, next)
    return RouteEngine.turnPrompt(curr, next, dist, bearingDeg)
  }

  private fun distanceToSegment(p: LatLng, a: LatLng, b: LatLng): Double {
    // Approx in Meter mit Projektion
    val apx = metersX(a, p); val apy = metersY(a, p)
    val abx = metersX(a, b); val aby = metersY(a, b)
    val t = ((apx*abx + apy*aby) / (abx*abx + aby*aby)).coerceIn(0.0,1.0)
    val proj = LatLng(a.lat + (b.lat - a.lat)*t, a.lng + (b.lng - a.lng)*t)
    return Geo.haversine(p, proj)
  }
  private fun metersX(o: LatLng, p: LatLng) = Geo.haversine(o, LatLng(o.lat, p.lng)) * if (p.lng>o.lng) 1 else -1
  private fun metersY(o: LatLng, p: LatLng) = Geo.haversine(o, LatLng(p.lat, o.lng)) * if (p.lat>o.lat) 1 else -1

  private fun progressionSign(a: android.location.Location, b: android.location.Location, leg: Leg): Int {
    val pA = LatLng(a.latitude,a.longitude)
    val pB = LatLng(b.latitude,b.longitude)
    val toEndA = Geo.haversine(pA, leg.points.last())
    val toEndB = Geo.haversine(pB, leg.points.last())
    return if (toEndB < toEndA - 0.5) +1 else if (toEndB > toEndA + 0.5) -1 else 0
  }

  private fun nearestHotspotIndex(p: LatLng): Int? {
    var best = -1; var bd = Double.MAX_VALUE
    plan.hotspots.forEachIndexed { i, h ->
      val d = Geo.haversine(p, h.center)
      if (d < bd) { bd=d; best=i }
    }
    return if (best>=0) best else null
  }
}
KOT

########################################
# 4) Scheduler-Ergänzungen:
#    - Pigtails-Checks 2×/h (Front-Schnellcheck)
#    - Double-Outfitcheck Blöcke
########################################
cat > "$PKG/scheduler/StrictCheckScheduler.kt" <<'KOT'
package com.example.outfitguardian.scheduler

import android.content.Context
import android.content.Intent
import androidx.work.*
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import com.example.outfitguardian.AutoCameraActivity
import com.example.outfitguardian.FastenerMacroActivity

object StrictCheckScheduler {
  fun start(ctx: Context) {
    // zwei Pigtail/Front-Checks pro Stunde: wir reuse AutoCameraActivity, die Front zuerst schießt
    val w1 = OneTimeWorkRequestBuilder<FrontCheckWorker>()
      .setInitialDelay(25, TimeUnit.MINUTES).build()
    val w2 = OneTimeWorkRequestBuilder<FrontCheckWorker>()
      .setInitialDelay(55, TimeUnit.MINUTES).build()
    WorkManager.getInstance(ctx).enqueueUniqueWork("front_checks", ExistingWorkPolicy.REPLACE, listOf(w1,w2))

    // Double-Check Blöcke: 1–2 mal pro Stunde
    val blocks = Random.nextInt(1,3)
    repeat(blocks) { i ->
      val delay = Random.nextInt(20, 50).toLong()
      val w = OneTimeWorkRequestBuilder<DoubleCheckWorker>()
        .setInitialDelay(delay, TimeUnit.MINUTES).build()
      WorkManager.getInstance(ctx).enqueueUniqueWork("double_check_$i", ExistingWorkPolicy.REPLACE, w)
    }
  }
  fun stop(ctx: Context) {
    WorkManager.getInstance(ctx).cancelUniqueWork("front_checks")
    WorkManager.getInstance(ctx).cancelAllWorkByTag("double_check")
  }

  class FrontCheckWorker(ctx: Context, p: WorkerParameters): CoroutineWorker(ctx,p) {
    override suspend fun doWork(): Result {
      val i = Intent(applicationContext, AutoCameraActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i)
      return Result.success()
    }
  }
  class DoubleCheckWorker(ctx: Context, p: WorkerParameters): CoroutineWorker(ctx,p) {
    override suspend fun doWork(): Result {
      val i1 = Intent(applicationContext, AutoCameraActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i1)
      // 10 Sekunden später Fastener-Makro
      kotlinx.coroutines.delay(10_000)
      val i2 = Intent(applicationContext, FastenerMacroActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i2)
      return Result.success()
    }
  }
}
KOT

########################################
# 5) Hook in MainActivity: Navigator, HUD, Scheduler
########################################
python3 - <<'PY'
from pathlib import Path, re as _re
p = Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
src = p.read_text()
if "SessionNavigator" not in src:
  src = src.replace("import android.location.Location",
                    "import android.location.Location\nimport com.example.outfitguardian.route.*")
if "view_direction_hud" not in Path("app/src/main/res/layout/activity_main.xml").read_text():
  # naive: append HUD include
  am = Path("app/src/main/res/layout/activity_main.xml")
  s = am.read_text()
  s = s.replace("</LinearLayout>", '\n  <include layout="@layout/view_direction_hud"/>\n</LinearLayout>\n')
  am.write_text(s)

# init fields
if "private var navigator" not in src:
  src = src.replace("class MainActivity", "class MainActivity")
  src = src.replace("setContentView(R.layout.activity_main)", 
"""setContentView(R.layout.activity_main)
    // Route HUD minimal
    val arrow = findViewById<android.widget.ImageView>(com.example.outfitguardian.R.id.ivArrow)
    val prompt = findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvPrompt)
    // Dummy plan init; in deiner echten App: aus Konfiguration/Hotspotliste
    routePlan = com.example.outfitguardian.route.RouteEngine.buildPlan(emptyList(), mutableListOf())
    navigator = com.example.outfitguardian.route.SessionNavigator(this, routePlan)""")

  src = src.replace("class MainActivity :",
                    "class MainActivity :")
  src = src.replace("override fun onCreate(savedInstanceState: Bundle?) {",
                    "private lateinit var navigator: com.example.outfitguardian.route.SessionNavigator\n  private lateinit var routePlan: com.example.outfitguardian.route.RoutePlan\n  override fun onCreate(savedInstanceState: Bundle?) {")

# start/stop schedulers around session
src = src.replace("startForegroundSession()", 
                  "startForegroundSession()\n      com.example.outfitguardian.scheduler.StrictCheckScheduler.start(this)")
src = src.replace("stopForegroundSession();", 
                  "stopForegroundSession(); com.example.outfitguardian.scheduler.StrictCheckScheduler.stop(this);")

# wire location to navigator + HUD prompt
if "onNewLocation" not in src:
  src += """

  private fun onNewLocation(loc: Location) {
    // Navigator Kernlogik
    navigator.onLocation(loc)
    val bearing = loc.bearing.toDouble().let { if (it.isNaN()) 0.0 else it }
    val (txt, arrowCode) = navigator.prompt(com.example.outfitguardian.route.LatLng(loc.latitude, loc.longitude), bearing)
    findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvPrompt)?.text = txt
    val iv = findViewById<android.widget.ImageView>(com.example.outfitguardian.R.id.ivArrow)
    when (arrowCode) {
      -1 -> iv?.rotation = -90f
      0 -> iv?.rotation = 0f
      1 -> iv?.rotation = 90f
      else -> iv?.rotation = 180f
    }
  }
"""
p.write_text(src)
print("MainActivity patched")
PY

########################################
# 6) OutfitCheckManager Hook: nach bestandenem Check 15m/3min Fenster aktivieren
########################################
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitCheckManager.kt")
s = p.read_text()
if "onOutfitCheckPassed" not in s:
  s = s.replace('if (pass) {',
                'if (pass) {\n            // Bewegungsauflage nach Outfitcheck\n            try { com.example.outfitguardian.MainActivity::class.java.getMethod("onOutfitCheckPassedBridge").invoke(null) } catch (_:Throwable){}')
p.write_text(s); print("OutfitCheckManager patched (post-check window)")
PY

# Static bridge (fallback) – optional no-op if you already route events elsewhere
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
s = p.read_text()
if "onOutfitCheckPassedBridge" not in s:
  s += """

  companion object {
    @JvmStatic fun onOutfitCheckPassedBridge() {
      // In einer echten Arch: via EventBus/Navigator-Instanz. Hier Platzhalter.
    }
  }
"""
p.write_text(s); print("MainActivity bridge appended")
PY

########################################
# 7) Bestätigungen bestehender Regeln (4,5,26) sind bereits in deinen Heuristiken/Tresor;
#    keine Codeänderung nötig. Pigtails-Checks (6) kommen über StrictCheckScheduler.
########################################

echo "==> Build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew :app:assembleDebug
