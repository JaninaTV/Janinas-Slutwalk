package com.example.outfitguardian.rules

data class OutfitInput(
  val skirtOrDress: Boolean,
  val lengthAboveKneeCm: Int?,      // z.B. 10 bedeutet 10 cm über Knie
  val tightsOrStockingsVisible: Boolean,
  val tightsColorIsSkin: Boolean,
  val kneeSocksOrRufflesWhiteOver: Boolean, // optional
  val heelHeightCm: Int?,
  val eyeMakeupClearlyVisible: Boolean
)

data class RuleResult(val ok: Boolean, val messages: List<String>)

object OutfitRules {
  fun check(inpt: OutfitInput): RuleResult {
    val msgs = mutableListOf<String>()

    if (!inpt.skirtOrDress) msgs += "Rock/Kleid ist Pflicht."
    if ((inpt.lengthAboveKneeCm ?: 999) > 10) msgs += "Maximale Länge: ~10 cm über Knie."
    if (!inpt.tightsOrStockingsVisible) msgs += "Strumpfhose/Halterlose müssen sichtbar sein."
    if (inpt.tightsColorIsSkin) msgs += "Hautfarbene Strumpfhose ist verboten."
    if ((inpt.heelHeightCm ?: 0) < 8) msgs += "High Heels mind. 8 cm Absatz sind Pflicht."
    if (!inpt.eyeMakeupClearlyVisible) msgs += "Augen-Make-up muss deutlich erkennbar sein."

    // Weißer Kontrast (optional) – Hinweis, nicht Pflicht
    if (!inpt.kneeSocksOrRufflesWhiteOver) {
      msgs += "Tipp: Weiße Kniestrümpfe/Rüschensocken über Strumpfhose erhöhen Sichtbarkeit (optional)."
    }

    return RuleResult(msgs.isEmpty(), msgs)
  }
}
