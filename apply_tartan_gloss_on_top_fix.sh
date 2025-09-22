#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
BASE="app/src/main/java/${APP_ID//.//}"
PKG_OUTFIT="$BASE/outfit"

mkdir -p "$PKG_OUTFIT"

############################################
# 1) Heuristiken anpassen:
#    - glossThighScore(): Glanz NUR im Oberschenkel-ROI
#    - whiteSockScore(): wie gehabt (reinweiß), Muster optional
#    - overLayerContrast(): Weiß über Schwarz (Lagen-Check)
############################################
python3 - <<'PY'
from pathlib import Path

p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitHeuristics.kt")
s = p.read_text()

def ensure_func(tag, code):
    global s
    if tag not in s:
        s = s.replace("object OutfitHeuristics {", "object OutfitHeuristics {\n" + code + "\n")

# Neue Funktion: Glanz oben (Oberschenkel-ROI)
ensure_func("fun glossThighScore", r'''
  /**
   * Glanzgrad im OBEREN Bein-ROI (Oberschenkel) für schwarze Strumpfhose/Halterlose.
   * 0..1 — erwartet dunkle Basis + spekulare Highlights.
   */
  fun glossThighScore(bmp: android.graphics.Bitmap): Float {
    val thigh = regions(bmp).thigh
    val step = kotlin.math.max(1, kotlin.math.min(thigh.width(), thigh.height())/128)
    var bright=0; var dark=0; var tot=0
    var y=thigh.top
    while (y<thigh.bottom) {
      var x=thigh.left
      while (x<thigh.right) {
        val c=bmp.getPixel(x,y)
        val r=(c ushr 16) and 0xFF; val g=(c ushr 8) and 0xFF; val b=c and 0xFF
        val mx=kotlin.math.max(r, kotlin.math.max(g,b))
        val mn=kotlin.math.min(r, kotlin.math.min(g,b))
        val v=mx/255f
        val sat = if (mx==0) 0f else 1f - (mn.toFloat()/mx.toFloat())
        if (v<0.28f) dark++
        if (v>0.70f && sat<0.25f) bright++
        tot++; x+=step
      }
      y+=step
    }
    if (tot==0) return 0f
    val darkFrac = dark.toFloat()/tot
    val specFrac = bright.toFloat()/tot
    return (0.55f*darkFrac + 0.45f*specFrac).coerceIn(0f,1f)
  }
''')

# Falls whiteSockScore/overLayerContrast schon existieren, lassen wir sie in Ruhe.
# Knit-Score bleibt Bonus, kein Fail.

p.write_text(s)
print("Heuristics patched: glossThighScore() added/ensured")
PY

############################################
# 2) OutfitCheckManager: Tartan-Preset-Regeln umdrehen
#    - Glanz oben Pflicht (glossThighScore >= 0.55)
#    - Weißsocken Pflicht über Schwarz (whiteSockScore >= 0.70 + overLayerContrast >= 0.35)
#    - Knit-Score nur Bonus (kein Fail)
#    - Hauttöne tabu
############################################
python3 - <<'PY'
from pathlib import Path, re

p = Path("app/src/main/java/com/example/outfitguardian/outfit/OutfitCheckManager.kt")
s = p.read_text()

block_id = "TARTAN_WHITE_OVER_BLACK_V2"
if block_id in s:
    print("Manager already patched")
else:
    s = s.replace("val reasons = mutableListOf<String>()",
r'''val reasons = mutableListOf<String>()

        // TARTAN_WHITE_OVER_BLACK_V2: Glanz oben (Oberschenkel), Weißsocken darüber, Muster optional
        try {
            val presetName = ctx.getSharedPreferences("fortuna_preset", 0).getString("drawn", "")
            if (presetName == "Tartan Micro-Faltenrock") {
                // 0) Hauttöne am Bein tabu
                val skinFrac = OutfitHeuristics.skinToneFraction(bmp)
                if (skinFrac > 0.15f) reasons += "Hauttöne am Bein sichtbar (verboten)"

                // 1) Schwarze Glanzbasis im OBEREN Bereich (Oberschenkel)
                val glossTop = OutfitHeuristics.glossThighScore(bmp)
                if (glossTop < 0.55f) {
                    reasons += "Strumpfhose/Halterlose oben nicht glänzend erkennbar"
                }

                // 2) Weiße Socken/Rüschen DARÜBER (reinweiß + Lagenkontrast)
                val whiteScore = OutfitHeuristics.whiteSockScore(bmp)
                val overlay = OutfitHeuristics.overLayerContrast(bmp)
                if (whiteScore < 0.70f || overlay < 0.35f) {
                    reasons += "Weiße Kniestrümpfe/Rüschen über der Strumpfhose nicht erkennbar"
                }

                // 3) Knit-Textur: nur Bonus, KEIN Fail
                runCatching {
                    val knit = OutfitHeuristics.knitTextureScore(bmp)
                    // optional: bei hohem knit kann man Strenge an anderer Stelle lockern
                }
            }
        } catch (_:Throwable) {}
''', 1)
    Path(p).write_text(s)
    print("OutfitCheckManager patched with TARTAN_WHITE_OVER_BLACK_V2")
PY

############################################
# 3) Build
############################################
echo "==> Build"
if [ -x ./gradlew ]; then
  ./gradlew --stop >/dev/null 2>&1 || true
  ./gradlew -i :app:assembleDebug
else
  gradle --stop >/dev/null 2>&1 || true
  gradle -i :app:assembleDebug
fi

echo "✅ Regel-Update aktiv: Glanzpflicht oben (Oberschenkel), Weißsocken darüber, Muster optional. APK unter app/build/outputs/apk/debug/"
