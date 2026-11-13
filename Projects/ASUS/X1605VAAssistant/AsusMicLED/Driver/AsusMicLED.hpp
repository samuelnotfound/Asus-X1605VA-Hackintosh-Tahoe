// AsusMicLED — orange mic-LED GPIO bridge for ASUS X1605VA
#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSSymbol.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

class AsusMicLED : public IOService {
    OSDeclareDefaultStructors(AsusMicLED)
    IOACPIPlatformDevice *acpi {nullptr};

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type,
                           IOUserClient **handler) override;

    IOReturn getLED(uint32_t *state);
    IOReturn setLED(uint32_t state, uint32_t *result);
};

class AsusMicLEDClient : public IOUserClient {
    OSDeclareDefaultStructors(AsusMicLEDClient)
    AsusMicLED *drv {nullptr};

public:
    bool initWithTask(task_t owningTask, void *securityID, UInt32 type) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                            IOExternalMethodDispatch *dispatch, OSObject *target,
                            void *ref) override;

    static IOReturn sGet(AsusMicLEDClient *me, void *ref,
                         IOExternalMethodArguments *args);
    static IOReturn sSet(AsusMicLEDClient *me, void *ref,
                         IOExternalMethodArguments *args);
};
