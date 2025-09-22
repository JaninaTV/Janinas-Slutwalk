package com.example.outfitguard.rules

/**
 * Zentrale Regel-„Rezepte“. Wird z.B. von Sessionstart, Randomizer oder
 * Schuh-/Rock-Auswahl-Triggern aufgerufen.
 */
object RuleBook {

    /**
     * Baseline für aktuelle Standard-Sessions:
     * - Schwarze, glänzende Strumpfhose/Halterlose (40–80 den) als Basis
     * - Weiße Kniestrümpfe/Rüschen darüber sichtbar
     * - Kontrastpflicht
     * - No Plateau
     * - Heel min 8 cm
     */
    fun applyBaseline(req: SessionRequirements) = req.apply {
        heelMinCm = maxOf(heelMinCm, 8)
        noPlateau = true
        hosieryAllowed = setOf(Hosiery.BLACK_GLOSS)
        needWhiteKneeOver = true
        requireContrast = true
        enforceContrastAtCheck = true
    }

    /**
     * 16 cm Metallabsatz / Sonderschuh-Trigger:
     * - Mikro-Rock bis Po-Kante
     * - Heel >= 16 cm
     * - No Plateau
     * - Nur schwarze, glänzende Strumpfhose erlaubt
     * - Weiße Kniestrümpfe/Rüschen darüber Pflicht
     * - Kontrastpflicht
     */
    fun applyShoeTrigger16(req: SessionRequirements) = req.apply {
        skirtMaxToPoEdge = true
        skirtLocked = true
        heelMinCm = maxOf(heelMinCm, 16)
        noPlateau = true
        hosieryAllowed = setOf(Hosiery.BLACK_GLOSS)
        needWhiteKneeOver = true
        requireContrast = true
        enforceContrastAtCheck = true
    }

    /**
     * Random-Härtestufe kann dies kombinieren – hier nur ein Beispiel:
     * - ggf. noch strengere Variante bei besonders hoher Sichtbarkeitsstufe
     */
    fun applyHardestVariant(req: SessionRequirements) = req.apply {
        skirtMaxToPoEdge = true
        skirtLocked = true
        heelMinCm = maxOf(heelMinCm, 16)
        noPlateau = true
        hosieryAllowed = setOf(Hosiery.BLACK_GLOSS)
        needWhiteKneeOver = true
        requireContrast = true
        enforceContrastAtCheck = true
    }
}
