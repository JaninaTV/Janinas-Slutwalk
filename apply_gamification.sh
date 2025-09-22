#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"

echo "==> SessionScoreManager schreiben"
mkdir -p "$PKG/session"
cat > "$PKG/session/SessionScoreManager.kt" <<'KOT'
package com.example.outfitguardian.session

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Gamification & Log:
 * - Punkte für Hotspots, Outfitchecks, konstantes Tempo
 * - Abzug für Verstöße
 * - Session-Log mit Events (Typ, Zeit, Nachricht)
 */
object SessionScoreManager {
    private const val PREF = "session_score"
    private const val KEY_POINTS = "points"
    private const val KEY_LOG = "log_json"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun reset(ctx: Context) {
        prefs(ctx).edit().putInt(KEY_POINTS, 0).putString(KEY_LOG, JSONArray().toString()).apply()
    }

    fun addPoints(ctx: Context, pts: Int, reason: String) {
        val p = prefs(ctx)
        val current = p.getInt(KEY_POINTS, 0)
        val newVal = current + pts
        p.edit().putInt(KEY_POINTS, newVal).apply()
        appendLog(ctx, "POINTS", "$reason (+$pts)", newVal)
    }

    fun subtractPoints(ctx: Context, pts: Int, reason: String) {
        val p = prefs(ctx)
        val current = p.getInt(KEY_POINTS, 0)
        val newVal = current - pts
        p.edit().putInt(KEY_POINTS, newVal).apply()
        appendLog(ctx, "POINTS", "$reason (-$pts)", newVal)
    }

    fun getPoints(ctx: Context): Int = prefs(ctx).getInt(KEY_POINTS, 0)

    fun getLog(ctx: Context): List<JSONObject> {
        val s = prefs(ctx).getString(KEY_LOG, JSONArray().toString()) ?: "[]"
        val arr = JSONArray(s)
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    private fun appendLog(ctx: Context, type: String, msg: String, score: Int?=null) {
        val arr = JSONArray(prefs(ctx).getString(KEY_LOG, JSONArray().toString()))
        val o = JSONObject()
        o.put("time", System.currentTimeMillis())
        o.put("type", type)
        o.put("msg", msg)
        if (score != null) o.put("score", score)
        arr.put(o)
        prefs(ctx).edit().putString(KEY_LOG, arr.toString()).apply()
    }

    fun logEvent(ctx: Context, type: String, msg: String) {
        appendLog(ctx, type, msg, getPoints(ctx))
    }
}
KOT

echo "==> SessionMonitor erweitern: Punkte + Log"
cat > "$PKG/session/SessionMonitor.kt" <<'KOT'
package com.example.outfitguardian.session

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.*
import com.example.outfitguardian.integration.tasker.TaskerEvents
import org.json.JSONArray
import kotlin.math.*

class SessionMonitor(private val ctx: Context) {

    private val client = LocationServices.getFusedLocationProviderClient(ctx)
    private var lastLoc: Location? = null
    private var route: List<Pair<Double,Double>> = emptyList()
    private var hotspots: List<Hotspot> = emptyList()
    private var startLat = 0.0
    private var startLng = 0.0

    private var stillSince: Long = 0
    private var backtrackSince: Long = 0

    data class Hotspot(val name:String, val lat:Double, val lng:Double, val stayMin:Int, var enteredAt:Long?=null, var done:Boolean=false)

    @SuppressLint("MissingPermission")
    fun start(routeJson:String, spotsJson:String) {
        val rArr = JSONArray(routeJson)
        route = (0 until rArr.length()).map {
            val o = rArr.getJSONObject(it)
            o.getDouble("lat") to o.getDouble("lng")
        }
        val sArr = JSONArray(spotsJson)
        hotspots = (0 until sArr.length()).map {
            val o = sArr.getJSONObject(it)
            Hotspot(o.getString("name"), o.getDouble("lat"), o.getDouble("lng"), o.getInt("stayMin"))
        }
        if (route.isNotEmpty()) {
            startLat = route.first().first
            startLng = route.first().second
        }

        SessionScoreManager.reset(ctx)
        SessionScoreManager.logEvent(ctx, "SESSION", "Session gestartet")

        val req = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000)
            .setMinUpdateIntervalMillis(3000).build()
        client.requestLocationUpdates(req, callback, Looper.getMainLooper())
    }

    fun stop() {
        client.removeLocationUpdates(callback)
        SessionScoreManager.logEvent(ctx, "SESSION", "Session gestoppt")
    }

    private val callback = object: LocationCallback() {
        override fun onLocationResult(res: LocationResult) {
            for (loc in res.locations) handleLocation(loc)
        }
    }

    private fun handleLocation(loc: Location) {
        val now = System.currentTimeMillis()
        val last = lastLoc
        lastLoc = loc

        val spd = loc.speed * 3.6f
        if (spd < 1.0) {
            if (stillSince==0L) stillSince=now
            if (now-stillSince > 10000) {
                TaskerEvents.startViolation(ctx, TaskerEvents.Type.STOP, 70, "Stillstand >10s")
                SessionScoreManager.subtractPoints(ctx, 5, "Stillstand")
            }
        } else {
            stillSince=0L
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.STOP, "Bewegung erkannt")
        }

        if (spd < 1.2) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.SPEED, 40, "Unter Solltempo (1.5km/h)")
            SessionScoreManager.subtractPoints(ctx, 2, "Zu langsam")
        } else if (spd > 3.0) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.SPEED, 40, "Über Solltempo")
            SessionScoreManager.subtractPoints(ctx, 2, "Zu schnell")
        } else {
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.SPEED, "Tempo ok")
            SessionScoreManager.addPoints(ctx, 1, "Tempo im Soll")
        }

        if (route.isNotEmpty()) {
            val d = distanceToPolyline(loc.latitude, loc.longitude, route)
            if (d > 20) {
                TaskerEvents.startViolation(ctx, TaskerEvents.Type.CORRIDOR, 60, "Korridor überschritten (${d.toInt()}m)")
                SessionScoreManager.subtractPoints(ctx, 3, "Korridor verlassen")
            } else {
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.CORRIDOR, "Korridor ok")
            }
        }

        if (last != null && route.isNotEmpty()) {
            val segAz = bearing(route.first().first, route.first().second, route.last().first, route.last().second)
            val diff = abs(loc.bearing - segAz)
            if (diff > 120) {
                if (backtrackSince==0L) backtrackSince=now
                if (now-backtrackSince > 6000) {
                    TaskerEvents.startViolation(ctx, TaskerEvents.Type.BACKTRACK, 80, "Rückwärtsbewegung")
                    SessionScoreManager.subtractPoints(ctx, 4, "Backtracking")
                }
            } else {
                backtrackSince=0L
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.BACKTRACK, "Richtung ok")
            }
        }

        for (hs in hotspots) {
            val d = haversine(loc.latitude, loc.longitude, hs.lat, hs.lng)
            if (!hs.done && d < 20) {
                if (hs.enteredAt==null) hs.enteredAt=now
                val stay = (now-hs.enteredAt!!)/60000
                if (stay >= hs.stayMin) {
                    hs.done=true
                    SessionScoreManager.addPoints(ctx, 10, "Hotspot ${hs.name} erfüllt")
                    SessionScoreManager.logEvent(ctx, "HOTSPOT", "${hs.name} abgeschlossen")
                }
            }
        }

        val dz = haversine(loc.latitude, loc.longitude, startLat, startLng)
        if (dz < 50 && !allHotspotsDone()) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.RED_ZONE, 50, "Rote Zone Start/Ziel")
            SessionScoreManager.subtractPoints(ctx, 5, "Rote Zone vor Ende")
        } else {
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.RED_ZONE, "Zone ok")
        }
    }

    private fun allHotspotsDone(): Boolean = hotspots.all { it.done }

    private fun haversine(lat1:Double, lon1:Double, lat2:Double, lon2:Double): Double {
        val R=6371000.0
        val dLat=Math.toRadians(lat2-lat1)
        val dLon=Math.toRadians(lon2-lon1)
        val a=sin(dLat/2).pow(2.0)+cos(Math.toRadians(lat1))*cos(Math.toRadians(lat2))*sin(dLon/2).pow(2.0)
        val c=2*atan2(sqrt(a), sqrt(1-a))
        return R*c
    }

    private fun bearing(lat1:Double, lon1:Double, lat2:Double, lon2:Double): Float {
        val dLon=Math.toRadians(lon2-lon1)
        val y=sin(dLon)*cos(Math.toRadians(lat2))
        val x=cos(Math.toRadians(lat1))*sin(Math.toRadians(lat2))-sin(Math.toRadians(lat1))*cos(Math.toRadians(lat2))*cos(dLon)
        return Math.toDegrees(atan2(y,x)).toFloat()
    }

    private fun distanceToPolyline(lat:Double, lon:Double, pts:List<Pair<Double,Double>>):Double {
        var best=Double.MAX_VALUE
        for (i in 0 until pts.size-1) {
            val d = haversine(lat,lon,pts[i].first,pts[i].second)
            if (d<best) best=d
        }
        return best
    }
}
KOT

echo "==> build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
