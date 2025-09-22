package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class RegionRects(val shoes: Rect, val socks: Rect, val hemStripe: Rect, val torsoStripe: Rect, val eyes: Rect)

data class RegionFeatures(val hueHist: FloatArray, val edgeRate: Float)
data class FrameFeatures(
    val socks: RegionFeatures,
    val legs: RegionFeatures,
    val shoes: RegionFeatures,
    val hemY: Int,
    val eyeSat: Float,
    val eyesLumaDarkFrac: Float
)

object OutfitHeuristics {

  /**
   * Absatzhöhe grob aus Seitenprofil schätzen. Ja, das ist hemdsärmelig,
   * reicht aber für Monotonie/Max-Fixierung.
   */
  fun estimateHeelHeightCm(bmp: android.graphics.Bitmap): Float {
    val shoes = regions(bmp).shoes
    val groundY = estimateGroundLineY(bmp, shoes)
    val heelPeakY = estimateHeelPeakY(bmp, shoes, groundY)
    val px = (groundY - heelPeakY).coerceAtLeast(0)
    // naive Umrechnung: 7 px ≈ 1 cm (dein Setup kalibriert's besser)
    return (px / 7f).coerceAtLeast(0f)
  }



  /**
   * Grobe Erkennung: roter Tartan + Falten (Plissee).
   * Metrik: Rotdominanz + vertikale Periodik (Faltenkämme) im Saumbereich.
   */
  fun tartanPleatScore(bmp: android.graphics.Bitmap): Float {
    val r = regions(bmp).hemStripe
    val step = kotlin.math.max(1, kotlin.math.min(r.width(), r.height())/128)
    var redBins = 0; var total=0
    var verticalEdges = 0
    var y = r.top
    while (y < r.bottom) {
      var x = r.left
      while (x < r.right - step) {
        val c = bmp.getPixel(x, y)
        val R = (c ushr 16) and 0xFF; val G = (c ushr 8) and 0xFF; val B = c and 0xFF
        // „rot“ dominiert klar
        if (R > G + 10 && R > B + 10) redBins++
        val c2 = bmp.getPixel(x+step, y)
        val l1 = ((R*299 + G*587 + B*114)/1000)
        val l2 = ((((c2 ushr 16) and 0xFF)*299 + ((c2 ushr 8) and 0xFF)*587 + ((c2) and 0xFF)*114)/1000)
        if (kotlin.math.abs(l2 - l1) > 28) verticalEdges++
        total++; x += step
      }
      y += step
    }
    val redFrac = if (total==0) 0f else redBins.toFloat()/total.toFloat()
    val edgeFrac = if (total==0) 0f else verticalEdges.toFloat()/total.toFloat()
    // beide Anteile hoch => plausibles Tartan+Falten
    return (0.6f*redFrac + 0.4f*edgeFrac).coerceIn(0f,1f)
  }



  /**
   * Spannrock/Up-Curve-Score: misst, ob die Saumlinie in der Mitte höher liegt
   * als links/rechts (gebogener Saum nach oben).
   * 0..1: niedrig..hoch
   */
  fun hemTensionScore(bmp: android.graphics.Bitmap): Float {
    val r = regions(bmp).hemStripe
    val cx = (r.left + r.right)/2
    val midY = (r.top + r.bottom)/2
    val step = kotlin.math.max(1, kotlin.math.min(r.width(), r.height())/128)
    var midEdge = 0; var sideEdge = 0; var count=0
    // Kanten vertikal messen
    var y = r.top
    while (y < r.bottom - step) {
      val cMid1 = bmp.getPixel(cx, y)
      val cMid2 = bmp.getPixel(cx, y+step)
      val l1 = ((cMid1 shr 16 and 0xFF)*299 + (cMid1 shr 8 and 0xFF)*587 + (cMid1 and 0xFF)*114)/1000
      val l2 = ((cMid2 shr 16 and 0xFF)*299 + (cMid2 shr 8 and 0xFF)*587 + (cMid2 and 0xFF)*114)/1000
      if (kotlin.math.abs(l2-l1) > 30) midEdge++
      val cL1 = bmp.getPixel(r.left + step, y)
      val cL2 = bmp.getPixel(r.left + step, y+step)
      val lL1 = ((cL1 shr 16 and 0xFF)*299 + (cL1 shr 8 and 0xFF)*587 + (cL1 and 0xFF)*114)/1000
      val lL2 = ((cL2 shr 16 and 0xFF)*299 + (cL2 shr 8 and 0xFF)*587 + (cL2 and 0xFF)*114)/1000
      if (kotlin.math.abs(lL2-lL1) > 30) sideEdge++
      val cR1 = bmp.getPixel(r.right - step, y)
      val cR2 = bmp.getPixel(r.right - step, y+step)
      val lR1 = ((cR1 shr 16 and 0xFF)*299 + (cR1 shr 8 and 0xFF)*587 + (cR1 and 0xFF)*114)/1000
      val lR2 = ((cR2 shr 16 and 0xFF)*299 + (cR2 shr 8 and 0xFF)*587 + (cR2 and 0xFF)*114)/1000
      if (kotlin.math.abs(lR2-lR1) > 30) sideEdge++
      count++; y += step
    }
    val side = kotlin.math.max(1, sideEdge)
    val ratio = midEdge.toFloat() / side.toFloat()
    // Wenn Mitte "höher" kantig wechselt als Seiten, deutet das auf Bogen nach oben hin
    return ratio.coerceIn(0f, 1.5f) / 1.5f
  }



    // Regionen relativ zur Bildhöhe definieren
    fun regions(bmp: Bitmap): RegionRects {
        val w = bmp.width
        val h = bmp.height
        fun r(x0: Int, y0: Int, x1: Int, y1: Int) = Rect(
            x0.coerceIn(0, w-1), y0.coerceIn(0, h-1),
            x1.coerceIn(1, w),   y1.coerceIn(1, h)
        )
        val shoes = r( (w*0.05).toInt(), (h*0.85).toInt(), (w*0.95).toInt(), h )
        val socks = r( (w*0.10).toInt(), (h*0.65).toInt(), (w*0.90).toInt(), (h*0.85).toInt() )
        val hemStripe = r( (w*0.10).toInt(), (h*0.45).toInt(), (w*0.90).toInt(), (h*0.60).toInt() )
        val torso = r( (w*0.10).toInt(), (h*0.55).toInt(), (w*0.90).toInt(), (h*0.70).toInt() )
        val eyes = r( (w*0.30).toInt(), (h*0.15).toInt(), (w*0.70).toInt(), (h*0.30).toInt() )
        return RegionRects(shoes, socks, hemStripe, torso, eyes)
    }

    // HSV-Hist in 24 Bins + Kantenrate (einfach) einer Region
    fun regionFeatures(bmp: Bitmap, rect: Rect): RegionFeatures {
        val bins = FloatArray(24)
        var edges = 0
        var count = 0
        val step = max(1, min(rect.width(), rect.height()) / 128) // subsampling
        var y = rect.top
        while (y < rect.bottom) {
            var x = rect.left
            while (x < rect.right) {
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

                if (x + step < rect.right) {
                    val c2 = bmp.getPixel(x + step, y)
                    val l1 = (r*299 + g*587 + b*114)/1000
                    val r2 = (c2 shr 16) and 0xFF
                    val g2 = (c2 shr 8) and 0xFF
                    val b2 = c2 and 0xFF
                    val l2 = (r2*299 + g2*587 + b2*114)/1000
                    if (abs(l1 - l2) > 28) edges++
                }
                count++
                x += step
            }
            y += step
        }
        val sum = bins.sum().takeIf { it > 0 } ?: 1f
        for (i in bins.indices) bins[i] /= sum
        val edgeRate = edges.toFloat() / count.toFloat().coerceAtLeast(1f)
        return RegionFeatures(bins, edgeRate)
    }

    fun cosine(a: FloatArray, b: FloatArray): Float {
        var dot = 0f; var na = 0f; var nb = 0f
        for (i in a.indices) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
        if (na == 0f || nb == 0f) return 0f
        return dot / sqrt(na*nb)
    }

    // einfache Schätzung der Saumlinie: stärkste horizontale Kantenakkumulation in der Mitte
    fun estimateHemY(bmp: Bitmap): Int {
        val h = bmp.height; val w = bmp.width
        val yTop = (h*0.35f).toInt(); val yBot = (h*0.70f).toInt()
        var bestY = (h*0.5f).toInt(); var bestScore = -1
        for (y in yTop until yBot step 2) {
            var s = 0
            var x = (w*0.1f).toInt()
            while (x < (w*0.9f).toInt()-2) {
                val c1 = bmp.getPixel(x,y)
                val c2 = bmp.getPixel(x,y+2)
                val l1 = ((c1 shr 16 and 0xFF)*299 + (c1 shr 8 and 0xFF)*587 + (c1 and 0xFF)*114)/1000
                val l2 = ((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
                if (abs(l1 - l2) > 24) s++
                x += 4
            }
            if (s > bestScore) { bestScore = s; bestY = y }
        }
        return bestY
    }

    // Sehr grobe Heuristik: Absatzhöhe über Konturknick im Schuhbereich (nur Seitenpose wirklich gut)
    fun heelLikelyHigh(bmp: Bitmap): Boolean {
        val r = regions(bmp).shoes
        // Edge-Dichte relativ hoch + vertikale Kantenhäufung -> "hoch"
        val f = regionFeatures(bmp, r)
        return f.edgeRate > 0.18f
    }

    // "weiß" Anteil im Sockenfenster
    fun whiteRatioSocks(bmp: Bitmap): Float {
        val r = regions(bmp).socks
        var white = 0; var tot = 0
        val step = max(1, min(r.width(), r.height()) / 128)
        var y = r.top
        while (y < r.bottom) {
            var x = r.left
            while (x < r.right) {
                val c = bmp.getPixel(x,y)
                val r8 = (c shr 16) and 0xFF
                val g8 = (c shr 8) and 0xFF
                val b8 = c and 0xFF
                val mx = max(r8, max(g8, b8)).toFloat()
                val mn = min(r8, min(g8, b8)).toFloat()
                val sat = if (mx == 0f) 0f else 1f - (mn/mx)
                val v = mx/255f
                if (sat < 0.25f && v > 0.85f) white++
                tot++
                x += step
            }
            y += step
        }
        return if (tot == 0) 0f else white.toFloat()/tot.toFloat()
    }

    // Augen-Make-up "deutlich" (dunkler Anteil + Sättigung)
    fun eyeMakeupSignals(bmp: Bitmap): Pair<Float, Float> {
        val r = regions(bmp).eyes
        var dark = 0; var total = 0; var sSum = 0f
        val step = max(1, min(r.width(), r.height())/64)
        var y = r.top
        while (y < r.bottom) {
            var x = r.left
            while (x < r.right) {
                val c = bmp.getPixel(x,y)
                val r8 = (c shr 16) and 0xFF
                val g8 = (c shr 8) and 0xFF
                val b8 = c and 0xFF
                val luma = (r8*299 + g8*587 + b8*114)/1000
                val mx = max(r8, max(g8,b8)).toFloat()
                val mn = min(r8, min(g8,b8)).toFloat()
                val sat = if (mx == 0f) 0f else 1f - (mn/mx)
                if (luma < 70) dark++
                sSum += sat
                total++
                x += step
            }
            y += step
        }
        val darkFrac = if (total==0) 0f else dark.toFloat()/total.toFloat()
        val satAvg = if (total==0) 0f else sSum/total.toFloat()
        return satAvg to darkFrac
    }

    fun frameFeatures(bmp: Bitmap): FrameFeatures {
        val regs = regions(bmp)
        val socksF = regionFeatures(bmp, regs.socks)
        // Beine-Crop: über Socken bis unter Saum
        val legsRect = Rect(regs.socks.left, (bmp.height*0.45f).toInt(), regs.socks.right, regs.socks.bottom)
        val legsF = regionFeatures(bmp, legsRect)
        val shoesF = regionFeatures(bmp, regs.shoes)
        val hemY = estimateHemY(bmp)
        val (eyeSat, eyesDark) = eyeMakeupSignals(bmp)
        return FrameFeatures(socksF, legsF, shoesF, hemY, eyeSat, eyesDark)
    }
}
