package com.example.outfitguardian.rules

import android.content.Context
import org.json.JSONObject

data class OutfitPreset(
  val enabled: Boolean = false,
  val name: String = "Tartan-Set",
  val heelMinCm: Int = 10,
  val colorsTopAllowed: Set<String> = setOf("white","red","black"),
  val colorsOuterAllowed: Set<String> = setOf("white","red","black"),
  val minFastenerScore: Float = 0.40f,
  val requireClosedHeelCounter: Boolean = true,
  val forbidSlipOns: Boolean = true
)
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
      colorsOuterAllowed = o.optString("colorsOuter","white,red,black").split(",").map{it.trim()}.toSet(),
      minFastenerScore = o.optDouble("minFastenerScore", 0.40).toFloat(),
      requireClosedHeelCounter = o.optBoolean("requireClosedHeelCounter", true),
      forbidSlipOns = o.optBoolean("forbidSlipOns", true)
    )
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
