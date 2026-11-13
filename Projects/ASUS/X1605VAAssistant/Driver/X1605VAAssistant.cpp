// X1605VAAssistant — samuelnotfound (https://github.com/samuelnotfound)
#include "X1605VAAssistant.hpp"
#include <IOKit/IOMessage.h>
#include <libkern/libkern.h>
#include "TrackpadControl.hpp"

#define super IOService
OSDefineMetaClassAndStructors(X1605VAAssistant, IOService)

bool X1605VAAssistant::start(IOService *provider) {
    if (!super::start(provider)) return false;

    acpi = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!acpi) {
        super::stop(provider);
        return false;
    }
    acpi->retain();

    registerService();
    IOLog("X1605VAAssistant: started\n");
    return true;
}

void X1605VAAssistant::stop(IOService *provider) {
    OSSafeReleaseNULL(acpi);
    super::stop(provider);
}

void X1605VAAssistant::free() {
    OSSafeReleaseNULL(acpi);
    super::free();
}

IOReturn X1605VAAssistant::getLED(uint32_t *state) {
    if (!acpi || isInactive()) return kIOReturnNotReady;
    const OSSymbol *name = OSSymbol::withCString("GLED");
    if (!name) return kIOReturnNoMemory;
    UInt32 val = 0;
    IOReturn ret = acpi->evaluateInteger(name, &val);
    name->release();
    if (ret == kIOReturnSuccess && val > 1) return kIOReturnError;
    if (ret == kIOReturnSuccess) *state = val;
    return ret;
}

IOReturn X1605VAAssistant::setLED(uint32_t state, uint32_t *result) {
    if (!acpi || isInactive()) return kIOReturnNotReady;
    if (state > 1) return kIOReturnBadArgument;

    const OSSymbol *name = OSSymbol::withCString("SLED");
    OSNumber *arg = OSNumber::withNumber(state, 32);
    if (!name || !arg) {
        OSSafeReleaseNULL(name);
        OSSafeReleaseNULL(arg);
        return kIOReturnNoMemory;
    }

    OSObject *params[1] = { arg };
    UInt32 val = 0;
    IOReturn ret = acpi->evaluateInteger(name, &val, params, 1);
    name->release();
    arg->release();

    if (ret == kIOReturnSuccess) {
        if (val > 1 || val != state) return kIOReturnError;
        *result = val;
    }
    return ret;
}

IOReturn X1605VAAssistant::getKeyboard(uint32_t *percent) {
    if (!acpi || isInactive() || !percent) return kIOReturnNotReady;
    const OSSymbol *name = OSSymbol::withCString("GBKL");
    if (!name) return kIOReturnNoMemory;
    UInt32 value = 0;
    IOReturn ret = acpi->evaluateInteger(name, &value);
    name->release();
    if (ret == kIOReturnSuccess && value > 100) return kIOReturnError;
    if (ret == kIOReturnSuccess) *percent = value;
    return ret;
}

IOReturn X1605VAAssistant::setKeyboard(uint32_t percent, uint32_t *result) {
    if (!acpi || isInactive() || !result) return kIOReturnNotReady;
    if (percent > 100) return kIOReturnBadArgument;
    const OSSymbol *name = OSSymbol::withCString("SBKL");
    OSNumber *arg = OSNumber::withNumber(percent, 32);
    if (!name || !arg) {
        OSSafeReleaseNULL(name); OSSafeReleaseNULL(arg);
        return kIOReturnNoMemory;
    }
    OSObject *params[] = {arg};
    UInt32 value = 0;
    IOReturn ret = acpi->evaluateInteger(name, &value, params, 1);
    name->release(); arg->release();
    if (ret == kIOReturnSuccess && (value > 100 || value != percent)) return kIOReturnError;
    if (ret == kIOReturnSuccess) *result = value;
    return ret;
}

// Capability discovery only checks namespace/services; it never executes TTPD.
// No firmware method or trackpad message is invoked from start().
bool X1605VAAssistant::trackpadACPIAvailable() {
    if (!acpi || isInactive() || acpi->validateObject("TTPD") != kIOReturnSuccess) return false;
    auto *matching = serviceMatching("AsusSMC");
    if (!matching) return false;
    auto *iterator = getMatchingServices(matching);
    matching->release();
    if (!iterator) return false;
    auto *service = OSDynamicCast(IOService, iterator->getNextObject());
    bool ready = service && !service->isInactive();
    iterator->release();
    return ready;
}

IOReturn X1605VAAssistant::trackpad(bool write, uint32_t enabled, uint32_t *result) {
    if (!result || enabled > 1 || isInactive()) return kIOReturnBadArgument;
    if (write && !trackpadACPIAvailable()) return kIOReturnUnsupported;
    auto *matching = serviceMatching("VoodooI2CMultitouchHIDEventDriver");
    if (!matching) return kIOReturnNoMemory;
    auto *iterator = getMatchingServices(matching);
    matching->release();
    if (!iterator) return kIOReturnNotFound;
    IOService *target = nullptr;
    while (auto *entry = iterator->getNextObject()) {
        auto *candidate = OSDynamicCast(IOService, entry);
        if (!candidate || candidate->isInactive()) continue;
        const char *cls = candidate->getMetaClass()->getClassName();
        // Never disable a touchscreen or a stylus subclass.
        if (!AsusSupportedTrackpadClass(cls)) continue;
        if (target) { iterator->release(); return kIOReturnUnsupported; }
        target = candidate;
    }
    IOReturn rc = kIOReturnNotFound;
    if (target) {
        bool state = false;
        rc = AsusApplyTrackpadState(target, this, acpi, write, enabled, &state);
        if (rc == kIOReturnSuccess) *result = state;
    }
    iterator->release();
    return rc;
}

IOReturn X1605VAAssistant::newUserClient(task_t owningTask, void *securityID, UInt32 type, IOUserClient **handler) {
    if (type != 0 || !handler || isInactive()) return kIOReturnBadArgument;
    *handler = nullptr;
    auto *client = OSTypeAlloc(X1605VAAssistantClient);
    if (!client) return kIOReturnNoMemory;

    if (!client->initWithTask(owningTask, securityID, type)) {
        client->release();
        return kIOReturnBadArgument;
    }
    if (!client->attach(this)) {
        client->release();
        return kIOReturnUnsupported;
    }
    if (!client->start(this)) {
        client->detach(this);
        client->release();
        return kIOReturnUnsupported;
    }

    *handler = client;
    return kIOReturnSuccess;
}

// ---------------- user client ----------------

#undef super
#define super IOUserClient
OSDefineMetaClassAndStructors(X1605VAAssistantClient, IOUserClient)

bool X1605VAAssistantClient::initWithTask(task_t owningTask, void *securityID, UInt32 type) {
    if (clientHasPrivilege(owningTask, kIOClientPrivilegeLocalUser) != kIOReturnSuccess)
        return false;
    return super::initWithTask(owningTask, securityID, type);
}

bool X1605VAAssistantClient::start(IOService *provider) {
    drv = OSDynamicCast(X1605VAAssistant, provider);
    if (!drv) return false;
    return super::start(provider);
}

IOReturn X1605VAAssistantClient::clientClose() {
    if (!isInactive()) terminate();
    return kIOReturnSuccess;
}

IOReturn X1605VAAssistantClient::sGet(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive()) return kIOReturnNotReady;
    uint32_t v = 0;
    IOReturn ret = me->drv->getLED(&v);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = v;
    return ret;
}

IOReturn X1605VAAssistantClient::sSet(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive()) return kIOReturnNotReady;
    if (args->scalarInput[0] > 1) return kIOReturnBadArgument;
    uint32_t v = 0;
    IOReturn ret = me->drv->setLED((uint32_t)args->scalarInput[0], &v);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = v;
    return ret;
}

IOReturn X1605VAAssistantClient::sGetKeyboard(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive()) return kIOReturnNotReady;
    uint32_t value = 0;
    IOReturn ret = me->drv->getKeyboard(&value);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = value;
    return ret;
}

IOReturn X1605VAAssistantClient::sSetKeyboard(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive()) return kIOReturnNotReady;
    if (args->scalarInput[0] > 100) return kIOReturnBadArgument;
    uint32_t value = 0;
    IOReturn ret = me->drv->setKeyboard((uint32_t)args->scalarInput[0], &value);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = value;
    return ret;
}

IOReturn X1605VAAssistantClient::sGetTrackpad(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive()) return kIOReturnNotReady;
    uint32_t value = 0;
    IOReturn rc = me->drv->trackpad(false, 0, &value);
    if (rc == kIOReturnSuccess) args->scalarOutput[0] = value;
    return rc;
}
IOReturn X1605VAAssistantClient::sSetTrackpad(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive()) return kIOReturnNotReady;
    if (args->scalarInput[0] > 1) return kIOReturnBadArgument;
    uint32_t value = 0;
    IOReturn rc = me->drv->trackpad(true, (uint32_t)args->scalarInput[0], &value);
    if (rc == kIOReturnSuccess) args->scalarOutput[0] = value;
    return rc;
}

IOReturn X1605VAAssistantClient::sCapabilities(X1605VAAssistantClient *me, void *, IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive()) return kIOReturnNotReady;
    args->scalarOutput[0] = me->drv->trackpadACPIAvailable() ? 1 : 0;
    return kIOReturnSuccess;
}

IOReturn X1605VAAssistantClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                           IOExternalMethodDispatch *, OSObject *, void *) {
    static const IOExternalMethodDispatch methods[7] = {
        { (IOExternalMethodAction)&X1605VAAssistantClient::sGet, 0, 0, 1, 0 }, // GLED: -> state
        { (IOExternalMethodAction)&X1605VAAssistantClient::sSet, 1, 0, 1, 0 }, // SLED: state -> state
        { (IOExternalMethodAction)&X1605VAAssistantClient::sGetKeyboard, 0, 0, 1, 0 },
        { (IOExternalMethodAction)&X1605VAAssistantClient::sSetKeyboard, 1, 0, 1, 0 },
        { (IOExternalMethodAction)&X1605VAAssistantClient::sGetTrackpad, 0, 0, 1, 0 },
        { (IOExternalMethodAction)&X1605VAAssistantClient::sSetTrackpad, 1, 0, 1, 0 },
        { (IOExternalMethodAction)&X1605VAAssistantClient::sCapabilities, 0, 0, 1, 0 },
    };
    if (selector >= 7) return kIOReturnUnsupported;
    return super::externalMethod(selector, args, (IOExternalMethodDispatch *)&methods[selector], this, nullptr);
}
