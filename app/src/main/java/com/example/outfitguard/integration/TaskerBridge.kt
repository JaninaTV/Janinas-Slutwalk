package com.example.outfitguard.integration

import android.content.Context
import android.content.Intent

/**
 * Sehr einfache Bridge zu Tasker: sendet Broadcasts, die du in Tasker
 * (Event > System > Intent Received) als Profile abfangen kannst.
 */
object TaskerBridge {

    private const val ACTION_VIOLATION_START = "com.example.outfitguard.ACTION_VIOLATION_START"

    fun sendViolation(
        type: String,   // z.B. "OUTFIT"
        reason: String, // Klartext
        severity: Int   // 0..100
    ) {
        // ACHTUNG: Context muss durch DI oder Singletons bereitgestellt werden.
        // Für Demo verwenden wir einen lazy Getter (muss in deiner App gesetzt werden).
        val ctx: Context = AppCtx.get() ?: return

        val i = Intent(ACTION_VIOLATION_START).apply {
            putExtra("violation_type", type)
            putExtra("violation_reason", reason)
            putExtra("violation_severity", severity)
        }
        ctx.sendBroadcast(i)
    }
}

/**
 * Minimaler App-Context-Holder. Setze AppCtx.set(applicationContext) z.B. in Application.onCreate().
 */
object AppCtx {
    @Volatile private var context: Context? = null
    fun set(ctx: Context) { context = ctx.applicationContext }
    fun get(): Context? = context
}
