#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.example.outfitguardian"
PKG="app/src/main/java/${APP_ID//.//}"
RES="app/src/main/res"

echo "==> Regeln: OutfitPreset speichern/lesen (fix ab Sessionstart)"
mkdir -p "$PKG/rules"
cat > "$PKG/rules/OutfitPreset.kt" <<'KOT'
package com.example.outfitguardian.rules

import android.content.Context
import org.json.JSONObject

data class OutfitPreset(
  val enabled: Boolean = false,
  val name: String = "Tartan-Set",
  val heelMinCm: Int = 10,
  val colorsTopAllowed: Set<String> = setOf("white","red","black"),
  val colorsOuterAllowed: Set<String> = setOf("white","red","black")
)

object OutfitPresetStore {
  private const val PREF="outfit_preset"
  private const val KEY_JSON="preset_json"
  private const val KEY_FROZEN="preset_frozen"

  fun save(ctx: Context, preset: OutfitPreset) {
    val o = JSONObject()
      .put("enabled", preset.enabled)
      .put("name", preset.name)
      .put("heelMinCm", preset.heelMinCm)
      .put("colorsTop", preset.colorsTopAllowed.joinToString(","))
      .put("colorsOuter", preset.colorsOuterAllowed.joinToString(","))
    ctx.getSharedPreferences(PREF,0).edit().putString(KEY_JSON, o.toString()).apply()
  }
  fun load(ctx: Context): OutfitPreset? {
    val s = ctx.getSharedPreferences(PREF,0).getString(KEY_JSON, null) ?: return null
    val o = JSONObject(s)
    return OutfitPreset(
      enabled = o.optBoolean("enabled", false),
      name = o.optString("name","Tartan-Set"),
      heelMinCm = o.optInt("heelMinCm", 10),
      colorsTopAllowed = o.optString("colorsTop","white,red,black").split(",").map{it.trim()}.toSet(),
      colorsOuterAllowed = o.optString("colorsOuter","white,red,black").split(",").map{it.trim()}.toSet()
    )
  }
  fun freeze(ctx: Context) { ctx.getSharedPreferences(PREF,0).edit().putBoolean(KEY_FROZEN,true).apply() }
  fun unfreeze(ctx: Context) { ctx.getSharedPreferences(PREF,0).edit().putBoolean(KEY_FROZEN,false).apply() }
  fun isFrozen(ctx: Context) = ctx.getSharedPreferences(PREF,0).getBoolean(KEY_FROZEN,false)
}
KOT

echo "==> Simple UI: Preset-Auswahl in MainActivity (vor Start, danach gesperrt)"
mkdir -p "$RES/layout"
# Minimaler Block in activity_main ergänzen: zwei Buttons + Status
python3 - <<'PY'
from pathlib import Path, re as _re
p=Path("app/src/main/res/layout/activity_main.xml")
if p.exists():
  s=p.read_text()
  if "btnPresetEnable" not in s:
    s = s.replace("</LinearLayout>", """
    <LinearLayout
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:orientation="horizontal"
      android:padding="8dp">
      <Button
        android:id="@+id/btnPresetEnable"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:text="Pflichtoutfit aktivieren"/>
      <Button
        android:id="@+id/btnPresetDisable"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:text="Pflichtoutfit deaktivieren"/>
    </LinearLayout>
    <TextView
      android:id="@+id/tvPreset"
      android:layout_width="match_parent"
      android:layout_height="wrap_content"
      android:padding="8dp"
      android:text="Pflichtoutfit: aus"/> 
</LinearLayout>
""")
    p.write_text(s)
print("layout patched")
PY

# MainActivity: Buttons verdrahten, Freeze/Unfreeze an Sessionstart/-ende
python3 - <<'PY'
from pathlib import Path, re
p=Path("app/src/main/java/com/example/outfitguardian/MainActivity.kt")
src=p.read_text()
if "OutfitPresetStore" not in src:
  src = src.replace("import com.example.outfitguardian.security.SessionGuard",
                    "import com.example.outfitguardian.security.SessionGuard\nimport com.example.outfitguardian.rules.OutfitPreset\nimport com.example.outfitguardian.rules.OutfitPresetStore\nimport com.example.outfitguardian.rules.OutfitRequirements")
if "btnPresetEnable" not in src:
  src = src.replace("setContentView(R.layout.activity_main)",
r"""setContentView(R.layout.activity_main)
    // Preset Buttons
    findViewById<Button>(R.id.btnPresetEnable)?.setOnClickListener {
      if (SessionGuard.isActive(this) || OutfitPresetStore.isFrozen(this)) { toast("Während aktiver Session gesperrt."); return@setOnClickListener }
      val p = OutfitPreset(enabled=true, heelMinCm=10)
      OutfitPresetStore.save(this, p)
      OutfitRequirements.setHeelMinCm(this, p.heelMinCm)
      findViewById<TextView>(R.id.tvPreset)?.text = "Pflichtoutfit: " + p.name
      toast("Pflichtoutfit aktiviert")
    }
    findViewById<Button>(R.id.btnPresetDisable)?.setOnClickListener {
      if (SessionGuard.isActive(this) || OutfitPresetStore.isFrozen(this)) { toast("Während aktiver Session gesperrt."); return@setOnClickListener }
      OutfitPresetStore.save(this, OutfitPreset(enabled=false))
      findViewById<TextView>(R.id.tvPreset)?.text = "Pflichtoutfit: aus"
      toast("Pflichtoutfit deaktiviert")
    }
""")
# Freeze beim Start
src = re.sub(r'SessionGuard\.startSession\(this, pin\)\n\s*startForegroundSession\(\)\n',
             r'SessionGuard.startSession(this, pin)\n      com.example.outfitguardian.rules.OutfitPresetStore.freeze(this)\n      startForegroundSession()\n',
             src)
# Unfreeze beim Stop
src = src.replace('stopForegroundSession(); getSharedPreferences("session_flags"',
                  'stopForegroundSession(); com.example.outfitguardian.rules.OutfitPresetStore.unfreeze(this); getSharedPreferences("session_flags"')
p.write_text(src)
print("MainActivity patched")
PY

echo "==> Heuristiken für Pflicht-Set: Tartan, Glanz-Tights, weiße Socken, schwarze Lack-Pumps, Hoodie/Outer Farben, Pigtails, rote Lippen"
cat > "$PKG/outfit/PresetHeuristics.kt" <<'KOT'
package com.example.outfitguardian.outfit

import android.graphics.Bitmap
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object PresetHeuristics {

  // Minirock Tartan rot: grob Rotdominanz + Gitternetz-Kanten
  fun isTartanRed(bmp: Bitmap): Boolean {
    val r = OutfitHeuristics.regions(bmp).hemStripe
    val step = max(1, min(r.width(), r.height())/128)
    var reds=0; var tot=0; var grid=0
    var y=r.top
    while (y<r.bottom-step) {
      var x=r.left
      while (x<r.right-step) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        if (R>G+15 && R>B+15) reds++
        val c2=bmp.getPixel(x+step,y)
        val c3=bmp.getPixel(x,y+step)
        val l = (R*299 + G*587 + B*114)/1000
        val l2=((c2 shr 16 and 0xFF)*299 + (c2 shr 8 and 0xFF)*587 + (c2 and 0xFF)*114)/1000
        val l3=((c3 shr 16 and 0xFF)*299 + (c3 shr 8 and 0xFF)*587 + (c3 and 0xFF)*114)/1000
        if (abs(l-l2)>28) grid++
        if (abs(l-l3)>28) grid++
        tot++; x+=step
      }
      y+=step
    }
    val redFrac = if (tot==0) 0f else reds.toFloat()/tot
    val gridRate = if (tot==0) 0f else grid.toFloat()/(tot*2)
    return redFrac>0.25f && gridRate>0.12f
  }

  // Schwarze glänzende Strumpfhose 40–80 den: sehr dunkle V mit spekularen Spots
  fun isBlackGlossyTights(bmp: Bitmap): Boolean {
    val regs = OutfitHeuristics.regions(bmp)
    val legs = Rect(regs.socks.left, (bmp.height*0.50f).toInt(), regs.socks.right, regs.socks.bottom)
    var dark=0; var bright=0; var tot=0
    val step = max(1, min(legs.width(), legs.height())/128)
    var y=legs.top
    while (y<legs.bottom) {
      var x=legs.left
      while (x<legs.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R,min(G,B)).toFloat()
        val v = mx/255f; val s = if (mx==0f) 0f else 1f-(mn/mx)
        if (v<0.22f) dark++              // sehr dunkel
        if (v>0.55f && s<0.25f) bright++ // glänzende Spots
        tot++; x+=step
      }
      y+=step
    }
    val darkFrac = if (tot==0) 0f else dark.toFloat()/tot
    val specFrac = if (tot==0) 0f else bright.toFloat()/tot
    return darkFrac>0.55f && specFrac>0.02f
  }

  // Weiße Kniestrümpfe / Rüschensocken
  fun whiteSocks(bmp: Bitmap): Boolean {
    return OutfitHeuristics.whiteRatioSocks(bmp) >= 0.35f
  }

  // Schwarze Patent-Pumps (Lack) ohne Plateau, Höhe >= Pflicht (separat geprüft)
  fun blackPatentPumps(bmp: Bitmap): Boolean {
    val r = OutfitHeuristics.regions(bmp).shoes
    val f = OutfitHeuristics.regionFeatures(bmp, r)
    // "schwarz" = niedrige V im Median; "Patent" = hohe edgeRate + helle Reflexpunkte
    val step = max(1, min(r.width(), r.height())/96)
    var tot=0; var bright=0; var veryDark=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R, min(G,B)).toFloat()
        val v = mx/255f; val s = if (mx==0f) 0f else 1f - (mn/mx)
        if (v<0.20f) veryDark++
        if (v>0.70f && s<0.20f) bright++
        tot++; x+=step
      }
      y+=step
    }
    val darkFrac = if (tot==0) 0f else veryDark.toFloat()/tot
    val specFrac = if (tot==0) 0f else bright.toFloat()/tot
    return darkFrac>0.20f && specFrac>0.02f && f.edgeRate>0.17f
  }

  // Hoodie/Oberteil in erlaubten Farben (weiß/rot/schwarz)
  fun topAllowedColor(bmp: Bitmap, allowed:Set<String>): Boolean {
    val r = OutfitHeuristics.regions(bmp).torsoStripe
    val step = max(1, min(r.width(), r.height())/128)
    var white=0; var red=0; var black=0; var tot=0
    var y=r.top
    while (y<r.bottom) {
      var x=r.left
      while (x<r.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val mx = max(R, max(G,B)).toFloat(); val mn=min(R, min(G,B)).toFloat()
        val v=mx/255f; val s= if (mx==0f) 0f else 1f-(mn/mx)
        if (v>0.85f && s<0.25f) white++
        if (R>G+15 && R>B+15) red++
        if (v<0.25f) black++
        tot++; x+=step
      }
      y+=step
    }
    val best = listOf("white" to white, "red" to red, "black" to black).maxBy { it.second }.first
    return allowed.contains(best)
  }

  // Pigtails: grob zwei dunkle Haar-Massen links/rechts oben
  fun pigtailsLikely(bmp: Bitmap): Boolean {
    val w=bmp.width; val h=bmp.height
    val topBand = Rect((w*0.05f).toInt(), (h*0.05f).toInt(), (w*0.95f).toInt(), (h*0.30f).toInt())
    val midX = w/2
    var leftDark=0; var rightDark=0; var totL=0; var totR=0
    val step = max(1, min(topBand.width(), topBand.height())/128)
    var y=topBand.top
    while (y<topBand.bottom) {
      var x=topBand.left
      while (x<topBand.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        val v = max(R, max(G,B))/255f
        if (x<midX) { totL++; if (v<0.25f) leftDark++ } else { totR++; if (v<0.25f) rightDark++ }
        x+=step
      }
      y+=step
    }
    val l = if (totL==0) 0f else leftDark.toFloat()/totL
    val r = if (totR==0) 0f else rightDark.toFloat()/totR
    return l>0.25f && r>0.25f
  }

  // Lippen rot + Augen dunkel
  fun lipsRedAndEyesDark(bmp: Bitmap): Boolean {
    val w=bmp.width; val h=bmp.height
    val mouth = Rect((w*0.40f).toInt(), (h*0.35f).toInt(), (w*0.60f).toInt(), (h*0.45f).toInt())
    val eyes = OutfitHeuristics.regions(bmp).eyes
    // Lippen rot
    var redPix=0; var totM=0
    val stepM = max(1, min(mouth.width(), mouth.height())/48)
    var y=mouth.top
    while (y<mouth.bottom) {
      var x=mouth.left
      while (x<mouth.right) {
        val c=bmp.getPixel(x,y)
        val R=(c shr 16) and 0xFF; val G=(c shr 8) and 0xFF; val B=c and 0xFF
        if (R>G+25 && R>B+25) redPix++
        totM++; x+=stepM
      }
      y+=stepM
    }
    val lipOk = totM>0 && redPix.toFloat()/totM > 0.12f
    // Augen dunkel: reuse Heuristic
    val pair = OutfitHeuristics.eyeMakeupSignals(bmp)
    val eyesDarkOK = pair.second > 0.15f
    return lipOk && eyesDarkOK
  }
}
KOT

echo "==> OutfitCheckManager erweitern: Pflicht-Set prüfen + Saum-Monotonie nur noch strenger"
python3 - "$PKG/outfit/OutfitCheckManager.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
if "PresetHeuristics" not in s:
  s = s.replace("import com.example.outfitguardian.integration.tasker.TaskerEvents",
                "import com.example.outfitguardian.integration.tasker.TaskerEvents\nimport com.example.outfitguardian.rules.OutfitPresetStore\nimport com.example.outfitguardian.outfit.PresetHeuristics\nimport com.example.outfitguardian.rules.OutfitRequirements")
# Saum stricter wenn Preset enabled (Monotonie schon vorhanden, aber Fehlergrund anpassen)
s = s.replace('if (!hemOk) reasons += "Saum länger als Referenz"',
              'if (!hemOk) reasons += "Saum länger als Referenz/Pflicht"')

# Nach bisheriger Prüfung: zusätzliche Pflichtprüfungen einhängen, wenn Preset aktiv
hook = 'val pass = scoreHue >= 0.90f && reasons.isEmpty()'
if "Preset extra checks" not in s:
  s = s.replace(hook, r'''
        // Preset extra checks (nur wenn aktiv)
        OutfitPresetStore.load(ctx)?.let { preset ->
          if (preset.enabled) {
            // Rock/Kleid: Tartan rot
            if (!PresetHeuristics.isTartanRed(bmp)) reasons += "Rock/Kleid nicht Tartan-rot"
            // Strumpfhose: schwarz glänzend
            if (!PresetHeuristics.isBlackGlossyTights(bmp)) reasons += "Strumpfhose nicht schwarz/glänzend"
            // Socken: weiß
            if (!PresetHeuristics.whiteSocks(bmp)) reasons += "Socken nicht weiß"
            // Schuhe: schwarze Patent-Pumps
            if (!PresetHeuristics.blackPatentPumps(bmp)) reasons += "Pumps nicht schwarz/lack"
            // Absatzpflicht (mind. Vorgabe)
            val req = OutfitRequirements.getHeelMinCm(ctx).coerceAtLeast(preset.heelMinCm)
            val bmpSide = android.graphics.BitmapFactory.decodeFile(path) // Fallback: gleicher Frame, heuristisch
            if (bmpSide!=null) {
              val cm = OutfitHeuristics.regionFeatures(bmpSide, OutfitHeuristics.regions(bmpSide).shoes).edgeRate // Platzhalter
            }
            // Oberteil: erlaubt (weiß/rot/schwarz)
            if (!PresetHeuristics.topAllowedColor(bmp, preset.colorsTopAllowed)) reasons += "Oberteil-Farbe nicht erlaubt"
            // Pigtails + Lippen/Augen
            if (!PresetHeuristics.pigtailsLikely(bmp)) reasons += "Frisur: Pigtails nicht erkannt"
            if (!PresetHeuristics.lipsRedAndEyesDark(bmp)) reasons += "Make-up (rote Lippen/dunkle Augen) fehlt"
          }
        }
        val pass = scoreHue >= 0.90f && reasons.isEmpty()''')
p.write_text(s); print("OutfitCheckManager patched")
PY

echo "==> DualOutfitCheckManager: Absatzpflicht >=10 cm bei Preset & Plateauverbot weiter prüfen"
python3 - "$PKG/outfit/DualOutfitCheckManager.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
if "OutfitPresetStore" not in s:
  s = s.replace("import com.example.outfitguardian.rules.OutfitRequirements",
                "import com.example.outfitguardian.rules.OutfitRequirements\nimport com.example.outfitguardian.rules.OutfitPresetStore")
# Nach heelsOk prüfen wir Pflicht vs Preset
s = s.replace('val pass = reasons.isEmpty()',
              'OutfitPresetStore.load(ctx)?.let{ if (it.enabled && !heelsOk) reasons += "Absatz < Pflicht" }\n    val pass = reasons.isEmpty()')
p.write_text(s); print("DualOutfitCheckManager patched")
PY

echo "==> Hinweistext in AutoCameraActivity etwas strenger"
python3 - "$PKG/AutoCameraActivity.kt" <<'PY'
import sys, pathlib, re
p=pathlib.Path(sys.argv[1]); s=p.read_text()
s = s.replace('tvHint.text = "Seitenprofil – bitte seitlich drehen (Foto in 5s)"',
              'tvHint.text = "Seitenprofil – bitte seitlich drehen (Foto in 5s). Pumps sichtbar, Socken weiß, Saum frei."')
p.write_text(s); print("AutoCameraActivity hint patched")
PY

echo "==> Build"
./gradlew --stop >/dev/null 2>&1 || true
./gradlew clean :app:assembleDebug
