package com.example.outfitguardian.session

import android.content.Context
import com.example.outfitguardian.integration.tasker.TaskerBus

object StreakManager {
  private const val SP="streak_mgr"
  private const val K_STREAK="streak"
  private const val K_FAILS="fails"
  private const val K_FREEZE_UNTIL="freeze_until"

  fun reset(ctx: Context) {
    ctx.getSharedPreferences(SP,0).edit().clear().apply()
  }

  fun getStreak(ctx: Context): Int = ctx.getSharedPreferences(SP,0).getInt(K_STREAK,0)
  fun getFails(ctx: Context): Int = ctx.getSharedPreferences(SP,0).getInt(K_FAILS,0)

  fun isFrozen(ctx: Context, now: Long = System.currentTimeMillis()): Boolean =
    now < ctx.getSharedPreferences(SP,0).getLong(K_FREEZE_UNTIL, 0L)

  fun freezeFor(ctx: Context, minutes: Int) {
    val until = System.currentTimeMillis() + minutes*60_000L
    ctx.getSharedPreferences(SP,0).edit().putLong(K_FREEZE_UNTIL, until).apply()
    TaskerBus.send(ctx, event="SESSION_TIME_FREEZE", type="GENERAL", detail="Freeze ${minutes}m", severity="MEDIUM")
  }

  fun recordPass(ctx: Context) {
    val sp = ctx.getSharedPreferences(SP,0)
    val s = sp.getInt(K_STREAK,0)+1
    sp.edit().putInt(K_STREAK, s).apply()
    TaskerBus.send(ctx, event="STREAK_UPDATE", type="GENERAL", detail="PASS", counterStreak=s, counterFail=sp.getInt(K_FAILS,0))
  }

  fun recordFail(ctx: Context) {
    val sp = ctx.getSharedPreferences(SP,0)
    val f = sp.getInt(K_FAILS,0)+1
    sp.edit().putInt(K_FAILS, f).putInt(K_STREAK, 0).apply()
    TaskerBus.send(ctx, event="STREAK_UPDATE", type="GENERAL", detail="FAIL", counterStreak=0, counterFail=f)
  }
}
