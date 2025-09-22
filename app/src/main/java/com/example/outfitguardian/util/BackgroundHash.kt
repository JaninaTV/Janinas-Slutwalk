package com.example.outfitguardian.util

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object BackgroundHash {
  private const val PREF="bg_hash"
  private const val KEY_LAST="last"

  fun perceptualHash24(bmp: Bitmap): String {
    val w=bmp.width; val h=(bmp.height*0.35f).toInt() // oberes Drittel als "Hintergrund"
    val r=Rect((w*0.05f).toInt(), (h*0.10f).toInt(), (w*0.95f).toInt(), (h*0.90f).toInt())
    val gx=6; val gy=4
    val cellW=max(1, r.width()/gx); val cellH=max(1, r.height()/gy)
    val arr = IntArray(gx*gy)
    var yy=r.top
    for (j in 0 until gy) {
      var xx=r.left
      for (i in 0 until gx) {
        var sum=0; var cnt=0
        var y=yy
        val yEnd=min(r.bottom, yy+cellH)
        val xEnd=min(r.right, xx+cellW)
        while (y<yEnd) {
          var x=xx
          while (x<xEnd) {
            val c=bmp.getPixel(x,y)
            val l=((c shr 16 and 0xFF)*299 + (c shr 8 and 0xFF)*587 + (c and 0xFF)*114)/1000
            sum+=l; cnt++; x+=2
          }
          y+=2
        }
        arr[j*gx+i] = if (cnt==0) 0 else sum/cnt
        xx += cellW
      }
      yy += cellH
    }
    // binarisieren gg Mittelwert
    val mean = arr.average()
    val bits = arr.map { if (it.toDouble() > mean) '1' else '0' }.joinToString("")
    return bits
  }

  fun tooSimilar(a:String, b:String, maxHamming:Int=4): Boolean {
    val n = min(a.length, b.length)
    var d=0
    for (i in 0 until n) if (a[i]!=b[i]) d++
    d += abs(a.length - b.length)
    return d <= maxHamming
  }

  fun checkAndStore(ctx: Context, hash: String): Boolean {
    val sp = ctx.getSharedPreferences(PREF, 0)
    val last = sp.getString(KEY_LAST, null)
    val ok = last==null || !tooSimilar(hash, last)
    sp.edit().putString(KEY_LAST, hash).apply()
    return ok
  }
}
