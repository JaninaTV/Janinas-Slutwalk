package com.example.outfitguardian.outfit

import android.content.Context
import android.graphics.BitmapFactory
import com.example.outfitguardian.integration.tasker.TaskerEvents
import com.example.outfitguardian.util.QualityGate
import com.example.outfitguardian.util.BackgroundHash
import com.example.outfitguardian.rules.OutfitPresetStore
import com.example.outfitguardian.outfit.PresetHeuristics
import com.example.outfitguardian.rules.OutfitRequirements
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.max

data class ReferenceProfile(
    val socks: RegionFeatures,
    val legs: RegionFeatures,
    val shoes: RegionFeatures,
    val hemY: Int,
    val eyeSat: Float,
    val eyesDarkFrac: Float,
    val whiteSockMinRatio: Float = 0.35f,
    val hueMin: Float = 0.92f,
    val edgeTol: Float = 0.10f
)

object OutfitCheckManager {
    private const val PREF = "outfit_ref_v2"
    private const val KEY_REF_JSON = "ref_json"
    private const val KEY_COUNT = "ref_count"
    private const val KEY_FAIL_STREAK = "fail_streak"
    private const val KEY_OPEN_VIOLATION = "open_violation"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun refCount(ctx: Context) = prefs(ctx).getInt(KEY_COUNT, 0)
    fun hasReference(ctx: Context) = prefs(ctx).contains(KEY_REF_JSON)

    // Speichert Referenzprofil aus Bitmap (erste Bilder)
    fun storeReferenceBitmap(ctx: Context, path: String) {
        val bmp = BitmapFactory.decodeFile(path) ?: return
        val ff = OutfitHeuristics.frameFeatures(bmp)
        val prof = ReferenceProfile(
            socks = ff.socks,
            legs = ff.legs,
            shoes = ff.shoes,
            hemY = ff.hemY,
            eyeSat = ff.eyeSat,
            eyesDarkFrac = ff.eyesLumaDarkFrac
        )
        prefs(ctx).edit()
            .putString(KEY_REF_JSON, toJson(prof).toString())
            .putInt(KEY_COUNT, (refCount(ctx) + 1).coerceAtMost(50))
            .apply()
    }

    // Hauptprüfung gegen Referenz, inklusive Hysterese und Tasker-Events
    fun checkBitmap(ctx: Context, path: String): Pair<Boolean, List<String>> {
        val bmp = BitmapFactory.decodeFile(path) ?: return false to listOf("Bild defekt")
        val ref = getRef(ctx) ?: return false to listOf("Keine Referenz")
        val ff = OutfitHeuristics.frameFeatures(bmp)

        val reasons = mutableListOf<String>()

        // HEEL_PRECISION_ENFORCE: ±0,5 cm gegen Referenz
        try {
          val need = com.example.outfitguardian.rules.HeelsMonotony.required(ctx)
          if (need > 0f) {
            val have = OutfitHeuristics.estimateHeelHeightCm(bmp)
            if (have + 0.5f < need) {
              reasons += "Absatz zu niedrig (Pflicht: ≥ %.1f cm, erkannt: %.1f cm)".format(need, have)
            }
          }
        } catch (_:Throwable) {}


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

        // 1) Socken weiß genug
        val whiteFrac = OutfitHeuristics.whiteRatioSocks(bmp)
        if (whiteFrac < ref.whiteSockMinRatio) reasons += "Socken nicht weiß genug (${(whiteFrac*100).toInt()}%)"

        // 2) Tights nicht hautfarben (heuristisch: Hue-Ähnlichkeit zu Referenz-Bein muss hoch UND Sättigung über Baseline)
        val hueLegSim = OutfitHeuristics.cosine(ff.legs.hueHist, ref.legs.hueHist)
        if (hueLegSim < ref.hueMin) reasons += "Beinkleid weicht farblich stark ab"
        val edgeLegDelta = abs(ff.legs.edgeRate - ref.legs.edgeRate)
        if (edgeLegDelta > ref.edgeTol) reasons += "Textur Beine abweichend"

        // 3) Heels grob „hoch“
        if (!OutfitHeuristics.heelLikelyHigh(bmp)) reasons += "High Heels nicht eindeutig"

        // 4) Saum nicht länger als erlaubt (+6px Toleranz, monotone Regel: strengster bisher)
        val hemOk = ff.hemY <= ref.hemY + 6
        if (!hemOk) reasons += "Saum länger als Referenz/Pflicht"

        // 5) Augen-Make-up sichtbar (Sättigung und dunkler Anteil nicht deutlich unter Referenz)
        if (ff.eyeSat + 0.05f < ref.eyeSat || ff.eyesDarkFrac + 0.05f < ref.eyesDarkFrac) {
            reasons += "Augen-Make-up schwach"
        }

        // Score (weighed quick check)
        val scoreHue =
            0.25f*OutfitHeuristics.cosine(ff.legs.hueHist, ref.legs.hueHist) +
            0.20f*OutfitHeuristics.cosine(ff.socks.hueHist, ref.socks.hueHist) +
            0.20f*OutfitHeuristics.cosine(ff.shoes.hueHist, ref.shoes.hueHist) +
            0.25f*(if (hemOk) 1f else 0f) +
            0.10f*(if (ff.eyeSat >= ref.eyeSat && ff.eyesLumaDarkFrac >= ref.eyesDarkFrac) 1f else 0f)

        
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
        val pass = scoreHue >= 0.90f && reasons.isEmpty()

        handleHysteresisAndTasker(ctx, pass, reasons)

        return pass to reasons
    }

    private fun handleHysteresisAndTasker(ctx: Context, pass: Boolean, reasons: List<String>) {
        val p = prefs(ctx)
        var streak = p.getInt(KEY_FAIL_STREAK, 0)
        var open = p.getString(KEY_OPEN_VIOLATION, null)

        if (pass) {
            // Bewegungsauflage nach Outfitcheck
            try { com.example.outfitguardian.MainActivity::class.java.getMethod("onOutfitCheckPassedBridge").invoke(null) } catch (_:Throwable){}
            // Ende bei erstem Pass
            if (open != null) {
                TaskerEvents.endViolation(ctx, "auto", TaskerEvents.Type.OUTFIT, "Outfit wieder passend")
                open = null
            }
            streak = 0
        } else {
            streak += 1
            if (streak >= 2 && open == null) {
                val msg = "Nachbesserungspflicht: " + reasons.joinToString("; ").take(160)
                val id = TaskerEvents.startViolation(ctx, TaskerEvents.Type.OUTFIT, 45, msg)
                open = id
            }
        }

        p.edit().putInt(KEY_FAIL_STREAK, streak).apply()
        if (open == null) p.edit().remove(KEY_OPEN_VIOLATION).apply()
        else p.edit().putString(KEY_OPEN_VIOLATION, open).apply()
    }

    private fun toJson(r: ReferenceProfile): JSONObject {
        fun arr(f: FloatArray) = JSONArray().apply { f.forEach { put(it) } }
        val o = JSONObject()
        o.put("socks_hist", arr(r.socks.hueHist))
        o.put("socks_edge", r.socks.edgeRate)
        o.put("legs_hist", arr(r.legs.hueHist))
        o.put("legs_edge", r.legs.edgeRate)
        o.put("shoes_hist", arr(r.shoes.hueHist))
        o.put("shoes_edge", r.shoes.edgeRate)
        o.put("hemY", r.hemY)
        o.put("eyeSat", r.eyeSat)
        o.put("eyesDark", r.eyesDarkFrac)
        o.put("whiteMin", r.whiteSockMinRatio)
        o.put("hueMin", r.hueMin)
        o.put("edgeTol", r.edgeTol)
        return o
    }

    private fun fromJson(o: JSONObject): ReferenceProfile {
        fun arr(name: String): FloatArray {
            val a = o.getJSONArray(name)
            return FloatArray(a.length()) { i -> a.getDouble(i).toFloat() }
        }
        val socks = RegionFeatures(arr("socks_hist"), o.getDouble("socks_edge").toFloat())
        val legs  = RegionFeatures(arr("legs_hist"),  o.getDouble("legs_edge").toFloat())
        val shoes = RegionFeatures(arr("shoes_hist"), o.getDouble("shoes_edge").toFloat())
        return ReferenceProfile(
            socks = socks,
            legs = legs,
            shoes = shoes,
            hemY = o.getInt("hemY"),
            eyeSat = o.getDouble("eyeSat").toFloat(),
            eyesDarkFrac = o.getDouble("eyesDark").toFloat(),
            whiteSockMinRatio = o.getDouble("whiteMin").toFloat(),
            hueMin = o.getDouble("hueMin").toFloat(),
            edgeTol = o.getDouble("edgeTol").toFloat()
        )
    }

    private fun getRef(ctx: Context): ReferenceProfile? {
        val s = prefs(ctx).getString(KEY_REF_JSON, null) ?: return null
        return fromJson(JSONObject(s))
    }
}


    private fun intentRefMode(): Boolean {
        return try { (lastCaptureIntent?.getBooleanExtra("ref_mode", false) ?: false) } catch (_:Throwable) { false }
    }
