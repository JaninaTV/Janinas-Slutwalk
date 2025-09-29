package com.example.outfitguard.rules

data class SessionRequirements(
    // Panty-Hotpants
    var allowPantsException: Boolean = false,
    var pantsPantyOnly: Boolean = false,
    var pantsMustNotCoverButt: Boolean = false,
    var thighsMustBeFullyFree: Boolean = false,

    // Nano-Minirock
    var nanoSkirtActive: Boolean = false,
    var buttCoverMaxPercent: Int = 0,

    // Cutout-Minirock
    var cutoutSkirtActive: Boolean = false,
    var cutoutSizeMinPercent: Int = 0,   // wie groß müssen Cutouts sein
    var movementDuty: Boolean = false,

    // Gemeinsame Pflichten
    var hosieryMandatory: Boolean = true,
    var hosieryBlackGlossRecommended: Boolean = true,
    var heelsMinCm: Int = 14,
    var noPlateau: Boolean = true,

    var frozen: Boolean = false
)
