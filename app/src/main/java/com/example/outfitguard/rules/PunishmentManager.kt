package com.example.outfitguard.rules

import com.example.outfitguard.integration.TaskerBridge

enum class PunishmentMode { NONE, PANTY, NANO, CUTOUT }

class PunishmentManager {
    val req = SessionRequirements()
    var mode: PunishmentMode = PunishmentMode.NONE

    fun startPanty() { mode = PunishmentMode.PANTY; PunishmentHotpants.apply(req) }
    fun startNano() { mode = PunishmentMode.NANO; PunishmentNanoSkirt.apply(req, 50) }
    fun startCutout() { mode = PunishmentMode.CUTOUT; PunishmentCutoutSkirt.apply(req, 30) }

    fun check(input: OutfitInput): OutfitCheckResult {
        val v = mutableListOf<String>()

        when (mode) {
            PunishmentMode.PANTY -> {
                if (input.pantsType != "PANTY") v += "Nur Panty-Hotpants erlaubt"
                if (input.buttCoveredByPants) v += "Po darf nicht bedeckt sein"
                if (!input.thighsFullyFree) v += "Oberschenkel müssen frei sein"
            }
            PunishmentMode.NANO -> {
                if (input.buttCoverPercent > req.buttCoverMaxPercent) {
                    v += "Po-Bedeckung zu hoch (${input.buttCoverPercent}% > erlaubt ${req.buttCoverMaxPercent}%)"
                }
            }
            PunishmentMode.CUTOUT -> {
                if (input.cutoutPercent < req.cutoutSizeMinPercent) {
                    v += "Cutout zu klein (${input.cutoutPercent}% < min ${req.cutoutSizeMinPercent}%)"
                }
                if (req.movementDuty && !input.movedRecently) {
                    v += "Bewegungspflicht verletzt"
                }
            }
            else -> {}
        }

        // Gemeinsam
        if (req.hosieryMandatory && !input.hosieryPresent) v += "Strumpfhose Pflicht"
        if (input.heelHeightCm < req.heelsMinCm) v += "Absatz zu niedrig"
        if (req.noPlateau && input.plateauDetected) v += "Plateau verboten"

        val ok = v.isEmpty()
        if (!ok) {
            TaskerBridge.send("OUTFIT", v.joinToString("; "), 70, "mode=$mode")
        }
        return OutfitCheckResult(ok, v)
    }
}
