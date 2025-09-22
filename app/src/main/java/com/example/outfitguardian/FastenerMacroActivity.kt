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
