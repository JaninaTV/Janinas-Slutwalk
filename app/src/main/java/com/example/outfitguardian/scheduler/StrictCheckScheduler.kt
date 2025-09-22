package com.example.outfitguardian.scheduler

import android.content.Context
import android.content.Intent
import androidx.work.*
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import com.example.outfitguardian.AutoCameraActivity
import com.example.outfitguardian.FastenerMacroActivity

object StrictCheckScheduler {
  fun start(ctx: Context) {
    // zwei Pigtail/Front-Checks pro Stunde: wir reuse AutoCameraActivity, die Front zuerst schießt
    val w1 = OneTimeWorkRequestBuilder<FrontCheckWorker>()
      .setInitialDelay(25, TimeUnit.MINUTES).build()
    val w2 = OneTimeWorkRequestBuilder<FrontCheckWorker>()
      .setInitialDelay(55, TimeUnit.MINUTES).build()
    WorkManager.getInstance(ctx).enqueueUniqueWork("front_checks", ExistingWorkPolicy.REPLACE, listOf(w1,w2))

    // Double-Check Blöcke: 1–2 mal pro Stunde
    val blocks = Random.nextInt(1,3)
    repeat(blocks) { i ->
      val delay = Random.nextInt(20, 50).toLong()
      val w = OneTimeWorkRequestBuilder<DoubleCheckWorker>()
        .setInitialDelay(delay, TimeUnit.MINUTES).build()
      WorkManager.getInstance(ctx).enqueueUniqueWork("double_check_$i", ExistingWorkPolicy.REPLACE, w)
    }
  }
  fun stop(ctx: Context) {
    WorkManager.getInstance(ctx).cancelUniqueWork("front_checks")
    WorkManager.getInstance(ctx).cancelAllWorkByTag("double_check")
  }

  class FrontCheckWorker(ctx: Context, p: WorkerParameters): CoroutineWorker(ctx,p) {
    override suspend fun doWork(): Result {
      val i = Intent(applicationContext, AutoCameraActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i)
      return Result.success()
    }
  }
  class DoubleCheckWorker(ctx: Context, p: WorkerParameters): CoroutineWorker(ctx,p) {
    override suspend fun doWork(): Result {
      val i1 = Intent(applicationContext, AutoCameraActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i1)
      // 10 Sekunden später Fastener-Makro
      kotlinx.coroutines.delay(10_000)
      val i2 = Intent(applicationContext, FastenerMacroActivity::class.java).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
      applicationContext.startActivity(i2)
      return Result.success()
    }
  }
}
