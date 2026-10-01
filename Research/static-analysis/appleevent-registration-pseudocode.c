/* Curated explanatory pseudocode, NOT extracted source or compilable product.
 * Build: Logic 12.3.1 (6682), Logic.framework arm64.
 * Exact proof: appleevent-registration.asm and registration.md.
 * API prototypes were corrected from the installed Carbon/AE SDK in Ghidra.
 * Guarded static-object initialization and stack protection are omitted.
 */

/* 0x004f11dc..0x004f11fc */
AEInstallEventHandler('aUeV', 'Spt2', handler_00590e30, NULL, false);

/* 0x017ccab8..0x017ccb08, FeatureAvailable(4) guard. */
[NSAppleEventManager.sharedAppleEventManager
    setEventHandler:appManager
    andSelector:@selector(handleGetURLEvent:withReplyEvent:)
    forEventClass:'GURL' andEventID:'GURL'];

/* Numeric table proven from file-backed Mach-O address 0x01cbeb70. */
static const int16_t command_for_positive_sPkc[15] = {
    0, 5, 535, 10, 11, 12, 13, 7, 1272, 1273, 4, 3, 14, 754, 753
};

/* Relevant subset of handler @ 0x00590e30. */
OSErr handler_00590e30(const AppleEvent *event, AppleEvent *reply, SRefCon refcon)
{
    void *owner = *(void **)0x0276de68;
    void *song;
    DescType actualType;
    Size size;
    int32_t mode, kc;
    OSErr status;

    /* Semantic +0xc0 proved by two named song/currentSong getters. */
    if (!owner || !(song = *(void **)((uint8_t *)owner + 0xc0)))
        return -38;

    status = AESizeOfParam(event, 'sPmo', &actualType, &size);
    if (status != 0 || actualType != 'long')
        return status; /* Wrong type with a present parameter returns ZERO. */
    status = AEGetParamPtr(event, 'sPmo', 'long', &actualType,
                          &global_02633d60, size, &size);
    if (status != 0)
        return status;
    mode = global_02633d60;

    if (mode == 6) {
        kc = 0;
        status = AESizeOfParam(event, 'sPkc', &actualType, &size);
        if (status != 0 || actualType != 'long')
            return status;
        status = AEGetParamPtr(event, 'sPkc', 'long', &actualType, &kc, size, &size);
        if (status != 0)
            return status;

        int16_t command;
        if (kc < 0) {
            /* Exact neg w8; sxth w0. Unsigned math expresses modulo-32
             * behavior without inventing C signed-overflow semantics. */
            command = (int16_t)(0u - (uint32_t)kc);
        } else {
            /* Exact unsigned sub/cmn predicate is equivalent on this branch. */
            if (!(1 <= kc && kc <= 14))
                return 0;
            command = command_for_positive_sPkc[kc];
        }
        FUN_008663d4(command, song, 0, 2, 0);
        return 0; /* Does not encode dispatcher success. */
    }

    if (mode == 4) {
        int32_t value_sr = FUN_003b1c58(song);
        int8_t raw_fr = *(int8_t *)((uint8_t *)song + 0xc4);
        int32_t value_fr = raw_fr < 0 ? 0 : raw_fr > 11 ? 11 : raw_fr;
        if (reply->descriptorType == 'null')
            return 0;
        status = AEPutParamPtr(reply, 'sPsr', 'long', &value_sr, 4);
        if (status != 0) return status;
        status = AEPutParamPtr(reply, 'sPfr', 'long', &value_fr, 4);
        if (status != 0) return status;
        FUN_010e3628(song, -1, 0); /* Potential tempo-state writes. */
        void *internalValue = FUN_019ae630(song, 3, 0, 0);
        CFStringRef string = FUN_01079a2c(song, *(int32_t *)((uint8_t *)internalValue + 0x18));
        /* Convert full string to UTF-8 with CFStringGetBytes. */
        if (converted_character_count & 0xff)
            return AEPutParamPtr(reply, 'sPso', 'utf8', utf8_bytes, byte_count);
        return 0;
    }

    /* Remaining file/text branches are mapped in registration.md.
     * No claim that other modes are safe, read-only, or complete follows. */
    return remaining_mode_specific_branch(event, reply, mode, song);
}
