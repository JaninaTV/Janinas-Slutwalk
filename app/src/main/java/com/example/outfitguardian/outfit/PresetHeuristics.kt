package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object PresetHeuristics {

  // Minirock Tartan rot: grob Rotdominanz + Gitternetz-Kanten
  fun isTartanRed(bmp: Bitmap): Boolean {
    val r = OutfitHeuristics.regions(bmp).hemStripe
    val step = max(1, min(r.width(), r.height())/128)
    var reds=0; var tot=0; var grid=0
    var y=r.top
    while (y<r.bottom-step) {
      var x=r.left
      while (x<r.right-step) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        if (R>G+15 && R>B+15) reds++
        val c2=bmp.getPixel(x+step,y)
        val c3=bmp.getPixel(x,y+step)
        val l = (R*299 + G*587 + B*114)/1000
        val l2=((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
        val l3=((c3 shr 16 and 0xFF)*299 + (c3 shr 8 and 0xFF)*587 + (c3 and 0xFF)*114)/1000
        if (abs(l-l2)>28) grid++
        if (abs(l-l3)>28) grid++
        tot++; x+=step
      }
      y+=step
    }
    val redFrac = if (tot==0) 0f else reds.toFloat()/tot
    val gridRate = if (tot==0) 0f else grid.toFloat()/(tot*2)
    return redFrac>0.25f && gridRate>0.12f
  }

  // Schwarze glänzende Strumpfhose 40–80 den: sehr dunkle V mit spekularen Spots
  fun isBlackGlossyTights(bmp: Bitmap): Boolean {
    val regs = OutfitHeuristics.regions(bmp)
    val legs = Rect(regs.socks.left, (bmp.height*0.50f).toInt(), regs.socks.right, regs.socks.bottom)
    var dark=0; var bright=0; var tot=0
    val step = max(1, min(legs.width(), legs.height())/128)
    var y=legs.top
    while (y<legs.bottom) {
      var x=legs.left
      while (x<legs.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R,min(G,B)).toFloat()
        val v = mx/255f; val s = if (mx==0f) 0f else 1f-(mn/mx)
        if (v<0.22f) dark++              // sehr dunkel
        if (v>0.55f && s<0.25f) bright++ // glänzende Spots
        tot++; x+=step
      }
      y+=step
    }
    val darkFrac = if (tot==0) 0f else dark.toFloat()/tot
    val specFrac = if (tot==0) 0f else bright.toFloat()/tot
    return darkFrac>0.55f && specFrac>0.02f
  }

  // Weiße Kniestrümpfe / Rüschensocken
  fun whiteSocks(bmp: Bitmap): Boolean {
    return OutfitHeuristics.whiteRatioSocks(bmp) >= 0.35f
  }

  // Schwarze Patent-Pumps (Lack) ohne Plateau, Höhe >= Pflicht (separat geprüft)
  fun blackPatentPumps(bmp: Bitmap): Boolean {
    val r = OutfitHeuristics.regions(bmp).shoes
    val f = OutfitHeuristics.regionFeatures(bmp, r)
    // "schwarz" = niedrige V im Median; "Patent" = hohe edgeRate + helle Reflexpunkte
    val step = max(1, min(r.width(), r.height())/96)
    var tot=0; var bright=0; var veryDark=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R, min(G,B)).toFloat()
        val v = mx/255f; val s = if (mx==0f) 0f else 1f - (mn/mx)
        if (v<0.20f) veryDark++
        if (v>0.70f && s<0.20f) bright++
        tot++; x+=step
      }
      y+=step
    }
    val darkFrac = if (tot==0) 0f else veryDark.toFloat()/tot
    val specFrac = if (tot==0) 0f else bright.toFloat()/tot
    return darkFrac>0.20f && specFrac>0.02f && f.edgeRate>0.17f
  }

  // Hoodie/Oberteil in erlaubten Farben (weiß/rot/schwarz)
  fun topAllowedColor(bmp: Bitmap, allowed:Set<String>): Boolean {
    val r = OutfitHeuristics.regions(bmp).torsoStripe
    val step = max(1, min(r.width(), r.height())/128)
    var white=0; var red=0; var black=0; var tot=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R, min(G,B)).toFloat()
        val v=mx/255f; val s= if (mx==0f) 0f else 1f-(mn/mx)
        if (v>0.85f && s<0.25f) white++
        if (R>G+15 && R>B+15) red++
        if (v<0.25f) black++
        tot++; x+=step
      }
      y+=step
    }
    val best = listOf("white" to white, "red" to red, "black" to black).maxBy { it.second }.first
    return allowed.contains(best)
  }

  // Pigtails: grob zwei dunkle Haar-Massen links/rechts oben
  fun pigtailsLikely(bmp: Bitmap): Boolean {
    val w=bmp.width; val h=bmp.height
    val topBand = Rect((w*0.05f).toInt(), (h*0.05f).toInt(), (w*0.95f).toInt(), (h*0.30f).toInt())
    val midX = w/2
    var leftDark=0; var rightDark=0; var totL=0; var totR=0
    val step = max(1, min(topBand.width(), topBand.height())/128)
    var y=topBand.top
    while (y<topBand.bottom) {
      var x=topBand.left
      while (x<topBand.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val v = max(R, max(G,B))/255f
        if (x<midX) { totL++; if (v<0.25f) leftDark++ } else { totR++; if (v<0.25f) rightDark++ }
        x+=step
      }
      y+=step
    }
    val l = if (totL==0) 0f else leftDark.toFloat()/totL
    val r = if (totR==0) 0f else rightDark.toFloat()/totR
    return l>0.25f && r>0.25f
  }

  // Lippen rot + Augen dunkel
  fun lipsRedAndEyesDark(bmp: Bitmap): Boolean {
    val w=bmp.width; val h=bmp.height
    val mouth = Rect((w*0.40f).toInt(), (h*0.35f).toInt(), (w*0.60f).toInt(), (h*0.45f).toInt())
    val eyes = OutfitHeuristics.regions(bmp).eyes
    // Lippen rot
    var redPix=0; var totM=0
    val stepM = max(1, min(mouth.width(), mouth.height())/48)
    var y=mouth.top
    while (y<mouth.bottom) {
      var x=mouth.left
      while (x<mouth.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        if (R>G+25 && R>B+25) redPix++
        totM++; x+=stepM
      }
      y+=stepM
    }
    val lipOk = totM>0 && redPix.toFloat()/totM > 0.12f
    // Augen dunkel: reuse Heuristic
    val pair = OutfitHeuristics.eyeMakeupSignals(bmp)
    val eyesDarkOK = pair.second > 0.15f
    return lipOk && eyesDarkOK
  }
}
