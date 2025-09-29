package com.example.outfitguard.rules

object PunishmentCutoutSkirt {
    fun apply(req: SessionRequirements, minCutoutPercent: Int = 30) = req.apply {
        cutoutSkirtActive = true
        cutoutSizeMinPercent = minCutoutPercent
        hosieryMandatory = true
        heelsMinCm = maxOf(heelsMinCm, 14)
        noPlateau = true
        movementDuty = true
        frozen = true
    }
}
