// X1605VAAssistant — samuelnotfound (https://github.com/samuelnotfound)
#pragma once
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/c++/OSSymbol.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>

class X1605VAAssistant : public IOService {
    OSDeclareDefaultStructors(X1605VAAssistant)
    IOACPIPlatformDevice *acpi {nullptr};

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type, IOUserClient **handler) override;

    IOReturn getLED(uint32_t *state);
    IOReturn setLED(uint32_t state, uint32_t *result);
    IOReturn getKeyboard(uint32_t *percent);
    IOReturn setKeyboard(uint32_t percent, uint32_t *result);
    IOReturn trackpad(bool write, uint32_t enabled, uint32_t *result);
    bool trackpadACPIAvailable();
};

class X1605VAAssistantClient : public IOUserClient {
    OSDeclareDefaultStructors(X1605VAAssistantClient)
    X1605VAAssistant *drv {nullptr};

public:
    bool initWithTask(task_t owningTask, void *securityID, UInt32 type) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                            IOExternalMethodDispatch *dispatch, OSObject *target, void *ref) override;

    static IOReturn sGet(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sSet(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sGetKeyboard(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sSetKeyboard(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sGetTrackpad(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sCapabilities(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
    static IOReturn sSetTrackpad(X1605VAAssistantClient *me, void *ref, IOExternalMethodArguments *args);
};
