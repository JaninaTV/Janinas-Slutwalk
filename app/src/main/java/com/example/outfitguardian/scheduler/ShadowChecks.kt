package com.example.outfitguardian.scheduler

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.example.outfitguardian.integration.tasker.TaskerBus
import kotlin.random.Random

/**
 * Sehr einfache Heuristik: wenn CrowdScore länger niedrig ist, plane einen Shadow-Check
 * (Front+Seite) in den nächsten 2–4 Minuten. Danach normal weiter.
 * Erwartet, dass CrowdScheduler onCrowdScore liefert (0..1).
 */
object ShadowChecks {
  private var lowSince: Long = 0
  private var armed = false
  private val h = Handler(Looper.getMainLooper())

  fun onCrowdScore(ctx: Context, score: Float, now: Long = System.currentTimeMillis(), trigger: ()->Unit) {
    if (score < 0.25f) {
      if (lowSince == 0L) lowSince = now
      if (!armed && now - lowSince > 60_000L) {
        // in 2–4 min auslösen
        armed = true
        val delay = (120_000L + Random.nextLong(0,120_000L))
        h.postDelayed({
          TaskerBus.send(ctx, event="CHECK_START", type="SHADOW", detail="ShadowCheck", severity="LOW")
          trigger()
          armed = false
          lowSince = 0
        }, delay)
      }
    } else {
      lowSince = 0
      armed = false
    }
  }
}
