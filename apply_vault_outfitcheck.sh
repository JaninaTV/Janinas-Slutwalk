#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG_DIR="app/src/main/java/${APP_ID//.//}"
RES_DIR="app/src/main/res"

# 1) Gradle: Security-Crypto rein
sed -i.bak '/dependencies\s*{/,/}/ {
  /security-crypto/ d
}' app/build.gradle.kts

awk '
/dependencies\s*\{/ && !seen {
  print; print "  implementation(\"androidx.security:security-crypto:1.1.0-alpha06\")"
  seen=1; next
}
{ print }
' app/build.gradle.kts > app/build.gradle.kts.tmp && mv app/build.gradle.kts.tmp app/build.gradle.kts

# 2) Manifest: FileProvider + NotPin/Service bleiben
cat > app/src/main/AndroidManifest.xml <<MAN
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  <application
    android:allowBackup="true"
    android:label="OutfitGuardian"
    android:theme="@style/Theme.Material3.DayNight.NoActionBar">

    <provider
      android:name="androidx.core.content.FileProvider"
      android:authorities="${APP_ID}.fileprovider"
      android:exported="false"
      android:grantUriPermissions="true">
      <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
    </provider>

    <activity
      android:name=".NotPinActivity"
      android:exported="false"
      android:excludeFromRecents="true"
      android:taskAffinity=""
      android:turnScreenOn="true"
      android:showOnLockScreen="true" />

    <activity
      android:name=".MainActivity"
      android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>

    <service
      android:name=".SessionForegroundService"
      android:exported="false"
      android:foregroundServiceType="location" />
  </application>
</manifest>
MAN

# 3) FileProvider-Pfade
mkdir -p ${RES_DIR}/xml
cat > ${RES_DIR}/xml/file_paths.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
  <cache-path name="imgs" path="imgs/"/>
  <external-files-path name="pics" path="Pictures/"/>
  <files-path name="vault" path="vault/"/>
</paths>
XML

# 4) Layout updaten: Buttons für Referenzen/Outfitcheck + Status
mkdir -p ${RES_DIR}/layout
cat > ${RES_DIR}/layout/activity_main.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
  android:layout_width="match_parent"
  android:layout_height="match_parent">
  <LinearLayout
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="16dp">

    <TextView
      android:id="@+id/tvSession"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Session: INAKTIV" />

    <Button
      android:id="@+id/btnSetRoute"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Route & Hotspots setzen (friert nach Start ein)"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnRefPhoto"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Referenzfoto aufnehmen (bis 50)"
      android:layout_marginTop="8dp"/>

    <TextView
      android:id="@+id/tvRefCount"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Referenzen: 0 / 50"
      android:layout_marginTop="4dp"/>

    <Button
      android:id="@+id/btnStartSession"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Session starten (Not-PIN 3s)"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnOutfitCheck"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Outfitcheck jetzt"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnStopWithPin"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Session mit Not-PIN beenden"
      android:layout_marginTop="8dp"/>

    <TextView
      android:id="@+id/tvLastCheck"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Letzter Outfitcheck: —"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnStopSessionUnsafe"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="(Dev) Session sofort beenden"
      android:layout_marginTop="24dp"/>
  </LinearLayout>
</ScrollView>
XML

# 5) Tresor: verschlüsselte Ablage + Zugangssperre während Session
mkdir -p ${PKG_DIR}/vault
cat > ${PKG_DIR}/vault/PhotoVault.kt <<'KOT'
package com.example.outfitguardian.vault

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import java.io.File
import java.io.InputStream

object PhotoVault {
  private const val VAULT_DIR = "vault"
  private const val META = "vault_meta.properties"

  private fun masterKey(ctx: Context) = MasterKey.Builder(ctx)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()

  private fun dir(ctx: Context): File = File(ctx.filesDir, VAULT_DIR).apply { mkdirs() }

  fun addImageEncrypted(ctx: Context, src: InputStream, filenameHint: String): File {
    val safe = filenameHint.replace(Regex("[^A-Za-z0-9._-]"), "_")
    val out = File(dir(ctx), "${System.currentTimeMillis()}_${safe}.bin")
    val ef = EncryptedFile.Builder(ctx, out, masterKey(ctx), EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB).build()
    ef.openFileOutput().use { dst -> src.copyTo(dst) }
    return out
  }

  /** Tresor-Inhalte sind während aktiver Session NICHT zugänglich. UI darf NICHT rendern. */
  fun listEncrypted(ctx: Context): List<File> = dir(ctx).listFiles()?.toList() ?: emptyList()

  /** Löschen nur zulässig, wenn Session NICHT aktiv (Business-Logik in aufrufender Ebene prüfen). */
  fun deleteAll(ctx: Context) {
    dir(ctx).listFiles()?.forEach { it.delete() }
  }
}
KOT

# 6) Outfit-Features & Vergleich (HSV-Histogramm + Kantenrate)
mkdir -p ${PKG_DIR}/outfit
cat > ${PKG_DIR}/outfit/OutfitFeatures.kt <<'KOT'
package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class FeatureVec(val hueHist: FloatArray, val edgeRate: Float)

object OutfitFeatures {

  fun decode(path: String): Bitmap? =
    BitmapFactory.decodeFile(path)

  fun features(bmp: Bitmap): FeatureVec {
    val w = bmp.width; val h = bmp.height
    val bins = FloatArray(24)
    var edges = 0
    var total = 0

    var y = 0
    while (y < h) {
      var x = 0
      while (x < w) {
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

        // einfache Kante horizontal
        if (x+2 < w) {
          val c2 = bmp.getPixel(x+2, y)
          val r2 = (c2 shr 16) and 0xFF
          val g2 = (c2 shr 8) and 0xFF
          val b2 = c2 and 0xFF
          val l1 = (r*299 + g*587 + b*114)/1000
          val l2 = (r2*299 + g2*587 + b2*114)/1000
          if (abs(l1 - l2) > 28) edges++
        }

        total++
        x += 4
      }
      y += 4
    }
    // Normieren
    val sum = bins.sum().takeIf { it > 0f } ?: 1f
    for (i in bins.indices) bins[i] /= sum
    val edgeRate = edges.toFloat() / total.toFloat().coerceAtLeast(1f)
    return FeatureVec(bins, edgeRate)
  }

  fun cosine(a: FloatArray, b: FloatArray): Float {
    var dot = 0f; var na = 0f; var nb = 0f
    for (i in a.indices) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
    if (na == 0f || nb == 0f) return 0f
    return (dot / kotlin.math.sqrt(na*nb))
  }

  /** einfacher Vergleich: Hue-Ähnlichkeit UND ähnliche Kantenrate */
  fun similar(a: FeatureVec, b: FeatureVec, hueMin: Float = 0.92f, edgeTol: Float = 0.08f): Boolean {
    val hueSim = cosine(a.hueHist, b.hueHist)
    val edgeOk = kotlin.math.abs(a.edgeRate - b.edgeRate) <= edgeTol
    return hueSim >= hueMin && edgeOk
  }
}
KOT

# 7) OutfitCheck-Manager: hält Referenz-Feature-Vektor, vergleicht Checks und steuert Tasker
cat > ${PKG_DIR}/outfit/OutfitCheckManager.kt <<'KOT'
package com.example.outfitguardian.outfit

import android.content.Context
import com.example.outfitguardian.integration.tasker.TaskerEvents

object OutfitCheckManager {
  private const val PREF = "outfit_ref"
  private const val KEY_REF = "ref_vec"    // gespeicherter Feature-Vektor als CSV
  private const val KEY_COUNT = "ref_count"

  private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

  fun refCount(ctx: Context) = prefs(ctx).getInt(KEY_COUNT, 0)

  fun storeReference(ctx: Context, vec: FeatureVec) {
    prefs(ctx).edit()
      .putString(KEY_REF, serialize(vec))
      .putInt(KEY_COUNT, (refCount(ctx) + 1).coerceAtMost(50))
      .apply()
  }

  fun hasReference(ctx: Context) = prefs(ctx).contains(KEY_REF)

  fun checkAgainstReference(ctx: Context, vec: FeatureVec): Boolean {
    val s = prefs(ctx).getString(KEY_REF, null) ?: return false
    val ref = deserialize(s)
    val ok = OutfitFeatures.similar(ref, vec)
    // Tasker-Events: Start/Ende mit "Nachbesserungspflicht"
    if (!ok) {
      TaskerEvents.startViolation(ctx, TaskerEvents.Type.OUTFIT, 45, "Nachbesserungspflicht: Outfit weicht ab")
    } else {
      TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.OUTFIT, "Outfit wieder passend")
    }
    return ok
  }

  private fun serialize(v: FeatureVec): String {
    val h = v.hueHist.joinToString(";")
    return "$h|${v.edgeRate}"
  }
  private fun deserialize(s: String): FeatureVec {
    val parts = s.split("|")
    val hist = parts[0].split(";").map { it.toFloat() }.toFloatArray()
    val edge = parts.getOrNull(1)?.toFloatOrNull() ?: 0f
    return FeatureVec(hist, edge)
  }
}
KOT

# 8) SessionGuard (bereits vorhanden), wir nutzen ihn weiter – keine Änderung

# 9) MainActivity: Kamera-Intent, Tresor speichern, Feature extrahieren, Sperren respektieren
cat > ${PKG_DIR}/MainActivity.kt <<'KOT'
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
import com.example.outfitguardian.rules.OutfitInput
import com.example.outfitguardian.rules.OutfitRules
import com.example.outfitguardian.security.SessionGuard
import com.example.outfitguardian.vault.PhotoVault
import com.example.outfitguardian.outfit.*

import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream

class MainActivity : ComponentActivity() {

  private var pendingCaptureForRef = false
  private var photoUri: Uri? = null

  private val camPerms = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
  ) { /* ignored */ }

  private val captureLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
  ) { res ->
    val ok = res.resultCode == Activity.RESULT_OK
    val uri = photoUri
    if (!ok || uri == null) { toast("Foto abgebrochen"); return@registerForActivityResult }
    contentResolver.openInputStream(uri)?.use { inStream ->
      // 1) Feature extrahieren (vor Tresor)
      val tmpPath = cacheFileFromStream(inStream, "tmp.jpg")
      val bmp = OutfitFeatures.decode(tmpPath)
      if (bmp == null) { toast("Bild konnte nicht gelesen werden"); return@registerForActivityResult }
      val vec = OutfitFeatures.features(bmp)

      // 2) Tresor: Foto verschlüsselt ablegen (kein Zugriff während Session)
      contentResolver.openInputStream(uri)?.use { reOpen ->
        PhotoVault.addImageEncrypted(this, reOpen, if (pendingCaptureForRef) "ref.jpg" else "check.jpg")
      }

      if (pendingCaptureForRef) {
        OutfitCheckManager.storeReference(this, vec)
        updateRefCount()
        toast("Referenz gespeichert (nur Zähler sichtbar).")
      } else {
        val okMatch = OutfitCheckManager.checkAgainstReference(this, vec)
        findViewById<TextView>(R.id.tvLastCheck).text =
          "Letzter Outfitcheck: " + if (okMatch) "OK" else "abweichend (Nachbesserungspflicht)"
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SessionGuard.enforceFlagSecure(this)
    SessionGuard.keepScreenOn(this, true)
    setContentView(R.layout.activity_main)

    ensurePerms()

    val tvSession = findViewById<TextView>(R.id.tvSession)
    fun refreshState() {
      tvSession.text = "Session: " + if (SessionGuard.isActive(this)) "AKTIV" else "INAKTIV"
      updateRefCount()
    }
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
      startForegroundSession()
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
          } else {
            toast("PIN falsch.")
          }
          d.dismiss()
        }
        .setNegativeButton("Abbrechen") { d,_ -> d.dismiss() }
        .show()
    }

    findViewById<Button>(R.id.btnStopSessionUnsafe).setOnClickListener {
      toast("Dev-Stop ist während Session deaktiviert.")
    }
  }

  private fun ensurePerms() {
    val need = mutableListOf<String>()
    listOf(
      Manifest.permission.ACCESS_FINE_LOCATION,
      Manifest.permission.ACCESS_COARSE_LOCATION,
      Manifest.permission.CAMERA
    ).forEach {
      if (ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED)
        need += it
    }
    if (need.isNotEmpty()) camPerms.launch(need.toTypedArray())
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

  private fun cacheFileFromStream(src: InputStream, name: String): String {
    val dir = File(cacheDir, "imgs").apply { mkdirs() }
    val f = File(dir, name)
    src.use { input -> f.outputStream().use { input.copyTo(it) } }
    return f.absolutePath
  }

  private fun updateRefCount() {
    val tv = findViewById<TextView>(R.id.tvRefCount)
    tv?.text = "Referenzen: ${OutfitCheckManager.refCount(this)} / 50"
  }

  private fun startForegroundSession() {
    ContextCompat.startForegroundService(this, Intent(this, SessionForegroundService::class.java))
  }

  private fun stopForegroundSession() {
    stopService(Intent(this, SessionForegroundService::class.java))
  }

  private fun toast(s: String) =
    android.widget.Toast.makeText(this, s, android.widget.Toast.LENGTH_SHORT).show()

  override fun onBackPressed() {
    if (SessionGuard.isActive(this)) {
      toast("Session aktiv – beenden nur mit Not-PIN.")
    } else {
      super.onBackPressed()
    }
  }
}
KOT

# 10) Strings fallback
mkdir -p ${RES_DIR}/values
cat > ${RES_DIR}/values/strings.xml <<STR
<resources>
  <string name="app_name">OutfitGuardian</string>
</resources>
STR

echo "==> Build starten"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
