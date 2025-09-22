package com.example.outfitguardian

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.example.outfitguardian.outfit.OutfitCheckManager
import com.example.outfitguardian.outfit.OutfitHeuristics
import com.example.outfitguardian.integration.tasker.TaskerEvents
import com.example.outfitguardian.vault.PhotoVault
import java.io.File
import java.util.concurrent.Executors

class AutoCameraActivity : ComponentActivity() {

  private lateinit var preview: PreviewView
  private lateinit var tvHint: TextView
  private var imageCapture: ImageCapture? = null
  private val camExecutor = Executors.newSingleThreadExecutor()
  private var frontPath: String? = null
  private var sidePath: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_autocamera)
    preview = findViewById(R.id.previewView)
    tvHint = findViewById(R.id.tvHint)
    tvHint.text = "Frontalfoto – bitte frontal hinstellen"

    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
      finish(); return
    }
    startCameraThenCapture()
  }

  private fun startCameraThenCapture() {
    val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
    cameraProviderFuture.addListener({
      val cameraProvider = cameraProviderFuture.get()
      val selector = CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_FRONT).build()
      val previewUse = Preview.Builder().build().also { it.setSurfaceProvider(preview.surfaceProvider) }
      imageCapture = ImageCapture.Builder()
        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
        .build()
      cameraProvider.unbindAll()
      cameraProvider.bindToLifecycle(this, selector, previewUse, imageCapture)
      // Frontbild sofort
      captureToCache { path ->
        frontPath = path
        PhotoVault.addImageEncrypted(this, File(path).inputStream(), "front_auto.jpg")
        tvHint.text = "Seitenprofil – bitte seitlich drehen (Foto in 5s). Pumps sichtbar, Socken weiß, Saum frei."
        // 5 Sekunden warten, dann Seitenprofil
        Handler(Looper.getMainLooper()).postDelayed({
          captureToCache { side ->
            sidePath = side
            PhotoVault.addImageEncrypted(this, File(side).inputStream(), "side_auto.jpg")
            analyzeAndFinish()
          }
        }, 5000)
      }
    }, ContextCompat.getMainExecutor(this))
  }

  private fun captureToCache(onSaved:(String)->Unit) {
    val tmp = File(cacheDir, "auto_${System.currentTimeMillis()}.jpg")
    val out = ImageCapture.OutputFileOptions.Builder(tmp).build()
    imageCapture?.takePicture(out, camExecutor, object: ImageCapture.OnImageSavedCallback {
      override fun onError(exc: ImageCaptureException) {
        runOnUiThread { finish() }
      }
      override fun onImageSaved(res: ImageCapture.OutputFileResults) {
        runOnUiThread { onSaved(tmp.absolutePath) }
      }
    })
  }

  private fun analyzeAndFinish() {
    val f = frontPath
    val s = sidePath
    if (f == null || s == null) { finish(); return }
    val (passFront, reasonsFront) = OutfitCheckManager.checkBitmap(this, f)

    val bmpSide = android.graphics.BitmapFactory.decodeFile(s)
    var heelsOk = false
    if (bmpSide != null) {
      val shoesFeat = OutfitHeuristics.regionFeatures(bmpSide, OutfitHeuristics.regions(bmpSide).shoes)
      heelsOk = shoesFeat.edgeRate > 0.18f
    }
    val reasons = mutableListOf<String>()
    if (!passFront) reasons += reasonsFront
    if (!heelsOk) reasons += "Absatzhöhe <8cm oder nicht eindeutig"

    if (reasons.isEmpty()) {
      TaskerEvents.endViolation(this, "auto", TaskerEvents.Type.OUTFIT, "Outfitcheck ok (Front+Seite)")
    } else {
      val msg = "Nachbesserungspflicht: " + reasons.joinToString("; ").take(160)
      TaskerEvents.startViolation(this, TaskerEvents.Type.OUTFIT, 55, msg)
    }
    finish()
  }
}
