package com.example.outfitguardian.scheduler

import android.content.Context
import android.content.Intent
import androidx.work.*
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import com.example.outfitguardian.FastenerMacroActivity

object FastenerMacroScheduler {
  private const val TAG="fastener_macro"

  fun scheduleNext(ctx: Context) {
    val delay = Random.nextInt(30, 46).toLong()
    val req = OneTimeWorkRequestBuilder<MacroWorker>()
      .setInitialDelay(delay, TimeUnit.MINUTES)
      .addTag(TAG).build()
    WorkManager.getInstance(ctx).enqueueUniqueWork(TAG, ExistingWorkPolicy.REPLACE, req)
  }

  fun cancel(ctx: Context) { WorkManager.getInstance(ctx).cancelUniqueWork(TAG) }

  class MacroWorker(ctx: Context, params: WorkerParameters): CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
      val i = Intent(applicationContext, FastenerMacroActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      applicationContext.startActivity(i)
      scheduleNext(applicationContext)
      return Result.success()
    }
  }
}
