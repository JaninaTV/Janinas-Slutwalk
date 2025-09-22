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
