// AsusMicLED — orange mic-LED GPIO bridge for ASUS X1605VA
#include "AsusMicLED.hpp"
#include <libkern/libkern.h>

#define super IOService
OSDefineMetaClassAndStructors(AsusMicLED, IOService)

bool AsusMicLED::start(IOService *provider) {
    if (!super::start(provider)) return false;

    acpi = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!acpi) {
        super::stop(provider);
        return false;
    }
    acpi->retain();

    registerService();
    IOLog("AsusMicLED: started\n");
    return true;
}

void AsusMicLED::stop(IOService *provider) {
    OSSafeReleaseNULL(acpi);
    super::stop(provider);
}

void AsusMicLED::free() {
    OSSafeReleaseNULL(acpi);
    super::free();
}

IOReturn AsusMicLED::getLED(uint32_t *state) {
    if (!acpi || isInactive() || !state) return kIOReturnNotReady;
    const OSSymbol *name = OSSymbol::withCString("GLED");
    if (!name) return kIOReturnNoMemory;
    UInt32 val = 0;
    IOReturn ret = acpi->evaluateInteger(name, &val);
    name->release();
    if (ret == kIOReturnSuccess) {
        if (val > 1) return kIOReturnError;
        *state = val;
    }
    return ret;
}

IOReturn AsusMicLED::setLED(uint32_t state, uint32_t *result) {
    if (!acpi || isInactive() || !result) return kIOReturnNotReady;
    if (state > 1) return kIOReturnBadArgument;

    const OSSymbol *name = OSSymbol::withCString("SLED");
    OSNumber *arg = OSNumber::withNumber((unsigned long long)state, 32);
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

IOReturn AsusMicLED::newUserClient(task_t owningTask, void *securityID,
                                   UInt32 type, IOUserClient **handler) {
    if (type != 0) return kIOReturnBadArgument;
    AsusMicLEDClient *client = new AsusMicLEDClient;
    if (!client) return kIOReturnNoMemory;
    if (!client->initWithTask(owningTask, securityID, type) ||
        !client->attach(this) || !client->start(this)) {
        client->detach(this);
        client->release();
        return kIOReturnError;
    }
    *handler = client;
    return kIOReturnSuccess;
}

// ---------- UserClient ----------

#define superClient IOUserClient
OSDefineMetaClassAndStructors(AsusMicLEDClient, IOUserClient)

bool AsusMicLEDClient::initWithTask(task_t owningTask, void *securityID, UInt32 type) {
    if (!superClient::initWithTask(owningTask, securityID, type)) return false;
    drv = nullptr;
    return true;
}

bool AsusMicLEDClient::start(IOService *provider) {
    if (!superClient::start(provider)) return false;
    drv = OSDynamicCast(AsusMicLED, provider);
    if (!drv) return false;
    drv->retain();
    return true;
}

IOReturn AsusMicLEDClient::clientClose() {
    if (drv) {
        drv->release();
        drv = nullptr;
    }
    terminate();
    return kIOReturnSuccess;
}

IOReturn AsusMicLEDClient::sGet(AsusMicLEDClient *me, void *,
                                IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive())
        return kIOReturnNotReady;
    uint32_t value = 0;
    IOReturn ret = me->drv->getLED(&value);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = value;
    return ret;
}

IOReturn AsusMicLEDClient::sSet(AsusMicLEDClient *me, void *,
                                IOExternalMethodArguments *args) {
    if (!me || !me->drv || me->isInactive() || me->drv->isInactive())
        return kIOReturnNotReady;
    if (args->scalarInput[0] > 1) return kIOReturnBadArgument;
    uint32_t value = 0;
    IOReturn ret = me->drv->setLED((uint32_t)args->scalarInput[0], &value);
    if (ret == kIOReturnSuccess) args->scalarOutput[0] = value;
    return ret;
}

IOReturn AsusMicLEDClient::externalMethod(uint32_t selector,
                                          IOExternalMethodArguments *args,
                                          IOExternalMethodDispatch *,
                                          OSObject *, void *) {
    static const IOExternalMethodDispatch methods[2] = {
        { (IOExternalMethodAction)&AsusMicLEDClient::sGet, 0, 0, 1, 0 }, // 0: GLED
        { (IOExternalMethodAction)&AsusMicLEDClient::sSet, 1, 0, 1, 0 }, // 1: SLED
    };
    if (selector >= 2) return kIOReturnUnsupported;
    return superClient::externalMethod(selector, args,
                                       (IOExternalMethodDispatch *)&methods[selector],
                                       this, nullptr);
}
