#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
BASE="app/src/main/java/${APP_ID//.//}"
PKG_RULES="$BASE/rules"
PKG_OUTFIT="$BASE/outfit"

mkdir -p "$PKG_RULES" "$PKG_OUTFIT"

############################################
# 1) Presets hinzufügen: Spannrock (optional) & Tartan Micro-Faltenrock
############################################
cat > "$PKG_RULES/OutfitPresetsExtras.kt" <<'KOT'
package com.example.outfitguardian.rules

import android.content.Context
import kotlin.random.Random

/**
 * Optional-Preset: „Spannrock“ – wird nur dann zur Pflicht,
 * wenn die Heuristik bei den Referenzfotos eine deutliche Saumkrümmung nach oben erkennt.
 */
object SpannrockOptionalPreset : OutfitPreset(
    name = "Spannrock-Optional",
    heelsMinCm = 12,
    requireMaxHeels = false
) {
    override fun description() =
        "Bodycon/Stretch-Micro. Wenn Saum-Spannung (Up-Curve) erkannt wird, gilt sie ab dann als Pflicht."
}

/**
 * Pflicht-Preset: „Tartan Micro-Faltenrock“ – roter Tartan, extrem kurz, plissee.
 * Maximale Länge = Glutealfalte.
 */
object TartanMicroPleatsPreset : OutfitPreset(
    name = "Tartan Micro-Faltenrock",
    heelsMinCm = 12,
    requireMaxHeels = true
) {
    override fun description() =
        "Roter Tartan-Microfaltenrock (plissee), maximale Länge = Glutealfalte; Strumpfpflicht; Stiletto ≥12 cm; kein Plateau."
}

/**
 * Utility: Fixiere nach Referenzphase die maximal ermittelte Absatzhöhe,
 * falls requireMaxHeels aktiv ist.
 */
object HeelsMonotony {
    private const val SP = "heels_monotony"
    private const val KEY_MAX = "max_heel_cm"

    fun record(ctx: Context, measuredCm: Float) {
        val sp = ctx.getSharedPreferences(SP, 0)
        val prev = sp.getFloat(KEY_MAX, 0f)
        if (measuredCm > prev) sp.edit().putFloat(KEY_MAX, measuredCm).apply()
    }

    fun required(ctx: Context): Float = ctx.getSharedPreferences(SP, 0).getFloat(KEY_MAX, 0f)
    fun reset(ctx: Context) { ctx.getSharedPreferences(SP,0).edit().remove(KEY_MAX).apply() }
}
KOT

############################################
# 2) Heuristiken erweitern:
#    - Spannrock: Saum-Spannungs-Score (Up-Curve)
#    - Tartan/Plissee: grobe Muster-/Falten-Erkennung
#    - Absatzhöhe aus Seitenprofil schätzen (für Max-Heels-Fixierung)
############################################
python3 - <<'PY'
from pathlib import Path, re
p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitHeuristics.kt")
s = p.read_text()

def inject(name, code):
    global s
    if name not in s:
        s = s.replace("object OutfitHeuristics {", "object OutfitHeuristics {\n" + code + "\n")

inject("fun hemTensionScore", r'''
  /**
   * Spannrock/Up-Curve-Score: misst, ob die Saumlinie in der Mitte höher liegt
   * als links/rechts (gebogener Saum nach oben).
   * 0..1: niedrig..hoch
   */
  fun hemTensionScore(bmp: android.graphics.Bitmap): Float {
    val r = regions(bmp).hemStripe
    val cx = (r.left + r.right)/2
    val midY = (r.top + r.bottom)/2
    val step = kotlin.math.max(1, kotlin.math.min(r.width(), r.height())/128)
    var midEdge = 0; var sideEdge = 0; var count=0
    // Kanten vertikal messen
    var y = r.top
    while (y < r.bottom - step) {
      val cMid1 = bmp.getPixel(cx, y)
      val cMid2 = bmp.getPixel(cx, y+step)
      val l1 = ((cMid1 shr 16 and 0xFF)*299 + (cMid1 shr 8 and 0xFF)*587 + (cMid1 and 0xFF)*114)/1000
      val l2 = ((cMid2 shr 16 and 0xFF)*299 + (cMid2 shr 8 and 0xFF)*587 + (cMid2 and 0xFF)*114)/1000
      if (kotlin.math.abs(l2-l1) > 30) midEdge++
      val cL1 = bmp.getPixel(r.left + step, y)
      val cL2 = bmp.getPixel(r.left + step, y+step)
      val lL1 = ((cL1 shr 16 and 0xFF)*299 + (cL1 shr 8 and 0xFF)*587 + (cL1 and 0xFF)*114)/1000
      val lL2 = ((cL2 shr 16 and 0xFF)*299 + (cL2 shr 8 and 0xFF)*587 + (cL2 and 0xFF)*114)/1000
      if (kotlin.math.abs(lL2-lL1) > 30) sideEdge++
      val cR1 = bmp.getPixel(r.right - step, y)
      val cR2 = bmp.getPixel(r.right - step, y+step)
      val lR1 = ((cR1 shr 16 and 0xFF)*299 + (cR1 shr 8 and 0xFF)*587 + (cR1 and 0xFF)*114)/1000
      val lR2 = ((cR2 shr 16 and 0xFF)*299 + (cR2 shr 8 and 0xFF)*587 + (cR2 and 0xFF)*114)/1000
      if (kotlin.math.abs(lR2-lR1) > 30) sideEdge++
      count++; y += step
    }
    val side = kotlin.math.max(1, sideEdge)
    val ratio = midEdge.toFloat() / side.toFloat()
    // Wenn Mitte "höher" kantig wechselt als Seiten, deutet das auf Bogen nach oben hin
    return ratio.coerceIn(0f, 1.5f) / 1.5f
  }
''')

inject("fun tartanPleatScore", r'''
  /**
   * Grobe Erkennung: roter Tartan + Falten (Plissee).
   * Metrik: Rotdominanz + vertikale Periodik (Faltenkämme) im Saumbereich.
   */
  fun tartanPleatScore(bmp: android.graphics.Bitmap): Float {
    val r = regions(bmp).hemStripe
    val step = kotlin.math.max(1, kotlin.math.min(r.width(), r.height())/128)
    var redBins = 0; var total=0
    var verticalEdges = 0
    var y = r.top
    while (y < r.bottom) {
      var x = r.left
      while (x < r.right - step) {
        val c = bmp.getPixel(x, y)
        val R = (c ushr 16) and 0xFF; val G = (c ushr 8) and 0xFF; val B = c and 0xFF
        // „rot“ dominiert klar
        if (R > G + 10 && R > B + 10) redBins++
        val c2 = bmp.getPixel(x+step, y)
        val l1 = ((R*299 + G*587 + B*114)/1000)
        val l2 = ((((c2 ushr 16) and 0xFF)*299 + ((c2 ushr 8) and 0xFF)*587 + ((c2) and 0xFF)*114)/1000)
        if (kotlin.math.abs(l2 - l1) > 28) verticalEdges++
        total++; x += step
      }
      y += step
    }
    val redFrac = if (total==0) 0f else redBins.toFloat()/total.toFloat()
    val edgeFrac = if (total==0) 0f else verticalEdges.toFloat()/total.toFloat()
    // beide Anteile hoch => plausibles Tartan+Falten
    return (0.6f*redFrac + 0.4f*edgeFrac).coerceIn(0f,1f)
  }
''')

inject("fun estimateHeelHeightCm", r'''
  /**
   * Absatzhöhe grob aus Seitenprofil schätzen. Ja, das ist hemdsärmelig,
   * reicht aber für Monotonie/Max-Fixierung.
   */
  fun estimateHeelHeightCm(bmp: android.graphics.Bitmap): Float {
    val shoes = regions(bmp).shoes
    val groundY = estimateGroundLineY(bmp, shoes)
    val heelPeakY = estimateHeelPeakY(bmp, shoes, groundY)
    val px = (groundY - heelPeakY).coerceAtLeast(0)
    // naive Umrechnung: 7 px ≈ 1 cm (dein Setup kalibriert's besser)
    return (px / 7f).coerceAtLeast(0f)
  }
''')

p.write_text(s)
print("OutfitHeuristics extended")
PY

############################################
# 3) OutfitCheckManager-Hooks:
#    - SpannrockOptional: wenn Score hoch bei Referenz -> wird Pflicht
#    - TartanMicroPleats: bei aktivem Preset: Score prüfen + Micro-Länge (Glutealfalte)
#    - HeelsMax-Fix: nach Referenz die höchste gefundene Absatzhöhe festnageln
############################################
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitCheckManager.kt")
s = p.read_text()
if "Spannrock/Tartan hooks" not in s:
  s = s.replace("val reasons = mutableListOf<String>()",
r'''val reasons = mutableListOf<String>()

        // Spannrock/Tartan hooks
        try {
            // 1) Spannrock optional: wenn bei Referenzfotos hohe Spannung erkannt -> Pflicht speichern
            val sp = ctx.getSharedPreferences("spannrock_flag", 0)
            val alreadyReq = sp.getBoolean("required", false)
            val tension = OutfitHeuristics.hemTensionScore(bmp)
            if (!alreadyReq && intentRefMode()) { // deine Kamera setzt ref_mode Extra
                if (tension >= 0.65f) {
                    sp.edit().putBoolean("required", true).apply()
                }
            }
            if (sp.getBoolean("required", false)) {
                if (tension < 0.55f) reasons += "Spannrock-Pflicht nicht erfüllt"
            }

            // 2) Tartan Micro-Faltenrock: wenn Preset aktiv, prüfe Muster/Falten & Micro-Länge
            val preset = ctx.getSharedPreferences("fortuna_preset", 0).getString("drawn", "")
            if (preset == "Tartan Micro-Faltenrock") {
                val tscore = OutfitHeuristics.tartanPleatScore(bmp)
                if (tscore < 0.55f) reasons += "Tartan/Plissee nicht erkennbar"
                // Micro-Länge: maximale Länge = Glutealfalte (hier approximiert über hemAboveKnee + Body landmarks light)
                val cmAbove = OutfitHeuristics.hemAboveKneeCmApprox(bmp)
                if (cmAbove < 18) { // Proxy für „mindestens gluteal-nah“
                    reasons += "Rock nicht kurz genug (Micro-Zone gefordert)"
                }
            }

            // 3) Heels-Max-Fix: nach Referenzphase größte Absatzhöhe als Pflicht
            if (intentRefMode()) {
                val cm = OutfitHeuristics.estimateHeelHeightCm(bmp)
                com.example.outfitguardian.rules.HeelsMonotony.record(ctx, cm)
            } else {
                val need = com.example.outfitguardian.rules.HeelsMonotony.required(ctx)
                if (need > 0f) {
                    val have = OutfitHeuristics.estimateHeelHeightCm(bmp)
                    if (have + 0.8f < need) { // kleine Toleranz
                        reasons += "Absatz zu niedrig (Pflicht: ≥ %.1f cm)".format(need)
                    }
                }
            }
        } catch (_:Throwable) {}
''')
  # Hilfsfunktion, um ref_mode zu erkennen (falls nicht vorhanden)
  if "private fun intentRefMode" not in s:
    s += '''

    private fun intentRefMode(): Boolean {
        return try { (lastCaptureIntent?.getBooleanExtra("ref_mode", false) ?: false) } catch (_:Throwable) { false }
    }
'''
  Path(p).write_text(s)
  print("OutfitCheckManager patched")
else:
  print("OutfitCheckManager already contains Spannrock/Tartan hooks")
PY

############################################
# 4) Optional: Voreinstellung ermöglichen (z. B. Preset wählen)
############################################
python3 - <<'PY'
from pathlib import Path
p = Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
s = p.read_text()
if "TartanMicroPleatsPreset" not in s:
  s = s.replace("import com.example.outfitguardian.rules.FortunaPreset",
                "import com.example.outfitguardian.rules.FortunaPreset\nimport com.example.outfitguardian.rules.TartanMicroPleatsPreset\nimport com.example.outfitguardian.rules.SpannrockOptionalPreset")
Path(p).write_text(s)
print("MainActivity imports updated (presets)")
PY

############################################
# 5) Build
############################################
echo "==> Build"
if [ -x ./gradlew ]; then
  ./gradlew --stop >/dev/null 2>&1 || true
  ./gradlew -i :app:assembleDebug
else
  gradle --stop >/dev/null 2>&1 || true
  gradle -i :app:assembleDebug
fi

echo "✅ Presets hinzugefügt: Spannrock (optional) & Tartan Micro-Faltenrock. Max-Heels-Fix aktiv. APK unter app/build/outputs/apk/debug/"
