package com.example.outfitguard.rules

import com.example.outfitguard.integration.TaskerBridge

/**
 * Ergebnis einer Live-Prüfung (z.B. beim Outfitcheck).
 */
data class OutfitCheckResult(
    val ok: Boolean,
    val violations: List<String> = emptyList()
)

object OutfitValidator {

    /**
     * Prüft die Strumpf-/Socken-Lagen und Kontrastregeln anhand erfasster Labels
     * des Outfitchecks (z.B. aus Computer Vision oder manuellen Bestätigungen).
     *
     * @param detectedBaseHosiery   erkannte Basis-Strumpflage (oder null, falls keine)
     * @param whiteKneeOverVisible  true, wenn weiße Kniestrümpfe/Rüschen über der Basis sichtbar sind
     * @param hasPlateau            true, wenn Plateau erkannt
     * @param heelHeightCm          erkannte Absatzhöhe in cm
     */
    fun validateHosieryAndShoe(
        requirements: SessionRequirements,
        detectedBaseHosiery: Hosiery?,
        whiteKneeOverVisible: Boolean,
        hasPlateau: Boolean,
        heelHeightCm: Int
    ): OutfitCheckResult {
        val v = mutableListOf<String>()

        // Plateau strikt verboten
        if (requirements.noPlateau && hasPlateau) {
            v += "Plateau verboten"
        }

        // Absatzhöhe
        if (heelHeightCm < requirements.heelMinCm) {
            v += "Absatz zu niedrig (min ${requirements.heelMinCm}cm)"
        }

        // Basis-Strumpf Pflicht
        if (detectedBaseHosiery == null) {
            v += "Schwarze, glänzende Strumpfhose/Halterlose (40–80den) erforderlich"
        } else {
            // Weiße Strumpfhose grundsätzlich nicht erlaubt
            if (detectedBaseHosiery == Hosiery.PURE_WHITE) {
                v += "Weiße Strumpfhose/Halterlose verboten"
            }
            // Nur erlaubte Basis
            if (!requirements.hosieryAllowed.contains(detectedBaseHosiery)) {
                v += "Falsche Basis-Strumpflage"
            }
        }

        // Sichtbare weiße Lage über der Basis Pflicht
        if (requirements.needWhiteKneeOver && !whiteKneeOverVisible) {
            v += "Weiße Kniestrümpfe/Rüschen müssen sichtbar über der Strumpfhose getragen werden"
        }

        // Kontrastpflicht (schwarz unten + weiß oben sichtbar)
        if (requirements.requireContrast) {
            if (detectedBaseHosiery != Hosiery.BLACK_GLOSS || !whiteKneeOverVisible) {
                v += "Kontrastpflicht verletzt (schwarz glänzend + weiße Kniestrümpfe/Rüschen sichtbar)"
            }
        }

        val ok = v.isEmpty()
        if (!ok) {
            // Optional: Tasker informieren
            TaskerBridge.sendViolation(
                type = "OUTFIT",
                reason = v.joinToString("; "),
                severity = 40
            )
        }
        return OutfitCheckResult(ok, v)
    }
}
