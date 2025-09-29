package com.example.outfitguard.rules

// Eingabestruktur für Prüfungen (kommt aus deiner Erkennung)
data class OutfitInput(
    // Für Panty
    val pantsType: String = "NONE",      // "PANTY" oder anderes
    val buttCoveredByPants: Boolean = false,
    val thighsFullyFree: Boolean = false,

    // Für Nano
    val buttCoverPercent: Int = 0,

    // Für Cutout
    val cutoutPercent: Int = 0,
    val movedRecently: Boolean = true,

    // Gemeinsam
    val hosieryPresent: Boolean = false,
    val hosieryGlossy: Boolean = false,
    val heelHeightCm: Int = 0,
    val plateauDetected: Boolean = false
)

data class OutfitCheckResult(
    val ok: Boolean,
    val violations: List<String>
)
