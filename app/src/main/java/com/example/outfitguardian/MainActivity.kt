package com.example.outfitguardian

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.outfitguardian.security.SessionGuard
import com.example.outfitguardian.rules.OutfitPreset
import com.example.outfitguardian.rules.OutfitPresetStore
import com.example.outfitguardian.rules.OutfitRequirements
import com.example.outfitguardian.vault.PhotoVault
import com.example.outfitguardian.outfit.OutfitCheckManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream

class MainActivity : ComponentActivity() {

  private var pendingCaptureForRef = false
  private var photoUri: Uri? = null

  private val perms = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
  ) { /* ignore */ }

  private val captureLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
  ) { res ->
    val ok = res.resultCode == Activity.RESULT_OK
    val uri = photoUri
    if (!ok || uri == null) { toast("Foto abgebrochen"); return@registerForActivityResult }

    // Bild temporär in Cachedatei kopieren, damit Heuristiken Pfad lesen können
    val tmpPath = cacheFileFromStream(contentResolver.openInputStream(uri)!!, "cap_${System.currentTimeMillis()}.jpg")

    // Tresor: Original verschlüsselt ablegen
    contentResolver.openInputStream(uri)?.use { reOpen ->
      PhotoVault.addImageEncrypted(this, reOpen, if (pendingCaptureForRef) "ref.jpg" else "check.jpg")
    }

    if (pendingCaptureForRef) {
      OutfitCheckManager.storeReferenceBitmap(this, tmpPath)
      updateRefCount()
      toast("Referenz gespeichert (Zähler aktualisiert).")
    } else {
      val (pass, reasons) = OutfitCheckManager.checkBitmap(this, tmpPath)
      val msg = if (pass) "Outfitcheck OK" else "Abweichung: " + reasons.joinToString("; ")
      findViewById<TextView>(R.id.tvLastCheck).text = "Letzter Outfitcheck: $msg"
    }
  }

  private lateinit var navigator: com.example.outfitguardian.route.SessionNavigator
  private lateinit var routePlan: com.example.outfitguardian.route.RoutePlan
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SessionGuard.enforceFlagSecure(this)
    SessionGuard.keepScreenOn(this, true)
    setContentView(R.layout.activity_main)
    // Route HUD minimal
    val arrow = findViewById<android.widget.ImageView>(com.example.outfitguardian.R.id.ivArrow)
    val prompt = findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvPrompt)
    // Dummy plan init; in deiner echten App: aus Konfiguration/Hotspotliste
    routePlan = com.example.outfitguardian.route.RouteEngine.buildPlan(emptyList(), mutableListOf())
    navigator = com.example.outfitguardian.route.SessionNavigator(this, routePlan)
    // Optional: Heel-Lift-Probe schnell starten
    // startActivity(android.content.Intent(this, HeelLiftProbeActivity::class.java))
    // Preset Buttons
    findViewById<Button>(R.id.btnPresetEnable)?.setOnClickListener {
      if (SessionGuard.isActive(this) || OutfitPresetStore.isFrozen(this)) { toast("Während aktiver Session gesperrt."); return@setOnClickListener }
      val p = OutfitPreset(enabled=true, heelMinCm=10)
      OutfitPresetStore.save(this, p)
      OutfitRequirements.setHeelMinCm(this, p.heelMinCm)
      findViewById<TextView>(R.id.tvPreset)?.text = "Pflichtoutfit: " + p.name
      toast("Pflichtoutfit aktiviert")
    }
    findViewById<Button>(R.id.btnPresetDisable)?.setOnClickListener {
      if (SessionGuard.isActive(this) || OutfitPresetStore.isFrozen(this)) { toast("Während aktiver Session gesperrt."); return@setOnClickListener }
      OutfitPresetStore.save(this, OutfitPreset(enabled=false))
      findViewById<TextView>(R.id.tvPreset)?.text = "Pflichtoutfit: aus"
      toast("Pflichtoutfit deaktiviert")
    }


    ensurePerms()

    val tvSession = findViewById<TextView>(R.id.tvSession)
    fun refreshState() { tvSession.text = "Session: " + if (SessionGuard.isActive(this)) "AKTIV" else "INAKTIV"; updateRefCount() }
    refreshState()

    findViewById<Button>(R.id.btnSetRoute).setOnClickListener {
      if (SessionGuard.isRouteFrozen(this)) { toast("Route/Hotspots sind eingefroren."); return@setOnClickListener }
      val route = JSONArray().put(JSONObject().put("lat", 0.0).put("lng", 0.0))
      val spots = JSONArray().put(JSONObject().put("name","Belebter Platz").put("lat",0.0).put("lng",0.0).put("stayMin",5))
      SessionGuard.freezeRoute(this, route.toString(), spots.toString())
      toast("Route/Hotspots gesetzt. Nach Start eingefroren.")
    }

    findViewById<Button>(R.id.btnRefPhoto).setOnClickListener {
      if (OutfitCheckManager.refCount(this) >= 50) { toast("Max. 50 Referenzen erreicht"); return@setOnClickListener }
      pendingCaptureForRef = true
      launchCamera()
    }

    findViewById<Button>(R.id.btnStartSession).setOnClickListener {
      if (!SessionGuard.isRouteFrozen(this)) { toast("Bitte zuerst Route & Hotspots setzen."); return@setOnClickListener }
      val pin = SessionGuard.generatePin()
      startActivity(Intent(this, NotPinActivity::class.java).putExtra("pin", pin))
      SessionGuard.startSession(this, pin)
      com.example.outfitguardian.rules.OutfitPresetStore.freeze(this)
      startForegroundSession()
      com.example.outfitguardian.session.NotificationGuard.enableInAppQuiet(this)
      com.example.outfitguardian.scheduler.StrictCheckScheduler.start(this)
      com.example.outfitguardian.scheduler.FastenerMacroScheduler.scheduleNext(this)
      refreshState()
    }

    findViewById<Button>(R.id.btnOutfitCheck).setOnClickListener {
      if (!OutfitCheckManager.hasReference(this)) { toast("Mindestens 1 Referenzfoto nötig"); return@setOnClickListener }
      pendingCaptureForRef = false
      launchCamera()
    }

    findViewById<Button>(R.id.btnStopWithPin).setOnClickListener {
      val dlg = android.app.AlertDialog.Builder(this)
      val input = android.widget.EditText(this).apply { isSingleLine = true; hint = "Not-PIN (25 Zeichen)" }
      dlg.setTitle("Session beenden")
        .setMessage("Bitte Not-PIN eingeben.")
        .setView(input)
        .setPositiveButton("Beenden") { d,_ ->
          val ok = SessionGuard.verifyAndStop(this, input.text.toString())
          if (ok) {
            stopForegroundSession()
            toast("Session beendet. Tresor wieder freigegeben.")
          } else toast("PIN falsch.")
          d.dismiss()
        }
        .setNegativeButton("Abbrechen") { d,_ -> d.dismiss() }
        .show()
    }

    findViewById<Button>(R.id.btnStopSessionUnsafe).setOnClickListener {
      toast("Dev-Stop während aktiver Session deaktiviert.")
    }
  }

  private fun ensurePerms() {
    val need = mutableListOf<String>()
    listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.CAMERA)
      .forEach { if (ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED) need += it }
    if (need.isNotEmpty()) perms.launch(need.toTypedArray())
  }

  private fun launchCamera() {
    val cv = ContentValues().apply {
      put(MediaStore.Images.Media.DISPLAY_NAME, "cap_${System.currentTimeMillis()}.jpg")
      put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
    }
    photoUri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv)
    val i = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
      putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
      addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    captureLauncher.launch(i)
  }

  private fun cacheFileFromStream(src: java.io.InputStream, name: String): String {
    val dir = File(cacheDir, "imgs").apply { mkdirs() }
    val f = File(dir, name)
    src.use { input -> f.outputStream().use { input.copyTo(it) } }
    return f.absolutePath
  }

  private fun startForegroundSession()
      com.example.outfitguardian.session.NotificationGuard.enableInAppQuiet(this)
      com.example.outfitguardian.scheduler.StrictCheckScheduler.start(this)
      com.example.outfitguardian.scheduler.FastenerMacroScheduler.scheduleNext(this) {
    ContextCompat.startForegroundService(this, Intent(this, SessionForegroundService::class.java))
  }

  private fun stopForegroundSession() {
    stopService(Intent(this, SessionForegroundService::class.java))
  }

  private fun updateRefCount() {
    findViewById<TextView>(R.id.tvRefCount)?.text = "Referenzen: ${OutfitCheckManager.refCount(this)} / 50"
  }

  private fun toast(s: String) =
    android.widget.Toast.makeText(this, s, android.widget.Toast.LENGTH_SHORT).show()

  override fun onBackPressed() {
    if (SessionGuard.isActive(this)) toast("Session aktiv – beenden nur mit Not-PIN.") else super.onBackPressed()
  }
}


  private fun onNewLocation(loc: Location) {
    // Navigator Kernlogik
    navigator.onLocation(loc)
    val bearing = loc.bearing.toDouble().let { if (it.isNaN()) 0.0 else it }
    val (txt, arrowCode) = navigator.prompt(com.example.outfitguardian.route.LatLng(loc.latitude, loc.longitude), bearing)
    findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvPrompt)?.text = txt
    val iv = findViewById<android.widget.ImageView>(com.example.outfitguardian.R.id.ivArrow)
    when (arrowCode) {
      -1 -> iv?.rotation = -90f
      0 -> iv?.rotation = 0f
      1 -> iv?.rotation = 90f
      else -> iv?.rotation = 180f
    }
  }


  companion object {
    @JvmStatic fun onOutfitCheckPassedBridge() {
      // In einer echten Arch: via EventBus/Navigator-Instanz. Hier Platzhalter.
    }
  }


  private fun updateFailCounter() {
    val tv = findViewById<android.widget.TextView>(com.example.outfitguardian.R.id.tvFailCounter)
    if (tv != null) {
      val fails = com.example.outfitguardian.session.StreakManager.getFails(this)
      val streak = com.example.outfitguardian.session.StreakManager.getStreak(this)
      tv.text = "Fails: %d | Streak: %d".format(fails, streak)
    }
  }
