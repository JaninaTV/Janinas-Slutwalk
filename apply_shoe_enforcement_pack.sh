#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"
RES="app/src/main/res"

echo "==> FastenerDetector: Schnalle/Spange/Fessel/Schnürung erkennen"
mkdir -p "$PKG/outfit"
cat > "$PKG/outfit/FastenerDetector.kt" <<'KOT'
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
KOT

echo "==> PlateauCheck: Plateau = Vorderfußhöhe >= 35% der Fersenhöhe"
cat > "$PKG/outfit/PlateauCheck.kt" <<'KOT'
package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

object PlateauCheck {
  /**
   * Nutzt HeelEstimator-Geometrie: Bodenlinie, Fersenpeak, Vorderfußhöhe.
   * Plateau wenn frontHeight >= 0.35 * heelHeight.
   */
  fun isPlateau(bmp: Bitmap): Boolean {
    val regs = OutfitHeuristics.regions(bmp)
    val shoesR = regs.shoes
    val h = bmp.height
    // Bodenlinie grob: unterstes 10%-Band maximale Kanten
    val groundY = OutfitHeuristics.estimateGroundLineY(bmp, shoesR)
    val heelPeakY = OutfitHeuristics.estimateHeelPeakY(bmp, shoesR, groundY)
    val toeY = OutfitHeuristics.estimateToeTopY(bmp, shoesR, groundY)
    val heelHeight = (groundY - heelPeakY).coerceAtLeast(0)
    val frontHeight = (groundY - toeY).coerceAtLeast(0)
    if (heelHeight <= 0) return false
    return frontHeight.toFloat() / heelHeight.toFloat() >= 0.35f
  }
}
KOT

echo "==> BackgroundHash & QualityGate: Anti-Repeat + Schärfe/Helligkeit"
mkdir -p "$PKG/util"
cat > "$PKG/util/BackgroundHash.kt" <<'KOT'
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
KOT

cat > "$PKG/util/QualityGate.kt" <<'KOT'
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
KOT

echo "==> HeelLiftProbeActivity: 5s Flow-Test (Ferse anheben ohne Schlupf)"
# Manifest-Eintrag
python3 - <<PY
from pathlib import Path
mf = Path("app/src/main/AndroidManifest.xml").read_text()
if ".HeelLiftProbeActivity" not in mf:
  ins = '''
    <activity
      android:name=".HeelLiftProbeActivity"
      android:exported="false"
      android:showOnLockScreen="true"
      android:turnScreenOn="true"
      android:excludeFromRecents="true"
      android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />'''
  Path("app/src/main/AndroidManifest.xml").write_text(mf.replace("</application>", ins + "\n  </application>"))
print("Manifest patched")
PY

mkdir -p "$RES/layout"
cat > "$RES/layout/activity_heel_lift_probe.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="match_parent"
  android:keepScreenOn="true">
  <androidx.camera.view.PreviewView
    android:id="@+id/previewView"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
  <TextView
    android:id="@+id/tvInfo"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Heel-Lift-Probe: Ferse 5s leicht anheben, Zehen bleiben am Boden."
    android:padding="16dp"
    android:textColor="#FFFFFF"
    android:textStyle="bold"
    android:background="#66000000"/>
  <TextView
    android:id="@+id/tvCountdown"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:layout_gravity="center"
    android:text="5"
    android:textStyle="bold"
    android:textColor="#FFFFFF"
    android:textSize="64sp"/>
</FrameLayout>
XML

cat > "$PKG/HeelLiftProbeActivity.kt" <<'KOT'
package com.example.outfitguardian

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.CountDownTimer
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.example.outfitguardian.integration.tasker.TaskerEvents
import com.example.outfitguardian.outfit.OutfitHeuristics
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class HeelLiftProbeActivity: ComponentActivity() {

  private lateinit var preview: PreviewView
  private lateinit var tvInfo: TextView
  private lateinit var tvCountdown: TextView
  private var analyzing = false
  private var flowHeel = 0.0
  private var flowInstep = 0.0

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_heel_lift_probe)
    preview = findViewById(R.id.previewView)
    tvInfo = findViewById(R.id.tvInfo)
    tvCountdown = findViewById(R.id.tvCountdown)

    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
      finish(); return
    }
    startAnalysis()
  }

  private fun startAnalysis() {
    val fut = ProcessCameraProvider.getInstance(this)
    fut.addListener({
      val provider = fut.get()
      val selector = CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_FRONT).build()
      val prev = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
      val ana = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
      ana.setAnalyzer(Executors.newSingleThreadExecutor()) { img ->
        if (!analyzing) { img.close(); return@setAnalyzer }
        val bmp = OutfitHeuristics.yuvToSmallBitmap(img, 320, 240)
        img.close()
        if (bmp != null) {
          val regs = OutfitHeuristics.regions(bmp)
          val heel = regs.shoes
          val instep = android.graphics.Rect(heel.left, max(0, heel.top - heel.height()/2), heel.right, heel.top)
          flowHeel += frameDiff(bmp, heel)
          flowInstep += frameDiff(bmp, instep)
        }
      }
      provider.unbindAll()
      provider.bindToLifecycle(this, selector, prev, ana)
      analyzing = true
      object: CountDownTimer(5000, 1000) {
        override fun onTick(ms: Long) { tvCountdown.text = ((ms/1000)+1).toString() }
        override fun onFinish() { evaluating() }
      }.start()
    }, ContextCompat.getMainExecutor(this))
  }

  private var lastBuf: IntArray? = null
  private fun frameDiff(bmp: android.graphics.Bitmap, r: android.graphics.Rect): Double {
    val step = max(1, min(r.width(), r.height())/64)
    var sum=0.0; var n=0.0
    val cur = IntArray(((r.width()/step)+1)*((r.height()/step)+1))
    var idx=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        cur[idx++] = bmp.getPixel(x,y)
        x+=step
        n+=1
      }
      y+=step
    }
    val last = lastBuf
    var diff=0.0
    if (last!=null && last.size==cur.size) {
      for (i in cur.indices) {
        val c1=cur[i]; val c2=last[i]
        val l1=((c1 shr 16 and 0xFF)*299 + (c1 shr 8 and 0xFF)*587 + (c1 and 0xFF)*114)/1000
        val l2=((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
        diff += abs(l1 - l2)
      }
    }
    lastBuf = cur
    return if (n==0.0) 0.0 else diff/n
  }

  private fun evaluating() {
    analyzing = false
    // Schlupf-Indiz: Heel-Flow >> Instep-Flow (Ferse bewegt sich relativ stark, Rist nicht)
    val ratio = if (flowInstep==0.0) 999.0 else flowHeel/flowInstep
    if (ratio > 2.2) {
      TaskerEvents.startViolation(this, TaskerEvents.Type.OUTFIT, 60, "Heel-Lift-Probe: Schlupfverdacht")
    } else {
      TaskerEvents.endViolation(this, "auto", TaskerEvents.Type.OUTFIT, "Heel-Lift-Probe ok")
    }
    finish()
  }
}
KOT

echo "==> FastenerMacroScheduler: zufällige Makro-Checks (30–45 min)"
mkdir -p "$PKG/scheduler"
cat > "$PKG/scheduler/FastenerMacroScheduler.kt" <<'KOT'
package com.example.outfitguardian.scheduler

import android.content.Context
import android.content.Intent
import androidx.work.*
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import com.example.outfitguardian.FastenerMacroActivity

object FastenerMacroScheduler {
  private const val TAG="fastener_macro"

  fun scheduleNext(ctx: Context) {
    val delay = Random.nextInt(30, 46).toLong()
    val req = OneTimeWorkRequestBuilder<MacroWorker>()
      .setInitialDelay(delay, TimeUnit.MINUTES)
      .addTag(TAG).build()
    WorkManager.getInstance(ctx).enqueueUniqueWork(TAG, ExistingWorkPolicy.REPLACE, req)
  }

  fun cancel(ctx: Context) { WorkManager.getInstance(ctx).cancelUniqueWork(TAG) }

  class MacroWorker(ctx: Context, params: WorkerParameters): CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
      val i = Intent(applicationContext, FastenerMacroActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      applicationContext.startActivity(i)
      scheduleNext(applicationContext)
      return Result.success()
    }
  }
}
KOT

echo "==> FastenerMacroActivity: Nahaufnahme-Vorgabe mit QualityGate + BackgroundAntiRepeat"
cat > "$RES/layout/activity_fastener_macro.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="match_parent"
  android:keepScreenOn="true">
  <androidx.camera.view.PreviewView
    android:id="@+id/previewView"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
  <TextView
    android:id="@+id/tvHint"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:text="Makro: Schnalle/Spange/Schnürung im Rahmen zeigen. Foto erfolgt automatisch."
    android:textStyle="bold"
    android:textColor="#FFFFFF"
    android:padding="16dp"
    android:background="#66000000"/>
</FrameLayout>
XML

python3 - <<PY
from pathlib import Path
mf = Path("app/src/main/AndroidManifest.xml").read_text()
if ".FastenerMacroActivity" not in mf:
  ins = '''
    <activity
      android:name=".FastenerMacroActivity"
      android:exported="false"
      android:showOnLockScreen="true"
      android:turnScreenOn="true"
      android:excludeFromRecents="true"
      android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen" />'''
  Path("app/src/main/AndroidManifest.xml").write_text(mf.replace("</application>", ins + "\n  </application>"))
print("Manifest patched (macro)")
PY

cat > "$PKG/FastenerMacroActivity.kt" <<'KOT'
package com.example.outfitguardian

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.example.outfitguardian.integration.tasker.TaskerEvents
import com.example.outfitguardian.outfit.FastenerDetector
import com.example.outfitguardian.util.BackgroundHash
import com.example.outfitguardian.util.QualityGate
import com.example.outfitguardian.vault.PhotoVault
import java.io.File
import java.util.concurrent.Executors

class FastenerMacroActivity: ComponentActivity() {

  private lateinit var preview: PreviewView
  private lateinit var tvHint: TextView
  private var imageCapture: ImageCapture? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_fastener_macro)
    preview = findViewById(R.id.previewView)
    tvHint = findViewById(R.id.tvHint)

    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
      finish(); return
    }
    startCamera()
  }

  private fun startCamera() {
    val fut = ProcessCameraProvider.getInstance(this)
    fut.addListener({
      val provider = fut.get()
      val selector = CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_FRONT).build()
      val prev = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
      imageCapture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
      provider.unbindAll()
      provider.bindToLifecycle(this, selector, prev, imageCapture)
      capture()
    }, ContextCompat.getMainExecutor(this))
  }

  private fun capture() {
    val tmp = File(cacheDir, "macro_${System.currentTimeMillis()}.jpg")
    val out = ImageCapture.OutputFileOptions.Builder(tmp).build()
    imageCapture?.takePicture(out, Executors.newSingleThreadExecutor(), object: ImageCapture.OnImageSavedCallback {
      override fun onError(exc: ImageCaptureException) { finish() }
      override fun onImageSaved(res: ImageCapture.OutputFileResults) {
        runOnUiThread {
          val bmp = android.graphics.BitmapFactory.decodeFile(tmp.absolutePath)
          if (bmp==null) { finish(); return@runOnUiThread }
          // Quality + Background Anti-Repeat
          val q = QualityGate.check(bmp)
          if (!q.ok) {
            TaskerEvents.startViolation(this@FastenerMacroActivity, TaskerEvents.Type.OUTFIT, 45, "Makro-Check unbrauchbar: ${q.reason}")
            finish(); return@runOnUiThread
          }
          val okBg = BackgroundHash.checkAndStore(this@FastenerMacroActivity, BackgroundHash.perceptualHash24(bmp))
          if (!okBg) {
            TaskerEvents.startViolation(this@FastenerMacroActivity, TaskerEvents.Type.OUTFIT, 40, "Gleicher Hintergrund wiederverwendet")
            finish(); return@runOnUiThread
          }
          // Fastener-Score
          val res = FastenerDetector.analyze(bmp)
          PhotoVault.addImageEncrypted(this@FastenerMacroActivity, tmp.inputStream(), "macro_fastener.jpg")
          if (res.score < 0.40f || !res.closedHeelLikely) {
            TaskerEvents.startViolation(this@FastenerMacroActivity, TaskerEvents.Type.OUTFIT, 60, "Fastener fehlt/nicht sichtbar oder Ferse offen")
          } else {
            TaskerEvents.endViolation(this@FastenerMacroActivity, "auto", TaskerEvents.Type.OUTFIT, "Fastener-Makro ok")
          }
          finish()
        }
      }
    })
  }
}
KOT

echo "==> Preset-Regeln erweitern (G): minFastenerScore, closedHeel, forbidSlipOns"
python3 - "$PKG/rules/OutfitPreset.kt" <<'PY'
import sys, pathlib, re, json
p=pathlib.Path(sys.argv[1])
s=p.read_text()
if "minFastenerScore" not in s:
  s = s.replace("data class OutfitPreset(", "data class OutfitPreset(\n  val enabled: Boolean = false,\n  val name: String = \"Tartan-Set\",\n  val heelMinCm: Int = 10,\n  val colorsTopAllowed: Set<String> = setOf(\"white\",\"red\",\"black\"),\n  val colorsOuterAllowed: Set<String> = setOf(\"white\",\"red\",\"black\"),\n  val minFastenerScore: Float = 0.40f,\n  val requireClosedHeelCounter: Boolean = true,\n  val forbidSlipOns: Boolean = true\n)")
  s = s.replace('o.put("colorsOuter", preset.colorsOuterAllowed.joinToString(","))',
                'o.put("colorsOuter", preset.colorsOuterAllowed.joinToString(","))\n      .put("minFastenerScore", preset.minFastenerScore)\n      .put("requireClosedHeelCounter", preset.requireClosedHeelCounter)\n      .put("forbidSlipOns", preset.forbidSlipOns)')
  s = s.replace("return OutfitPreset(", """return OutfitPreset(
      enabled = o.optBoolean("enabled", false),
      name = o.optString("name","Tartan-Set"),
      heelMinCm = o.optInt("heelMinCm", 10),
      colorsTopAllowed = o.optString("colorsTop","white,red,black").split(",").map{it.trim()}.toSet(),
      colorsOuterAllowed = o.optString("colorsOuter","white,red,black").split(",").map{it.trim()}.toSet(),
      minFastenerScore = o.optDouble("minFastenerScore", 0.40).toFloat(),
      requireClosedHeelCounter = o.optBoolean("requireClosedHeelCounter", true),
      forbidSlipOns = o.optBoolean("forbidSlipOns", true)
    )""")
p.write_text(s); print("OutfitPreset.kt patched")
PY

echo "==> DualOutfitCheckManager: Plateau = harter Fail, Fastener-Score, SlipOns verbieten"
python3 - "$PKG/outfit/DualOutfitCheckManager.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
if "FastenerDetector" not in s:
  s = s.replace("import com.example.outfitguardian.outfit.OutfitHeuristics",
                "import com.example.outfitguardian.outfit.OutfitHeuristics\nimport com.example.outfitguardian.outfit.PlateauCheck\nimport com.example.outfitguardian.outfit.FastenerDetector\nimport com.example.outfitguardian.rules.OutfitPresetStore")
# nach heelsOk / reasons… Plateau + Fastener einziehen
s = s.replace('val pass = reasons.isEmpty()',
r'''// Keine Plateau-Toleranz
    if (bmpSide!=null && PlateauCheck.isPlateau(bmpSide)) {
        reasons += "Plateau erkannt (verboten)"
    }
    // Fastener-Pflicht
    OutfitPresetStore.load(ctx)?.let { preset ->
        if (preset.enabled) {
            if (bmpSide!=null) {
                val fast = FastenerDetector.analyze(bmpSide)
                if (fast.score < preset.minFastenerScore) reasons += "Fastener unzureichend sichtbar"
                if (preset.requireClosedHeelCounter && !fast.closedHeelLikely) reasons += "Fersenkappe offen (verboten)"
                if (preset.forbidSlipOns && fast.score < 0.20f && heelsOk) reasons += "Schlupfschuh-Verdacht"
            }
        }
    }
    val pass = reasons.isEmpty()''')
p.write_text(s); print("DualOutfitCheckManager patched")
PY

echo "==> OutfitCheckManager: QualityGate + BackgroundAntiRepeat vor Bewertung"
python3 - "$PKG/outfit/OutfitCheckManager.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
if "QualityGate" not in s:
  s = s.replace("import com.example.outfitguardian.integration.tasker.TaskerEvents",
                "import com.example.outfitguardian.integration.tasker.TaskerEvents\nimport com.example.outfitguardian.util.QualityGate\nimport com.example.outfitguardian.util.BackgroundHash")
if "QualityGate.check" not in s:
  s = s.replace('val bmp = android.graphics.BitmapFactory.decodeFile(path) ?: return false to listOf("Bild ungültig")',
                'val bmp = android.graphics.BitmapFactory.decodeFile(path) ?: return false to listOf("Bild ungültig")\n        QualityGate.check(bmp).let { if (!it.ok) return false to listOf(it.reason ?: "Bildqualität ungenügend") }\n        val bgOk = BackgroundHash.checkAndStore(ctx, BackgroundHash.perceptualHash24(bmp))\n        if (!bgOk) return false to listOf("Hintergrund wiederverwendet")')
p.write_text(s); print("OutfitCheckManager patched")
PY

echo "==> MainActivity: Buttons/Flows für Heel-Lift-Probe & Fastener-Makro (optional starten)"
python3 - "$PKG/MainActivity.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
if "HeelLiftProbeActivity" not in s:
  s = s.replace("setContentView(R.layout.activity_main)",
                "setContentView(R.layout.activity_main)\n    // Optional: Heel-Lift-Probe schnell starten\n    // startActivity(android.content.Intent(this, HeelLiftProbeActivity::class.java))")
# FastenerMacroScheduler bei Sessionstart anhängen
if "FastenerMacroScheduler" not in s:
  s = s.replace("startForegroundSession()",
                "startForegroundSession()\n      com.example.outfitguardian.scheduler.FastenerMacroScheduler.scheduleNext(this)")
  s = s.replace("stopForegroundSession();",
                "stopForegroundSession(); com.example.outfitguardian.scheduler.FastenerMacroScheduler.cancel(this);")
p.write_text(s); print("MainActivity patched for schedulers")
PY

echo "==> Build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
