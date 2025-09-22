package com.example.outfitguardian.util

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object QualityGate {
  data class Result(val ok:Boolean, val reason:String?)

  fun check(bmp: Bitmap): Result {
    val sharp = laplacianVar(bmp)
    if (sharp < 40.0) return Result(false, "Bild unscharf")
    val v = avgV(bmp)
    if (v < 0.20 || v > 0.95) return Result(false, "Belichtung schlecht")
    return Result(true, null)
  }

  private fun laplacianVar(bmp: Bitmap): Double {
    // sehr simple Varianz der Intensitätsdifferenzen
    var sum=0.0; var sum2=0.0; var n=0.0
    val step = max(1, min(bmp.width, bmp.height)/256)
    var y=0
    while (y<bmp.height-step) {
      var x=0
      while (x<bmp.width-step) {
        val c=bmp.getPixel(x,y)
        val d=bmp.getPixel(x+step,y+step)
        val l1=((c shr 16 and 0xFF)*299 + (c shr 8 and 0xFF)*587 + (c and 0xFF)*114)/1000
        val l2=((d shr 16 and 0xFF)*299 + (d shr 8 and 0xFF)*587 + (d and 0xFF)*114)/1000
        val diff = (l2-l1).toDouble()
        sum += diff; sum2 += diff*diff; n += 1
        x += step
      }
      y += step
    }
    val mean = if (n==0.0) 0.0 else sum/n
    return if (n==0.0) 0.0 else (sum2/n - mean*mean)
  }

  private fun avgV(bmp: Bitmap): Double {
    var sum=0.0; var n=0.0
    val step = max(1, min(bmp.width, bmp.height)/256)
    var y=0
    while (y<bmp.height) {
      var x=0
      while (x<bmp.width) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toDouble()
        sum += mx/255.0; n += 1
        x += step
      }
      y += step
    }
    return if (n==0.0) 0.0 else sum/n
  }
}
