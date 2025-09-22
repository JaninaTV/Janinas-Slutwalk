#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"

mkdir -p "$PKG/outfit"
cat > "$PKG/outfit/DualOutfitCheckManager.kt" <<'KOT'
package com.example.outfitguardian.outfit

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.example.outfitguardian.integration.tasker.TaskerEvents
import com.example.outfitguardian.vault.PhotoVault
import java.io.File
import java.io.InputStream

/**
 * DualOutfitCheckManager:
 * - Erstellt automatisch zwei Fotos (Front, Seite) im 5s-Abstand
 * - Führt Heuristiken aus (Frontal: Saum/Socken/Strümpfe/Augen, Seite: Absatzhöhe)
 * - Ergebnis sofort an Tasker + Log
 */
object DualOutfitCheckManager {

    private var step = 0
    private var tmpFront: String? = null
    private var tmpSide: String? = null

    fun startAutoCheck(ctx: Context, takePhoto: (onDone:(Uri)->Unit)->Unit) {
        step = 0
        tmpFront = null
        tmpSide = null
        // Erstes Foto (Front)
        takePhoto { uri ->
            val f = cacheFileFromStream(ctx, ctx.contentResolver.openInputStream(uri)!!, "front.jpg")
            tmpFront = f
            PhotoVault.addImageEncrypted(ctx, ctx.contentResolver.openInputStream(uri)!!, "front_check.jpg")
            // 5 Sekunden warten, dann Seitenfoto
            Handler(Looper.getMainLooper()).postDelayed({
                takePhoto { uri2 ->
                    val f2 = cacheFileFromStream(ctx, ctx.contentResolver.openInputStream(uri2)!!, "side.jpg")
                    tmpSide = f2
                    PhotoVault.addImageEncrypted(ctx, ctx.contentResolver.openInputStream(uri2)!!, "side_check.jpg")
                    analyzeBoth(ctx)
                }
            }, 5000)
        }
    }

    private fun analyzeBoth(ctx: Context) {
        val front = tmpFront ?: return
        val side = tmpSide ?: return
        val bmpFront = BitmapFactory.decodeFile(front) ?: return
        val bmpSide = BitmapFactory.decodeFile(side) ?: return

        val (passFront, reasonsFront) = OutfitCheckManager.checkBitmap(ctx, front)
        val reasons = mutableListOf<String>()
        if (!passFront) reasons.addAll(reasonsFront)

        // Absatzhöhe Heuristik (nur Seitenfoto)
        if (!heelHighEnough(bmpSide)) reasons += "Absatzhöhe <8cm oder Plateau erkannt"

        val pass = reasons.isEmpty()
        if (pass) {
            TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.OUTFIT, "Outfitcheck (Front+Seite) ok")
        } else {
            val msg = "Nachbesserungspflicht: " + reasons.joinToString("; ").take(160)
            TaskerEvents.startViolation(ctx, TaskerEvents.Type.OUTFIT, 55, msg)
        }
    }

    private fun heelHighEnough(bmp: android.graphics.Bitmap): Boolean {
        val r = OutfitHeuristics.regions(bmp).shoes
        val f = OutfitHeuristics.regionFeatures(bmp, r)
        // grobe Logik: Absatz = hohe vertikale Kantenrate
        val edge = f.edgeRate
        return edge > 0.18f
    }

    private fun cacheFileFromStream(ctx: Context, src: InputStream, name: String): String {
        val dir = File(ctx.cacheDir, "dual").apply { mkdirs() }
        val f = File(dir, name)
        src.use { input -> f.outputStream().use { input.copyTo(it) } }
        return f.absolutePath
    }
}
KOT

echo "==> build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
