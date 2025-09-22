package com.example.outfitguardian.integration.tasker

import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Einheitlicher Event-Bus zu Tasker.
 * - Broadcast-Intent: action "com.example.outfitguardian.TASKER_EVENT"
 * - Optional HTTP POST an Tasker REST (konfigurierbar)
 *
 * Event-Namen (EVENT):
 *  - OUTFIT_PASS, OUTFIT_FAIL
 *  - ROUTE_PASS, ROUTE_FAIL
 *  - CHECK_START, CHECK_PASS, CHECK_FAIL
 *  - AUDIT_START, AUDIT_PASS, AUDIT_FAIL
 *  - STREAK_UPDATE
 *  - SESSION_TIME_ADD, SESSION_TIME_FREEZE
 *  - HOTSPOT_MOD
 *
 * Extras (Strings):
 *  - type: Kategorie (GLANZ|ABSATZ|SAUM|HOSIERY|KORRIDOR|TURN|STOP|SHADOW|AUDIT|GENERAL)
 *  - detail: Freitext kurz
 *  - severity: LOW|MEDIUM|HIGH|CRITICAL
 *  - minutes_delta: (+/-) Minutenänderung (als String)
 *  - corridor_m: neuer Korridor in Metern (als String)
 *  - action: ADD_LOOP|DOUBLE_HOTSPOT|SHRINK_CORRIDOR|NONE
 *  - counter_fail: gesamt Fails (als String)
 *  - counter_streak: aktuelle Streak (als String)
 */
object TaskerBus {
  private const val ACTION = "com.example.outfitguardian.TASKER_EVENT"
  @Volatile private var restUrl: String? = null

  fun configureRest(url: String?) { restUrl = url }

  fun send(
    ctx: Context,
    event: String,
    type: String = "GENERAL",
    detail: String = "",
    severity: String = "LOW",
    minutesDelta: Int? = null,
    corridorM: Int? = null,
    action: String? = null,
    counterFail: Int? = null,
    counterStreak: Int? = null
  ) {
    // Broadcast
    val i = Intent(ACTION).apply {
      putExtra("event", event)
      putExtra("type", type)
      putExtra("detail", detail)
      putExtra("severity", severity)
      minutesDelta?.let { putExtra("minutes_delta", it.toString()) }
      corridorM?.let { putExtra("corridor_m", it.toString()) }
      action?.let { putExtra("action", it) }
      counterFail?.let { putExtra("counter_fail", it.toString()) }
      counterStreak?.let { putExtra("counter_streak", it.toString()) }
    }
    ctx.sendBroadcast(i)

    // Optional REST
    restUrl?.let { url ->
      kotlin.runCatching {
        val payload = JSONObject().apply {
          put("event", event); put("type", type); put("detail", detail); put("severity", severity)
          if (minutesDelta!=null) put("minutes_delta", minutesDelta)
          if (corridorM!=null) put("corridor_m", corridorM)
          if (action!=null) put("action", action)
          if (counterFail!=null) put("counter_fail", counterFail)
          if (counterStreak!=null) put("counter_streak", counterStreak)
        }.toString()
        val con = (URL(url).openConnection() as HttpURLConnection).apply {
          requestMethod = "POST"
          doOutput = true
          setRequestProperty("Content-Type","application/json")
        }
        con.outputStream.use { it.write(payload.toByteArray()) }
        con.inputStream.use { it.readBytes() }
        con.disconnect()
      }.onFailure { Log.w("TaskerBus","REST send failed: ${it.message}") }
    }
  }
}
