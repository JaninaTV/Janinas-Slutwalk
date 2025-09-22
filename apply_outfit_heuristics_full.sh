#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"

echo "==> Heuristik-Datei schreiben: OutfitHeuristics.kt"
mkdir -p "$PKG/outfit"
cat > "$PKG/outfit/OutfitHeuristics.kt" <<'KOT'
package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class RegionRects(val shoes: Rect, val socks: Rect, val hemStripe: Rect, val torsoStripe: Rect, val eyes: Rect)

data class RegionFeatures(val hueHist: FloatArray, val edgeRate: Float)
data class FrameFeatures(
    val socks: RegionFeatures,
    val legs: RegionFeatures,
    val shoes: RegionFeatures,
    val hemY: Int,
    val eyeSat: Float,
    val eyesLumaDarkFrac: Float
)

object OutfitHeuristics {

    // Regionen relativ zur Bildhöhe definieren
    fun regions(bmp: Bitmap): RegionRects {
        val w = bmp.width
        val h = bmp.height
        fun r(x0: Int, y0: Int, x1: Int, y1: Int) = Rect(
            x0.coerceIn(0, w-1), y0.coerceIn(0, h-1),
            x1.coerceIn(1, w),   y1.coerceIn(1, h)
        )
        val shoes = r( (w*0.05).toInt(), (h*0.85).toInt(), (w*0.95).toInt(), h )
        val socks = r( (w*0.10).toInt(), (h*0.65).toInt(), (w*0.90).toInt(), (h*0.85).toInt() )
        val hemStripe = r( (w*0.10).toInt(), (h*0.45).toInt(), (w*0.90).toInt(), (h*0.60).toInt() )
        val torso = r( (w*0.10).toInt(), (h*0.55).toInt(), (w*0.90).toInt(), (h*0.70).toInt() )
        val eyes = r( (w*0.30).toInt(), (h*0.15).toInt(), (w*0.70).toInt(), (h*0.30).toInt() )
        return RegionRects(shoes, socks, hemStripe, torso, eyes)
    }

    // HSV-Hist in 24 Bins + Kantenrate (einfach) einer Region
    fun regionFeatures(bmp: Bitmap, rect: Rect): RegionFeatures {
        val bins = FloatArray(24)
        var edges = 0
        var count = 0
        val step = max(1, min(rect.width(), rect.height()) / 128) // subsampling
        var y = rect.top
        while (y < rect.bottom) {
            var x = rect.left
            while (x < rect.right) {
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

                if (x + step < rect.right) {
                    val c2 = bmp.getPixel(x + step, y)
                    val l1 = (r*299 + g*587 + b*114)/1000
                    val r2 = (c2 shr 16) and 0xFF
                    val g2 = (c2 shr 8) and 0xFF
                    val b2 = c2 and 0xFF
                    val l2 = (r2*299 + g2*587 + b2*114)/1000
                    if (abs(l1 - l2) > 28) edges++
                }
                count++
                x += step
            }
            y += step
        }
        val sum = bins.sum().takeIf { it > 0 } ?: 1f
        for (i in bins.indices) bins[i] /= sum
        val edgeRate = edges.toFloat() / count.toFloat().coerceAtLeast(1f)
        return RegionFeatures(bins, edgeRate)
    }

    fun cosine(a: FloatArray, b: FloatArray): Float {
        var dot = 0f; var na = 0f; var nb = 0f
        for (i in a.indices) { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
        if (na == 0f || nb == 0f) return 0f
        return dot / sqrt(na*nb)
    }

    // einfache Schätzung der Saumlinie: stärkste horizontale Kantenakkumulation in der Mitte
    fun estimateHemY(bmp: Bitmap): Int {
        val h = bmp.height; val w = bmp.width
        val yTop = (h*0.35f).toInt(); val yBot = (h*0.70f).toInt()
        var bestY = (h*0.5f).toInt(); var bestScore = -1
        for (y in yTop until yBot step 2) {
            var s = 0
            var x = (w*0.1f).toInt()
            while (x < (w*0.9f).toInt()-2) {
                val c1 = bmp.getPixel(x,y)
                val c2 = bmp.getPixel(x,y+2)
                val l1 = ((c1 shr 16 and 0xFF)*299 + (c1 shr 8 and 0xFF)*587 + (c1 and 0xFF)*114)/1000
                val l2 = ((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
                if (abs(l1 - l2) > 24) s++
                x += 4
            }
            if (s > bestScore) { bestScore = s; bestY = y }
        }
        return bestY
    }

    // Sehr grobe Heuristik: Absatzhöhe über Konturknick im Schuhbereich (nur Seitenpose wirklich gut)
    fun heelLikelyHigh(bmp: Bitmap): Boolean {
        val r = regions(bmp).shoes
        // Edge-Dichte relativ hoch + vertikale Kantenhäufung -> "hoch"
        val f = regionFeatures(bmp, r)
        return f.edgeRate > 0.18f
    }

    // "weiß" Anteil im Sockenfenster
    fun whiteRatioSocks(bmp: Bitmap): Float {
        val r = regions(bmp).socks
        var white = 0; var tot = 0
        val step = max(1, min(r.width(), r.height()) / 128)
        var y = r.top
        while (y < r.bottom) {
            var x = r.left
            while (x < r.right) {
                val c = bmp.getPixel(x,y)
                val r8 = (c shr 16) and 0xFF
                val g8 = (c shr 8) and 0xFF
                val b8 = c and 0xFF
                val mx = max(r8, max(g8, b8)).toFloat()
                val mn = min(r8, min(g8, b8)).toFloat()
                val sat = if (mx == 0f) 0f else 1f - (mn/mx)
                val v = mx/255f
                if (sat < 0.25f && v > 0.85f) white++
                tot++
                x += step
            }
            y += step
        }
        return if (tot == 0) 0f else white.toFloat()/tot.toFloat()
    }

    // Augen-Make-up "deutlich" (dunkler Anteil + Sättigung)
    fun eyeMakeupSignals(bmp: Bitmap): Pair<Float, Float> {
        val r = regions(bmp).eyes
        var dark = 0; var total = 0; var sSum = 0f
        val step = max(1, min(r.width(), r.height())/64)
        var y = r.top
        while (y < r.bottom) {
            var x = r.left
            while (x < r.right) {
                val c = bmp.getPixel(x,y)
                val r8 = (c shr 16) and 0xFF
                val g8 = (c shr 8) and 0xFF
                val b8 = c and 0xFF
                val luma = (r8*299 + g8*587 + b8*114)/1000
                val mx = max(r8, max(g8,b8)).toFloat()
                val mn = min(r8, min(g8,b8)).toFloat()
                val sat = if (mx == 0f) 0f else 1f - (mn/mx)
                if (luma < 70) dark++
                sSum += sat
                total++
                x += step
            }
            y += step
        }
        val darkFrac = if (total==0) 0f else dark.toFloat()/total.toFloat()
        val satAvg = if (total==0) 0f else sSum/total.toFloat()
        return satAvg to darkFrac
    }

    fun frameFeatures(bmp: Bitmap): FrameFeatures {
        val regs = regions(bmp)
        val socksF = regionFeatures(bmp, regs.socks)
        // Beine-Crop: über Socken bis unter Saum
        val legsRect = Rect(regs.socks.left, (bmp.height*0.45f).toInt(), regs.socks.right, regs.socks.bottom)
        val legsF = regionFeatures(bmp, legsRect)
        val shoesF = regionFeatures(bmp, regs.shoes)
        val hemY = estimateHemY(bmp)
        val (eyeSat, eyesDark) = eyeMakeupSignals(bmp)
        return FrameFeatures(socksF, legsF, shoesF, hemY, eyeSat, eyesDark)
    }
}
KOT

echo "==> OutfitCheckManager erweitern: Referenzprofil, Hysterese, Tasker-Signale"
cat > "$PKG/outfit/OutfitCheckManager.kt" <<'KOT'
package com.example.outfitguardian.outfit

import android.content.Context
import android.graphics.BitmapFactory
import com.example.outfitguardian.integration.tasker.TaskerEvents
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.max

data class ReferenceProfile(
    val socks: RegionFeatures,
    val legs: RegionFeatures,
    val shoes: RegionFeatures,
    val hemY: Int,
    val eyeSat: Float,
    val eyesDarkFrac: Float,
    val whiteSockMinRatio: Float = 0.35f,
    val hueMin: Float = 0.92f,
    val edgeTol: Float = 0.10f
)

object OutfitCheckManager {
    private const val PREF = "outfit_ref_v2"
    private const val KEY_REF_JSON = "ref_json"
    private const val KEY_COUNT = "ref_count"
    private const val KEY_FAIL_STREAK = "fail_streak"
    private const val KEY_OPEN_VIOLATION = "open_violation"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun refCount(ctx: Context) = prefs(ctx).getInt(KEY_COUNT, 0)
    fun hasReference(ctx: Context) = prefs(ctx).contains(KEY_REF_JSON)

    // Speichert Referenzprofil aus Bitmap (erste Bilder)
    fun storeReferenceBitmap(ctx: Context, path: String) {
        val bmp = BitmapFactory.decodeFile(path) ?: return
        val ff = OutfitHeuristics.frameFeatures(bmp)
        val prof = ReferenceProfile(
            socks = ff.socks,
            legs = ff.legs,
            shoes = ff.shoes,
            hemY = ff.hemY,
            eyeSat = ff.eyeSat,
            eyesDarkFrac = ff.eyesLumaDarkFrac
        )
        prefs(ctx).edit()
            .putString(KEY_REF_JSON, toJson(prof).toString())
            .putInt(KEY_COUNT, (refCount(ctx) + 1).coerceAtMost(50))
            .apply()
    }

    // Hauptprüfung gegen Referenz, inklusive Hysterese und Tasker-Events
    fun checkBitmap(ctx: Context, path: String): Pair<Boolean, List<String>> {
        val bmp = BitmapFactory.decodeFile(path) ?: return false to listOf("Bild defekt")
        val ref = getRef(ctx) ?: return false to listOf("Keine Referenz")
        val ff = OutfitHeuristics.frameFeatures(bmp)

        val reasons = mutableListOf<String>()
        // 1) Socken weiß genug
        val whiteFrac = OutfitHeuristics.whiteRatioSocks(bmp)
        if (whiteFrac < ref.whiteSockMinRatio) reasons += "Socken nicht weiß genug (${(whiteFrac*100).toInt()}%)"

        // 2) Tights nicht hautfarben (heuristisch: Hue-Ähnlichkeit zu Referenz-Bein muss hoch UND Sättigung über Baseline)
        val hueLegSim = OutfitHeuristics.cosine(ff.legs.hueHist, ref.legs.hueHist)
        if (hueLegSim < ref.hueMin) reasons += "Beinkleid weicht farblich stark ab"
        val edgeLegDelta = abs(ff.legs.edgeRate - ref.legs.edgeRate)
        if (edgeLegDelta > ref.edgeTol) reasons += "Textur Beine abweichend"

        // 3) Heels grob „hoch“
        if (!OutfitHeuristics.heelLikelyHigh(bmp)) reasons += "High Heels nicht eindeutig"

        // 4) Saum nicht länger als erlaubt (+6px Toleranz, monotone Regel: strengster bisher)
        val hemOk = ff.hemY <= ref.hemY + 6
        if (!hemOk) reasons += "Saum länger als Referenz"

        // 5) Augen-Make-up sichtbar (Sättigung und dunkler Anteil nicht deutlich unter Referenz)
        if (ff.eyeSat + 0.05f < ref.eyeSat || ff.eyesDarkFrac + 0.05f < ref.eyesDarkFrac) {
            reasons += "Augen-Make-up schwach"
        }

        // Score (weighed quick check)
        val scoreHue =
            0.25f*OutfitHeuristics.cosine(ff.legs.hueHist, ref.legs.hueHist) +
            0.20f*OutfitHeuristics.cosine(ff.socks.hueHist, ref.socks.hueHist) +
            0.20f*OutfitHeuristics.cosine(ff.shoes.hueHist, ref.shoes.hueHist) +
            0.25f*(if (hemOk) 1f else 0f) +
            0.10f*(if (ff.eyeSat >= ref.eyeSat && ff.eyesLumaDarkFrac >= ref.eyesDarkFrac) 1f else 0f)

        val pass = scoreHue >= 0.90f && reasons.isEmpty()

        handleHysteresisAndTasker(ctx, pass, reasons)

        return pass to reasons
    }

    private fun handleHysteresisAndTasker(ctx: Context, pass: Boolean, reasons: List<String>) {
        val p = prefs(ctx)
        var streak = p.getInt(KEY_FAIL_STREAK, 0)
        var open = p.getString(KEY_OPEN_VIOLATION, null)

        if (pass) {
            // Ende bei erstem Pass
            if (open != null) {
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.OUTFIT, "Outfit wieder passend")
                open = null
            }
            streak = 0
        } else {
            streak += 1
            if (streak >= 2 && open == null) {
                val msg = "Nachbesserungspflicht: " + reasons.joinToString("; ").take(160)
                val id = TaskerEvents.startViolation(ctx, TaskerEvents.Type.OUTFIT, 45, msg)
                open = id
            }
        }

        p.edit().putInt(KEY_FAIL_STREAK, streak).apply()
        if (open == null) p.edit().remove(KEY_OPEN_VIOLATION).apply()
        else p.edit().putString(KEY_OPEN_VIOLATION, open).apply()
    }

    private fun toJson(r: ReferenceProfile): JSONObject {
        fun arr(f: FloatArray) = JSONArray().apply { f.forEach { put(it) } }
        val o = JSONObject()
        o.put("socks_hist", arr(r.socks.hueHist))
        o.put("socks_edge", r.socks.edgeRate)
        o.put("legs_hist", arr(r.legs.hueHist))
        o.put("legs_edge", r.legs.edgeRate)
        o.put("shoes_hist", arr(r.shoes.hueHist))
        o.put("shoes_edge", r.shoes.edgeRate)
        o.put("hemY", r.hemY)
        o.put("eyeSat", r.eyeSat)
        o.put("eyesDark", r.eyesDarkFrac)
        o.put("whiteMin", r.whiteSockMinRatio)
        o.put("hueMin", r.hueMin)
        o.put("edgeTol", r.edgeTol)
        return o
    }

    private fun fromJson(o: JSONObject): ReferenceProfile {
        fun arr(name: String): FloatArray {
            val a = o.getJSONArray(name)
            return FloatArray(a.length()) { i -> a.getDouble(i).toFloat() }
        }
        val socks = RegionFeatures(arr("socks_hist"), o.getDouble("socks_edge").toFloat())
        val legs  = RegionFeatures(arr("legs_hist"),  o.getDouble("legs_edge").toFloat())
        val shoes = RegionFeatures(arr("shoes_hist"), o.getDouble("shoes_edge").toFloat())
        return ReferenceProfile(
            socks = socks,
            legs = legs,
            shoes = shoes,
            hemY = o.getInt("hemY"),
            eyeSat = o.getDouble("eyeSat").toFloat(),
            eyesDarkFrac = o.getDouble("eyesDark").toFloat(),
            whiteSockMinRatio = o.getDouble("whiteMin").toFloat(),
            hueMin = o.getDouble("hueMin").toFloat(),
            edgeTol = o.getDouble("edgeTol").toFloat()
        )
    }

    private fun getRef(ctx: Context): ReferenceProfile? {
        val s = prefs(ctx).getString(KEY_REF_JSON, null) ?: return null
        return fromJson(JSONObject(s))
    }
}
KOT

echo "==> MainActivity an neue API anpassen (Referenz & Check mit Bitmap-Pfaden)"
# Wir ersetzen MainActivity mit einer Version, die:
# - Referenzspeicherung via OutfitCheckManager.storeReferenceBitmap()
# - Check via OutfitCheckManager.checkBitmap()
# - Tresor bleibt unverändert
cat > "$PKG/MainActivity.kt" <<'KOT'
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

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SessionGuard.enforceFlagSecure(this)
    SessionGuard.keepScreenOn(this, true)
    setContentView(R.layout.activity_main)

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

  private fun startForegroundSession() {
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
KOT

echo "==> Build starten"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
