package com.example.outfitguardian.session

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Gamification & Log:
 * - Punkte für Hotspots, Outfitchecks, konstantes Tempo
 * - Abzug für Verstöße
 * - Session-Log mit Events (Typ, Zeit, Nachricht)
 */
object SessionScoreManager {
    private const val PREF = "session_score"
    private const val KEY_POINTS = "points"
    private const val KEY_LOG = "log_json"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun reset(ctx: Context) {
        prefs(ctx).edit().putInt(KEY_POINTS, 0).putString(KEY_LOG, JSONArray().toString()).apply()
    }

    fun addPoints(ctx: Context, pts: Int, reason: String) {
        val p = prefs(ctx)
        val current = p.getInt(KEY_POINTS, 0)
        val newVal = current + pts
        p.edit().putInt(KEY_POINTS, newVal).apply()
        appendLog(ctx, "POINTS", "$reason (+$pts)", newVal)
    }

    fun subtractPoints(ctx: Context, pts: Int, reason: String) {
        val p = prefs(ctx)
        val current = p.getInt(KEY_POINTS, 0)
        val newVal = current - pts
        p.edit().putInt(KEY_POINTS, newVal).apply()
        appendLog(ctx, "POINTS", "$reason (-$pts)", newVal)
    }

    fun getPoints(ctx: Context): Int = prefs(ctx).getInt(KEY_POINTS, 0)

    fun getLog(ctx: Context): List<JSONObject> {
        val s = prefs(ctx).getString(KEY_LOG, JSONArray().toString()) ?: "[]"
        val arr = JSONArray(s)
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    private fun appendLog(ctx: Context, type: String, msg: String, score: Int?=null) {
        val arr = JSONArray(prefs(ctx).getString(KEY_LOG, JSONArray().toString()))
        val o = JSONObject()
        o.put("time", System.currentTimeMillis())
        o.put("type", type)
        o.put("msg", msg)
        if (score != null) o.put("score", score)
        arr.put(o)
        prefs(ctx).edit().putString(KEY_LOG, arr.toString()).apply()
    }

    fun logEvent(ctx: Context, type: String, msg: String) {
        appendLog(ctx, type, msg, getPoints(ctx))
    }
}
