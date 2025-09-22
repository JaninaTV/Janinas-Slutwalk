#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# Projektpfade (bitte ggf. anpassen, falls dein Package anders heißt)
PKG_DIR="app/src/main/java/com/example/outfitguard"
RULES_DIR="$PKG_DIR/rules"
INTEGRATION_DIR="$PKG_DIR/integration"
UTIL_DIR="$PKG_DIR/util"

mkdir -p "$RULES_DIR" "$INTEGRATION_DIR" "$UTIL_DIR"

# ---------- SessionRequirements + HosieryRule ----------
cat > "$RULES_DIR/SessionRequirements.kt" <<'KOT'
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
KOT

# ---------- RuleBook: zentrale Setups/Trigger ----------
cat > "$RULES_DIR/RuleBook.kt" <<'KOT'
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
KOT

# ---------- Validator: prüft Kontrast & Verbot Weiß-auf-Weiß ----------
cat > "$RULES_DIR/OutfitValidator.kt" <<'KOT'
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
KOT

# ---------- TaskerBridge (Broadcast-Intent) ----------
cat > "$INTEGRATION_DIR/TaskerBridge.kt" <<'KOT'
package com.example.outfitguard.integration

import android.content.Context
import android.content.Intent

/**
 * Sehr einfache Bridge zu Tasker: sendet Broadcasts, die du in Tasker
 * (Event > System > Intent Received) als Profile abfangen kannst.
 */
object TaskerBridge {

    private const val ACTION_VIOLATION_START = "com.example.outfitguard.ACTION_VIOLATION_START"

    fun sendViolation(
        type: String,   // z.B. "OUTFIT"
        reason: String, // Klartext
        severity: Int   // 0..100
    ) {
        // ACHTUNG: Context muss durch DI oder Singletons bereitgestellt werden.
        // Für Demo verwenden wir einen lazy Getter (muss in deiner App gesetzt werden).
        val ctx: Context = AppCtx.get() ?: return

        val i = Intent(ACTION_VIOLATION_START).apply {
            putExtra("violation_type", type)
            putExtra("violation_reason", reason)
            putExtra("violation_severity", severity)
        }
        ctx.sendBroadcast(i)
    }
}

/**
 * Minimaler App-Context-Holder. Setze AppCtx.set(applicationContext) z.B. in Application.onCreate().
 */
object AppCtx {
    @Volatile private var context: Context? = null
    fun set(ctx: Context) { context = ctx.applicationContext }
    fun get(): Context? = context
}
KOT

# ---------- Hilfs-Enums für Auswertung (optional) ----------
cat > "$UTIL_DIR/OutfitSignals.kt" <<'KOT'
package com.example.outfitguard.util

/**
 * Vereinheitlichte Erkennungs-Signale aus Outfitcheck (CV oder manuell).
 */
enum class BaseHosierySignal { BLACK_GLOSS, PURE_WHITE, NONE }
KOT

echo "==> Patch geschrieben:
 - $RULES_DIR/SessionRequirements.kt
 - $RULES_DIR/RuleBook.kt
 - $RULES_DIR/OutfitValidator.kt
 - $INTEGRATION_DIR/TaskerBridge.kt
 - $UTIL_DIR/OutfitSignals.kt
"

# Optionaler Hinweis, falls kein Gradle Wrapper existiert
if [[ ! -f "./gradlew" ]]; then
  echo "Hinweis: Kein ./gradlew im Repo gefunden. Build überspringen."
  exit 0
fi

# (Kein automatischer Build hier – nur Patch. Falls du builden willst:
#  ./gradlew :app:assembleDebug)
