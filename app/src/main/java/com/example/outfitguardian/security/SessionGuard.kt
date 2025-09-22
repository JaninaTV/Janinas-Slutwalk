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
