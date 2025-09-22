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
