package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class FeatureVec(val hueHist: FloatArray, val edgeRate: Float)

object OutfitFeatures {

  fun decode(path: String): Bitmap? =
    BitmapFactory.decodeFile(path)

  fun features(bmp: Bitmap): FeatureVec {
    val w = bmp.width; val h = bmp.height
    val bins = FloatArray(24)
    var edges = 0
    var total = 0

    var y = 0
    while (y < h) {
      var x = 0
      while (x < w) {
        val c = bmp.getPixel(x, y)
        val r = (c shr 16) and 0xFF
        val g = (c shr 8) and 0xFF
        val b = c and 0xFF
        val mx = max(r, max(g, b)).toFloat()
        val mn = min(r, min(g, b)).toFloat()
        val d = mx - mn
        val hDeg = when {
          d == 0f -> 0f
          mx == r.toFloat() -> 60f * (((g - b) / d) % 6f)
          mx == g.toFloat() -> 60f * (((b - r) / d) + 2f)
          else -> 60f * (((r - g) / d) + 4f)
        }
        val hue = ((hDeg + 360f) % 360f)
        val bin = (hue / 15f).toInt().coerceIn(0, 23)
        bins[bin] += 1f

        // einfache Kante horizontal
        if (x+2 < w) {
          val c2 = bmp.getPixel(x+2, y)
          val r2 = (c2 shr 16) and 0xFF
          val g2 = (c2 shr 8) and 0xFF
          val b2 = c2 and 0xFF
          val l1 = (r*299 + g*587 + b*114)/1000
          val l2 = (r2*299 + g2*587 + b2*114)/1000
          if (abs(l1 - l2) > 28) edges++
        }

        total++
        x += 4
      }
      y += 4
    }
    // Normieren
    val sum = bins.sum().takeIf { it > 0f } ?: 1f
    for (i in bins.indices) bins[i] /= sum
    val edgeRate = edges.toFloat() / total.toFloat().coerceAtLeast(1f)
    return FeatureVec(bins, edgeRate)
  }

  fun cosine(a: FloatArray, b: FloatArray): Float {
    var dot = 0f; var na = 0f; var nb = 0f
    for (i in a.indices) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
    if (na == 0f || nb == 0f) return 0f
    return (dot / kotlin.math.sqrt(na*nb))
  }

  /** einfacher Vergleich: Hue-Ähnlichkeit UND ähnliche Kantenrate */
  fun similar(a: FeatureVec, b: FeatureVec, hueMin: Float = 0.92f, edgeTol: Float = 0.08f): Boolean {
    val hueSim = cosine(a.hueHist, b.hueHist)
    val edgeOk = kotlin.math.abs(a.edgeRate - b.edgeRate) <= edgeTol
    return hueSim >= hueMin && edgeOk
  }
}
