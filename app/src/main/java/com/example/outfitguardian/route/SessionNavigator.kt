package com.example.outfitguardian.route

import android.content.Context
import android.location.Location
import com.example.outfitguardian.integration.tasker.TaskerEvents
import kotlin.math.*

class SessionNavigator(
  private val ctx: android.content.Context,
  private val plan: RoutePlan
) {
  // FAIL_REACTION_BLOCK
  private var corridorM: Int = 15

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

  private fun insertBonusLoop(lenM: Double) {
    val a = currentLatLng()
    val b = offset(a, lenM/3, 45.0)
    val c = offset(b, lenM/3, -120.0)
    val d = a
    val leg = Leg(listOf(a,b,c,d), isMystery = true)
    val insertAt = (currentLegIndex+1).coerceAtMost(plan.legs.size)
    plan.legs.add(insertAt, leg)
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
