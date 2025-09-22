#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"

echo "==> SessionMonitor schreiben"
mkdir -p "$PKG/session"
cat > "$PKG/session/SessionMonitor.kt" <<'KOT'
package com.example.outfitguardian.session

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.*
import com.example.outfitguardian.integration.tasker.TaskerEvents
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.*

/**
 * SessionMonitor überwacht:
 * - Geschwindigkeit (Soll 1.5 km/h)
 * - Stillstand (>10s)
 * - Korridorabweichung (20m)
 * - Backtracking (>120° Abweichung)
 * - Hotspots mit Verweilzeit
 * - Rote Zone Start/Ziel
 */
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

        val req = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY, 5000
        ).setMinUpdateIntervalMillis(3000).build()

        client.requestLocationUpdates(req, callback, Looper.getMainLooper())
    }

    fun stop() {
        client.removeLocationUpdates(callback)
    }

    private val callback = object: LocationCallback() {
        override fun onLocationResult(res: LocationResult) {
            for (loc in res.locations) {
                handleLocation(loc)
            }
        }
    }

    private fun handleLocation(loc: Location) {
        val now = System.currentTimeMillis()
        val last = lastLoc
        lastLoc = loc

        // Geschwindigkeit km/h
        val spd = loc.speed * 3.6f
        if (spd < 1.0) {
            if (stillSince==0L) stillSince=now
            if (now-stillSince > 10000) {
                TaskerEvents.startViolation(ctx, TaskerEvents.Type.STOP, 70, "Stillstand >10s")
            }
        } else {
            stillSince=0L
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.STOP, "Bewegung wieder erkannt")
        }

        if (spd < 1.2) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.SPEED, 40, "Unter Solltempo (1.5km/h)")
        } else if (spd > 3.0) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.SPEED, 40, "Über Solltempo")
        } else {
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.SPEED, "Tempo im Sollbereich")
        }

        // Korridor: Distanz zur Route >20m?
        if (route.isNotEmpty()) {
            val d = distanceToPolyline(loc.latitude, loc.longitude, route)
            if (d > 20) {
                TaskerEvents.startViolation(ctx, TaskerEvents.Type.CORRIDOR, 60, "Korridor überschritten (${d.toInt()}m)")
            } else {
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.CORRIDOR, "Zurück im Korridor")
            }
        }

        // Backtracking (Heading)
        if (last != null && route.isNotEmpty()) {
            val segAz = bearing(route.first().first, route.first().second, route.last().first, route.last().second)
            val diff = abs(loc.bearing - segAz)
            if (diff > 120) {
                if (backtrackSince==0L) backtrackSince=now
                if (now-backtrackSince > 6000) {
                    TaskerEvents.startViolation(ctx, TaskerEvents.Type.BACKTRACK, 80, "Rückwärtsbewegung erkannt")
                }
            } else {
                backtrackSince=0L
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.BACKTRACK, "Richtung wieder korrekt")
            }
        }

        // Hotspots
        for (hs in hotspots) {
            val d = haversine(loc.latitude, loc.longitude, hs.lat, hs.lng)
            if (!hs.done && d < 20) {
                if (hs.enteredAt==null) hs.enteredAt=now
                val stay = (now-hs.enteredAt!!)/60000
                if (stay >= hs.stayMin) {
                    hs.done=true
                }
            }
        }

        // Rote Zone Start/Ziel
        val dz = haversine(loc.latitude, loc.longitude, startLat, startLng)
        if (dz < 50 && !allHotspotsDone()) {
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.RED_ZONE, 50, "Rote Zone Start/Ziel vor Ende")
        } else {
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.RED_ZONE, "Zone verlassen oder Sessionende")
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
            val d = distanceToSegment(lat, lon, pts[i], pts[i+1])
            if (d<best) best=d
        }
        return best
    }

    private fun distanceToSegment(lat:Double, lon:Double, a:Pair<Double,Double>, b:Pair<Double,Double>):Double {
        val A= Location("").apply { latitude=a.first; longitude=a.second }
        val B= Location("").apply { latitude=b.first; longitude=b.second }
        val P= Location("").apply { latitude=lat; longitude=lon }
        val AB=A.distanceTo(B)
        if (AB==0f) return P.distanceTo(A).toDouble()
        val AP=A.distanceTo(P)
        val t = ((P.latitude-A.latitude)*(B.latitude-A.latitude)+(P.longitude-A.longitude)*(B.longitude-A.longitude)) /
                ((B.latitude-A.latitude).pow(2)+(B.longitude-A.longitude).pow(2))
        return when {
            t<0 -> P.distanceTo(A).toDouble()
            t>1 -> P.distanceTo(B).toDouble()
            else -> {
                val latProj=A.latitude+t*(B.latitude-A.latitude)
                val lonProj=A.longitude+t*(B.longitude-A.longitude)
                haversine(lat,lon,latProj,lonProj)
            }
        }
    }
}
KOT

echo "==> build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
