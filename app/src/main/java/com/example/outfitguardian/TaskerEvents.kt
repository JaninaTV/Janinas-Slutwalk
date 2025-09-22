package com.example.outfitguardian.integration.tasker

import android.content.Context
import android.content.Intent
import java.util.UUID

object TaskerEvents {

  const val ACTION_VIOLATION_START = "com.example.outfitguardian.ACTION_VIOLATION_START"
  const val ACTION_VIOLATION_END   = "com.example.outfitguardian.ACTION_VIOLATION_END"

  object Type {
    const val ROUTE = "ROUTE"
    const val CORRIDOR = "CORRIDOR"
    const val SPEED = "SPEED"
    const val STOP = "STOP"
    const val BACKTRACK = "BACKTRACK"
    const val RED_ZONE = "RED_ZONE"
    const val OUTFIT = "OUTFIT"
  }

  fun startViolation(
    context: Context,
    type: String,
    severity: Int,
    message: String
  ): String {
    val id = UUID.randomUUID().toString()
    val i = Intent(ACTION_VIOLATION_START).apply {
      putExtra("violation_id", id)
      putExtra("type", type)
      putExtra("severity", severity.coerceIn(0, 100))
      putExtra("message", message)
      putExtra("ts", System.currentTimeMillis())
    }
    context.sendBroadcast(i)
    return id
  }

  fun endViolation(
    context: Context,
    violationId: String,
    type: String,
    message: String = "resolved"
  ) {
    val i = Intent(ACTION_VIOLATION_END).apply {
      putExtra("violation_id", violationId)
      putExtra("type", type)
      putExtra("message", message)
      putExtra("ts", System.currentTimeMillis())
    }
    context.sendBroadcast(i)
  }
}
