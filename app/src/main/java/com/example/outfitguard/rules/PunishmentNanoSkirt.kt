package com.example.outfitguard.rules

object PunishmentNanoSkirt {
    fun apply(req: SessionRequirements, maxButtCoverPercent: Int = 50) = req.apply {
        nanoSkirtActive = true
        buttCoverMaxPercent = maxButtCoverPercent
        hosieryMandatory = true
        heelsMinCm = maxOf(heelsMinCm, 14)
        noPlateau = true
        frozen = true
    }
}
