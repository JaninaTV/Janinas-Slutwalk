package com.example.outfitguardian.session

import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * Blockt eigene Non-Critical-Notifications; optional kann der Nutzer DND freigeben.
 * Systemweite Blockade geht nur mit user consent (Policy access).
 */
object NotificationGuard {
  fun enableInAppQuiet(ctx: Context) {
    // Deine App: keine Non-Critical Notifications während Session
    ctx.getSharedPreferences("notif_guard",0).edit().putBoolean("quiet", true).apply()
  }
  fun disableInAppQuiet(ctx: Context) {
    ctx.getSharedPreferences("notif_guard",0).edit().putBoolean("quiet", false).apply()
  }
  fun requestSystemDnd(ctx: Context) {
    if (Build.VERSION.SDK_INT >= 23) {
      val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      // Hinweis: tatsächliche Freigabe erfordert Settings-Intent, hier nur Platzhalter-Aufruf
      // ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
  }
}
