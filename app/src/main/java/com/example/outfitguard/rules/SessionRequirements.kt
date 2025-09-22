package com.example.outfitguard.rules

/**
 * Live-Requirements, die die App/Session fortlaufend erzwingt.
 */
data class SessionRequirements(
    var skirtMaxToPoEdge: Boolean = false,          // Mikro bis Po-Falte
    var skirtLocked: Boolean = false,               // Länge fixiert, nicht änderbar
    var heelMinCm: Int = 8,
    var noPlateau: Boolean = true,
    var hosieryAllowed: Set<Hosiery> = setOf(Hosiery.BLACK_GLOSS),
    var needWhiteKneeOver: Boolean = true,          // Weiße Kniestrümpfe/Rüschen drüber sichtbar
    var requireContrast: Boolean = true,            // Sichtbarer Kontrast Pflicht
    var enforceContrastAtCheck: Boolean = true      // Bei Outfitcheck prüfen
)

enum class Hosiery {
    BLACK_GLOSS,   // 40–80 den, glänzend
    PURE_WHITE     // bewusst vorhanden, aber im aktuellen Profil verboten
}
