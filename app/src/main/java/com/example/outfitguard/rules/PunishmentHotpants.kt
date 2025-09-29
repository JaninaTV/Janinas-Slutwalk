package com.example.outfitguard.rules

object PunishmentHotpants {
    fun apply(req: SessionRequirements) = req.apply {
        allowPantsException = true
        pantsPantyOnly = true
        pantsMustNotCoverButt = true
        thighsMustBeFullyFree = true

        hosieryMandatory = true
        heelsMinCm = maxOf(heelsMinCm, 14)
        noPlateau = true
        frozen = true
    }
}
