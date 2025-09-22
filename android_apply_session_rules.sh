#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"

jpath() { echo "app/src/main/java/${APP_ID//.//}/$1"; }
rpath() { echo "app/src/main/res/$1"; }

echo "==> Layout anpassen (Buttons für Referenzfoto & Route/Hotspots setzen)"
mkdir -p "$(rpath layout)"
cat > "$(rpath layout)/activity_main.xml" <<'XML'
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
      android:text="1. Referenzfoto aufnehmen"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnStartSession"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Session starten (Not-PIN anzeigen)"
      android:layout_marginTop="8dp"/>

    <Button
      android:id="@+id/btnStopWithPin"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Session mit Not-PIN beenden"
      android:layout_marginTop="8dp"/>

    <View
      android:layout_width="match_parent"
      android:layout_height="1dp"
      android:background="#DDD"
      android:layout_marginTop="16dp"
      android:layout_marginBottom="16dp" />

    <TextView
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Outfit-Regeln (Demo-Prüfer):"/>

    <Button
      android:id="@+id/btnCheckOutfit"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:text="Outfit prüfen (regulativ, kein Foto erforderlich)"
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

echo "==> Manifest um Service & PIN-Activity ergänzen"
cat > app/src/main/AndroidManifest.xml <<MAN
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

  <application
    android:allowBackup="true"
    android:label="OutfitGuardian"
    android:theme="@style/Theme.Material3.DayNight.NoActionBar">

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

echo "==> SessionGuard (Not-PIN, Freeze, Screenshot-Sperre, Kiosk-Mode-Fallback)"
mkdir -p "$(jpath security)"
cat > "$(jpath security)/SessionGuard.kt" <<'KOT'
package com.example.outfitguardian.security

import android.app.Activity
import android.content.Context
import android.os.CountDownTimer
import android.view.WindowManager
import java.security.SecureRandom

object SessionGuard {
  private const val PREF = "session_guard"
  private const val KEY_PIN_HASH = "pin_hash"
  private const val KEY_ACTIVE = "active"
  private const val KEY_ROUTE_FROZEN = "route_frozen"
  private const val KEY_PIN_SHOWN = "pin_shown"   // verhindert erneute Anzeige
  private const val KEY_ROUTE_JSON = "route"
  private const val KEY_SPOTS_JSON = "hotspots"

  private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

  fun generatePin(): String {
    val chars = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
      "abcdefghijklmnopqrstuvwxyz" +
      "0123456789" +
      "!@#\$%^&*()-_=+[]{},.<>?/|").toCharArray()
    val rnd = SecureRandom()
    val sb = StringBuilder()
    repeat(25) { sb.append(chars[rnd.nextInt(chars.size)]) }
    return sb.toString()
  }

  fun hash(s: String): String = s.toByteArray().fold(0) { acc, b -> (acc * 131 + b) and 0x7fffffff }.toString()

  fun startSession(ctx: Context, notPin: String) {
    prefs(ctx).edit()
      .putString(KEY_PIN_HASH, hash(notPin))
      .putBoolean(KEY_ACTIVE, true)
      .putBoolean(KEY_PIN_SHOWN, true) // bereits gezeigt
      .apply()
  }

  fun isActive(ctx: Context) = prefs(ctx).getBoolean(KEY_ACTIVE, false)

  fun canShowPinAgain(ctx: Context) = !prefs(ctx).getBoolean(KEY_PIN_SHOWN, false)

  fun verifyAndStop(ctx: Context, entered: String): Boolean {
    val ok = prefs(ctx).getString(KEY_PIN_HASH, null) == hash(entered)
    if (ok) {
      prefs(ctx).edit()
        .putBoolean(KEY_ACTIVE, false)
        .putBoolean(KEY_ROUTE_FROZEN, false)
        .remove(KEY_PIN_HASH)
        .remove(KEY_ROUTE_JSON)
        .remove(KEY_SPOTS_JSON)
        .apply()
    }
    return ok
  }

  fun freezeRoute(ctx: Context, routeJson: String, spotsJson: String) {
    prefs(ctx).edit()
      .putBoolean(KEY_ROUTE_FROZEN, true)
      .putString(KEY_ROUTE_JSON, routeJson)
      .putString(KEY_SPOTS_JSON, spotsJson)
      .apply()
  }

  fun isRouteFrozen(ctx: Context) = prefs(ctx).getBoolean(KEY_ROUTE_FROZEN, false)

  fun getFrozen(ctx: Context): Pair<String?, String?> =
    prefs(ctx).getString(KEY_ROUTE_JSON, null) to prefs(ctx).getString(KEY_SPOTS_JSON, null)

  /** Screenshot-Sperre auf Fenster anwenden */
  fun enforceFlagSecure(activity: Activity) {
    activity.window.setFlags(
      WindowManager.LayoutParams.FLAG_SECURE,
      WindowManager.LayoutParams.FLAG_SECURE
    )
  }

  /** Simpler Fallback „Kiosk“: Bildschirm an & Zurück-Taste dämpfen (in Activity). */
  fun keepScreenOn(activity: Activity, enable: Boolean) {
    if (enable)
      activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    else
      activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
  }

  /** Timer, der die Not-PIN Anzeige auf 3 s begrenzt */
  fun showPinFor3s(pin: String, onTick: (Long) -> Unit, onFinish: () -> Unit) =
    object : CountDownTimer(3000, 200) {
      override fun onTick(millisUntilFinished: Long) = onTick(millisUntilFinished)
      override fun onFinish() = onFinish()
    }.start()
}
KOT

echo "==> OutfitRules (rein regulativ, prüft nur deklarative Angaben)"
mkdir -p "$(jpath rules)"
cat > "$(jpath rules)/OutfitRules.kt" <<'KOT'
package com.example.outfitguardian.rules

data class OutfitInput(
  val skirtOrDress: Boolean,
  val lengthAboveKneeCm: Int?,      // z.B. 10 bedeutet 10 cm über Knie
  val tightsOrStockingsVisible: Boolean,
  val tightsColorIsSkin: Boolean,
  val kneeSocksOrRufflesWhiteOver: Boolean, // optional
  val heelHeightCm: Int?,
  val eyeMakeupClearlyVisible: Boolean
)

data class RuleResult(val ok: Boolean, val messages: List<String>)

object OutfitRules {
  fun check(inpt: OutfitInput): RuleResult {
    val msgs = mutableListOf<String>()

    if (!inpt.skirtOrDress) msgs += "Rock/Kleid ist Pflicht."
    if ((inpt.lengthAboveKneeCm ?: 999) > 10) msgs += "Maximale Länge: ~10 cm über Knie."
    if (!inpt.tightsOrStockingsVisible) msgs += "Strumpfhose/Halterlose müssen sichtbar sein."
    if (inpt.tightsColorIsSkin) msgs += "Hautfarbene Strumpfhose ist verboten."
    if ((inpt.heelHeightCm ?: 0) < 8) msgs += "High Heels mind. 8 cm Absatz sind Pflicht."
    if (!inpt.eyeMakeupClearlyVisible) msgs += "Augen-Make-up muss deutlich erkennbar sein."

    // Weißer Kontrast (optional) – Hinweis, nicht Pflicht
    if (!inpt.kneeSocksOrRufflesWhiteOver) {
      msgs += "Tipp: Weiße Kniestrümpfe/Rüschensocken über Strumpfhose erhöhen Sichtbarkeit (optional)."
    }

    return RuleResult(msgs.isEmpty(), msgs)
  }
}
KOT

echo "==> NotPinActivity (zeigt 25-stelligen Not-PIN exakt 3 s, mit Screenshot-Sperre, dann beendet sich)"
cat > "$(jpath)/NotPinActivity.kt" <<'KOT'
package com.example.outfitguardian

import android.os.Bundle
import android.widget.TextView
import androidx.activity.ComponentActivity
import com.example.outfitguardian.security.SessionGuard

class NotPinActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SessionGuard.enforceFlagSecure(this)
    setContentView(android.R.layout.simple_list_item_1)
    val tv = findViewById<TextView>(android.R.id.text1)

    val pin = intent.getStringExtra("pin") ?: "—"
    tv.text = "NOT-PIN: $pin\n(wird nach 3s ausgeblendet)"

    SessionGuard.showPinFor3s(pin,
      onTick = { /* optional Countdown anzeigen */ },
      onFinish = { finish() }
    )
  }

  override fun onBackPressed() {
    // unterbinden
  }
}
KOT

echo "==> Foreground-Service (hält Session aktiv)"
cat > "$(jpath)/SessionForegroundService.kt" <<'KOT'
package com.example.outfitguardian

import android.app.*
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class SessionForegroundService : Service() {
  companion object {
    const val CH = "session_guard_channel"
    const val ID = 1001
  }

  override fun onCreate() {
    super.onCreate()
    val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    if (mgr.getNotificationChannel(CH) == null) {
      mgr.createNotificationChannel(NotificationChannel(CH, "Session", NotificationManager.IMPORTANCE_LOW))
    }
    val pi = PendingIntent.getActivity(this, 0,
      Intent(this, MainActivity::class.java),
      PendingIntent.FLAG_IMMUTABLE
    )
    val notif = NotificationCompat.Builder(this, CH)
      .setContentTitle("Session aktiv")
      .setContentText("App bleibt im Vordergrund, Route/Hotspots sind eingefroren.")
      .setSmallIcon(android.R.drawable.ic_lock_lock)
      .setContentIntent(pi)
      .build()
    startForeground(ID, notif)
  }

  override fun onBind(intent: Intent?): IBinder? = null
}
KOT

echo "==> MainActivity aktualisieren (Session-Flow, Freeze, PIN-Anzeige, Screenshot-Sperre, Exit nur mit PIN)"
cat > "$(jpath)/MainActivity.kt" <<'KOT'
package com.example.outfitguardian

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.outfitguardian.rules.OutfitInput
import com.example.outfitguardian.rules.OutfitRules
import com.example.outfitguardian.security.SessionGuard
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : ComponentActivity() {

  private val reqPerms = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
  ) { /* no-op */ }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    SessionGuard.enforceFlagSecure(this)         // Screenshot-Sperre
    SessionGuard.keepScreenOn(this, true)        // Fokus halten (Fallback)
    setContentView(R.layout.activity_main)

    if (!hasLocationPerm()) {
      reqPerms.launch(arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION
      ))
    }

    val tvSession = findViewById<TextView>(R.id.tvSession)
    fun refreshState() {
      tvSession.text = "Session: " + if (SessionGuard.isActive(this)) "AKTIV" else "INAKTIV"
    }
    refreshState()

    findViewById<Button>(R.id.btnSetRoute).setOnClickListener {
      if (SessionGuard.isRouteFrozen(this)) {
        toast("Route/Hotspots sind eingefroren.")
      } else {
        // Demo: Dummy-Route & Hotspots als JSON
        val route = JSONArray().put(JSONObject().put("lat", 0.0).put("lng", 0.0))
        val spots = JSONArray()
          .put(JSONObject().put("name", "Marktplatz").put("lat", 0.0).put("lng", 0.0).put("stayMin", 5))
        SessionGuard.freezeRoute(this, route.toString(), spots.toString())
        toast("Route/Hotspots gesetzt & werden nach Start eingefroren.")
      }
    }

    findViewById<Button>(R.id.btnRefPhoto).setOnClickListener {
      toast("Demo: 1. Referenzfoto aufgenommen (Platzhalter).")
    }

    findViewById<Button>(R.id.btnStartSession).setOnClickListener {
      if (!SessionGuard.isRouteFrozen(this)) {
        toast("Bitte zuerst Route & Hotspots setzen.")
        return@setOnClickListener
      }
      // Not-PIN generieren & 3 s anzeigen
      val pin = SessionGuard.generatePin()
      startActivity(Intent(this, NotPinActivity::class.java).putExtra("pin", pin))
      // Session aktivieren
      SessionGuard.startSession(this, pin)
      startForegroundSession()
      refreshState()
    }

    findViewById<Button>(R.id.btnStopWithPin).setOnClickListener {
      // einfacher Dialog zum Eingeben (Android-Builtin)
      val dlg = android.app.AlertDialog.Builder(this)
      val input = android.widget.EditText(this).apply {
        isSingleLine = true
        hint = "Not-PIN (25 Zeichen)"
      }
      dlg.setTitle("Session beenden")
        .setMessage("Bitte Not-PIN eingeben.")
        .setView(input)
        .setPositiveButton("Beenden") { d, _ ->
          val ok = SessionGuard.verifyAndStop(this, input.text.toString())
          if (ok) {
            stopForegroundSession()
            toast("Session beendet.")
          } else {
            toast("PIN falsch.")
          }
          d.dismiss()
        }
        .setNegativeButton("Abbrechen") { d, _ -> d.dismiss() }
        .show()
    }

    findViewById<Button>(R.id.btnCheckOutfit).setOnClickListener {
      // Demo-Eingaben – in echt würdest du UI/Erkennung anbinden
      val input = OutfitInput(
        skirtOrDress = true,
        lengthAboveKneeCm = 10,
        tightsOrStockingsVisible = true,
        tightsColorIsSkin = false,
        kneeSocksOrRufflesWhiteOver = true,
        heelHeightCm = 9,
        eyeMakeupClearlyVisible = true
      )
      val res = OutfitRules.check(input)
      val msg = if (res.ok) "Outfit OK" else res.messages.joinToString("\n")
      android.app.AlertDialog.Builder(this)
        .setTitle("Outfit-Prüfung")
        .setMessage(msg)
        .setPositiveButton("OK", null)
        .show()
    }

    // Nur für Entwicklung
    findViewById<Button>(R.id.btnStopSessionUnsafe).setOnClickListener {
      SessionGuard.verifyAndStop(this, "—dev—") // falsch -> beendet nicht
      refreshState()
    }
  }

  private fun hasLocationPerm() =
    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

  private fun startForegroundSession() {
    ContextCompat.startForegroundService(this,
      Intent(this, SessionForegroundService::class.java))
  }

  private fun stopForegroundSession() {
    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    stopService(Intent(this, SessionForegroundService::class.java))
  }

  private fun toast(s: String) =
    android.widget.Toast.makeText(this, s, android.widget.Toast.LENGTH_SHORT).show()

  override fun onBackPressed() {
    // Während Session kein normales Beenden
    if (SessionGuard.isActive(this)) {
      toast("Session aktiv – beenden nur mit Not-PIN.")
    } else {
      super.onBackPressed()
    }
  }
}
KOT

echo "==> Fertig. Jetzt bauen: ./gradlew :app:assembleDebug"
