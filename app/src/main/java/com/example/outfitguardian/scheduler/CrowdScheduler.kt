package com.example.outfitguardian.scheduler

import android.content.Context

/**
 * Platzhalter CrowdScheduler – sorgt dafür, dass ShadowChecks eingebunden werden können.
 * Wenn du später echte Crowd-Daten (Sensorik, Kamera, API) einbindest,
 * ersetze die onTick-Logik.
 */
class CrowdScheduler(
  private val ctx: Context,
  private val navProvider: ()->Navigator?
) {
  private var lastScore: Float = 0f

  fun start() {
    // Hier könnte man z.B. alle 10s CrowdScore updaten
    // Wir simulieren erstmal nur Low-Crowd.
    onTick(0.1f)
  }

  fun onTick(score: Float) {
    lastScore = score
    ShadowChecks.onCrowdScore(ctx, score) {
      navProvider()?.requestOutfitCheckNow()
    }
  }
}

/** Dummy-Interface für Navigator */
interface Navigator {
  fun requestOutfitCheckNow()
}
