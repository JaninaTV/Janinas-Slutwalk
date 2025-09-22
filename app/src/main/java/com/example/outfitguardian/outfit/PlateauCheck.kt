package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

object PlateauCheck {
  /**
   * Nutzt HeelEstimator-Geometrie: Bodenlinie, Fersenpeak, Vorderfußhöhe.
   * Plateau wenn frontHeight >= 0.35 * heelHeight.
   */
  fun isPlateau(bmp: Bitmap): Boolean {
    val regs = OutfitHeuristics.regions(bmp)
    val shoesR = regs.shoes
    val h = bmp.height
    // Bodenlinie grob: unterstes 10%-Band maximale Kanten
    val groundY = OutfitHeuristics.estimateGroundLineY(bmp, shoesR)
    val heelPeakY = OutfitHeuristics.estimateHeelPeakY(bmp, shoesR, groundY)
    val toeY = OutfitHeuristics.estimateToeTopY(bmp, shoesR, groundY)
    val heelHeight = (groundY - heelPeakY).coerceAtLeast(0)
    val frontHeight = (groundY - toeY).coerceAtLeast(0)
    if (heelHeight <= 0) return false
    return frontHeight.toFloat() / heelHeight.toFloat() >= 0.35f
  }
}
