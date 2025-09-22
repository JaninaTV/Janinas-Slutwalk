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
