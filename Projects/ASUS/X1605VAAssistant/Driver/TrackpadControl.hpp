#pragma once
// Typed bool query arguments match VoodooI2CHID's kKeyboardGetTouchStatus ABI.
// The caller retains the matched service for the duration of these calls.
static inline bool AsusSupportedTrackpadClass(const char *name) {
    return name && (!strcmp(name, "VoodooI2CPrecisionTouchpadHIDEventDriver") ||
                    !strcmp(name, "VoodooI2CMultitouchHIDEventDriver"));
}
// Reads use VoodooI2C's typed query. Writes only evaluate the ACPI notification
// endpoint once. The returned write value acknowledges a request, not completion.
template<typename Target, typename Provider, typename Endpoint>
IOReturn AsusApplyTrackpadState(Target *target, Provider *provider, Endpoint *acpi,
                                bool write, bool enabled, bool *result) {
    bool state = false;
    IOReturn rc = target->message(iokit_vendor_specific_msg(101), provider, &state);
    if (rc != kIOReturnSuccess) return rc;
    if (write && state != enabled) {
        UInt32 reply = 0xFF;
        rc = acpi->evaluateInteger("TTPD", &reply);
        if (rc != kIOReturnSuccess) return rc;
        if (reply != 0) return kIOReturnError;
    }
    *result = write ? enabled : state;
    return kIOReturnSuccess;
}
