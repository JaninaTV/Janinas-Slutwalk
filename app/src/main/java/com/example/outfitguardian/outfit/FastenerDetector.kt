package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

object FastenerDetector {

  data class Result(val score: Float, val closedHeelLikely: Boolean)

  /**
   * Liefert Fastener-Score (0..1) und closed-heel Indiz.
   * Heuristiken:
   * - Metallreflexe (helle, wenig gesättigte Punkte) im Knöchel-/Rist-ROI
   * - Regelmäßige vertikale Linien (Ösen/Schnürung)
   * - Zickzack-Kantenmuster (Schnürung)
   * - Fersenkappe geschlossen: dunkle, zusammenhängende Kontur am hinteren Schuhdrittel
   */
  fun analyze(bmp: Bitmap): Result {
    val regs = OutfitHeuristics.regions(bmp)
    val ankle = inflate(regs.shoes, bmp, 0.0f).let {
      Rect(it.left, it.top, it.right, min(bmp.height, it.top + (it.height()*0.55f).toInt()))
    }
    val heelBox = Rect(
      (ankle.left + ankle.width()*0.55f).toInt(),
      ankle.top,
      ankle.right,
      ankle.bottom
    )

    // Metallreflexe
    val spec = specularPoints(bmp, ankle)
    // Vertikal-Periodik
    val vertPeriod = verticalPeriodicity(bmp, ankle)
    // Zickzack
    val zig = zigzagEdges(bmp, ankle)
    // Geschlossene Ferse
    val closedHeel = closedHeelContour(bmp, heelBox)

    // Score: gewichtete Summe
    val score = (0.45f*spec + 0.35f*vertPeriod + 0.20f*zig).coerceIn(0f, 1f)
    return Result(score, closedHeel)
  }

  private fun specularPoints(bmp: Bitmap, r: Rect): Float {
    var bright=0; var tot=0
    val step = max(1, min(r.width(), r.height())/96)
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat()
        val mn = min(R, min(G,B)).toFloat()
        val v = mx/255f
        val s = if (mx==0f) 0f else 1f-(mn/mx) // geringe Sättigung = Metallreflex
        if (v>0.78f && s<0.25f) bright++
        tot++
        x+=step
      }
      y+=step
    }
    if (tot==0) return 0f
    return (bright.toFloat()/tot * 4f).coerceAtMost(1f)
  }

  private fun verticalPeriodicity(bmp: Bitmap, r: Rect): Float {
    // einfache vertikale Kantenhäufigkeit in schmalen Spalten
    val cols = 12
    val colW = max(2, r.width()/cols)
    val step = max(1, min(colW, r.height())/64)
    val counts = IntArray(cols)
    for (i in 0 until cols) {
      val x0 = r.left + i*colW
      val x1 = min(r.right-1, x0+colW)
      var cnt=0
      var y=r.top
      while (y<r.bottom-step) {
        var x=x0
        while (x<x1) {
          val c1=bmp.getPixel(x,y)
          val c2=bmp.getPixel(x, y+step)
          val l1=((c1 shr 16 and 0xFF)*299 + (c1 shr 8 and 0xFF)*587 + (c1 and 0xFF)*114)/1000
          val l2=((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
          if (abs(l1-l2)>28) cnt++
          x+=step
        }
        y+=step
      }
      counts[i]=cnt
    }
    // Periodik ~ Varianz über Spalten
    val avg = counts.average().toFloat()
    var varsum=0f; for (c in counts) { val d=c-avg; varsum += d*d }
    val norm = (avg*avg + 1f)
    val score = (varsum / norm).coerceIn(0f, 1f)
    return score
  }

  private fun zigzagEdges(bmp: Bitmap, r: Rect): Float {
    // Anhalt für Schnürung (wechselnde Richtung): Gradientenwechsel entlang Zeilen
    val step = max(1, min(r.width(), r.height())/96)
    var switches=0; var tot=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      var lastSign=0
      while (x<r.right-step) {
        val c1=bmp.getPixel(x,y)
        val c2=bmp.getPixel(x+step,y)
        val l1=((c1 shr 16 and 0xFF)*299 + (c1 shr 8 and 0xFF)*587 + (c1 and 0xFF)*114)/1000
        val l2=((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
        val diff = l2 - l1
        val sign = if (diff>10) 1 else if (diff<-10) -1 else 0
        if (sign!=0 && lastSign!=0 && sign!=lastSign) switches++
        if (sign!=0) lastSign = sign
        tot++; x+=step
      }
      y+=step
    }
    if (tot==0) return 0f
    return (switches.toFloat()/tot * 3f).coerceAtMost(1f)
  }

  private fun closedHeelContour(bmp: Bitmap, r: Rect): Boolean {
    // hinten zusammenhängende dunkle Kontur (Fersenkappe)
    var dark=0; var tot=0
    val step = max(1, min(r.width(), r.height())/96)
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val v = max(R, max(G,B))/255f
        if (v<0.25f) dark++
        tot++; x+=step
      }
      y+=step
    }
    val darkFrac = if (tot==0) 0f else dark.toFloat()/tot
    return darkFrac > 0.18f
  }

  private fun inflate(r: Rect, bmp: Bitmap, f: Float): Rect {
    val dx = (r.width()*f).toInt(); val dy=(r.height()*f).toInt()
    return Rect((r.left-dx).coerceAtLeast(0), (r.top-dy).coerceAtLeast(0),
      (r.right+dx).coerceAtMost(bmp.width), (r.bottom+dy).coerceAtMost(bmp.height))
  }
}
