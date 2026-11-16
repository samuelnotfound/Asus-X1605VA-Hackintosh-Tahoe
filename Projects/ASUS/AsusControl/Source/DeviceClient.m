// Copyright (c) 2026 samuelnotfound. MIT License.
#import "DeviceClient.h"
#import <IOKit/IOKitLib.h>
#include <limits.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <sys/time.h>

static NSString * const ErrorDomain = @"com.samuelnotfound.AsusControl";

static BOOL fail(NSError **error, NSString *message, NSInteger code) {
    if (error) *error = [NSError errorWithDomain:ErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

BOOL AsusControlDecodeNumber32(id value, uint32_t *result) {
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    int64_t number = 0;
    if (!CFNumberGetValue((__bridge CFNumberRef)value, kCFNumberSInt64Type, &number) ||
        number < INT32_MIN || number > UINT32_MAX) return NO;
    *result = (uint32_t)number;
    return YES;
}

NSString *AsusControlProfileName(NSInteger profile) {
    switch (profile) {
        case 0: return @"Standard";
        case 1: return @"Whisper";
        case 2: return @"Performance";
        case 3: return @"Full Speed";
        default: return @"Unavailable";
    }
}

static BOOL legacyInvertedFn(NSDictionary *properties) {
    return [properties[@"AsusControlHardwareProfile"] isEqual:@"ASUS X1605VA / BIOS 305"] &&
        [properties[@"FnLockSemanticsVersion"] integerValue] < 1;
}
NSDictionary *AsusControlNormalizeFnStatus(NSDictionary *status) {
    BOOL known = [status[@"AsusControlHardwareProfile"] isEqual:@"ASUS X1605VA / BIOS 305"];
    if (!known) return status;
    NSMutableDictionary *result = [status mutableCopy];
    if (legacyInvertedFn(status)) {
        if (status[@"FnLockHotkeys"]) result[@"FnLockHotkeys"] = @(![status[@"FnLockHotkeys"] boolValue]);
        if (status[@"FnLockRequestedHotkeys"]) result[@"FnLockRequestedHotkeys"] = @(![status[@"FnLockRequestedHotkeys"] boolValue]);
        result[@"FnLockSemanticsVersion"] = @1;
        result[@"FnLockInverted"] = @YES;
        result[@"FnLockCompatibilityMapping"] = @YES;
    }
    // This profile reads a shared firmware mirror, not the keyboard mode.
    // Honor an explicit future driver capability if a reliable source is added.
    if (known && !status[@"FnLockReadbackReliable"]) result[@"FnLockReadbackReliable"] = @NO;
    return result;
}
uint32_t AsusControlDeviceCommandForHardware(uint32_t command, NSDictionary *properties) {
    return legacyInvertedFn(properties) && (command == 3 || command == 4) ? 7 - command : command;
}

static NSDictionary *properties(io_service_t service) {
    CFMutableDictionaryRef values = NULL;
    if (IORegistryEntryCreateCFProperties(service, &values, kCFAllocatorDefault, 0) != KERN_SUCCESS)
        return @{};
    return CFBridgingRelease(values);
}

NSDictionary *AsusControlReadStatus(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusSMC"));
    if (!service) return @{@"Available": @NO};
    NSDictionary *values = properties(service);
    uint64_t registryID = 0;
    BOOL identityKnown = IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS;
    IOObjectRelease(service);
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithObject:@YES forKey:@"Available"];
    if (identityKnown) {
        status[@"DriverRegistryEntryID"] = @(registryID);
        struct timeval boot = {0}; size_t size = sizeof(boot);
        if (sysctlbyname("kern.boottime", &boot, &size, NULL, 0) == 0)
            status[@"DriverSessionID"] = [NSString stringWithFormat:@"%lld.%d:%llu", (long long)boot.tv_sec, (int)boot.tv_usec, (unsigned long long)registryID];
    }
    NSArray *keys = @[@"AsusSMC-Version", @"X1605VA-ControlAPIVersion", @"FanBackend",
        @"FanRPM", @"FanReadingValid", @"FanSamples", @"FanControlAllowed",
        @"FanRequestedMode", @"ThermalProfile", @"ThermalProfileValid",
        @"KeyboardControlAvailable", @"KeyboardPercent", @"KeyboardReadingValid", @"SettingsRefreshAvailable",
        @"AsusControlAPIVersion", @"AsusControlHardwareProfile", @"DeviceControlAllowed",
        @"AsusControlRevision", @"AsusControlAutoDetected", @"FnLockRaw", @"FnLockWriteAcknowledged", @"FnLockRequestedHotkeys",
        @"FnLockSemanticsVersion", @"FnLockInverted", @"FnLockReadbackReliable",
        @"BatteryCareAvailable", @"ChargeLimitRequested", @"BatteryConservativeMode",
        @"FnLockAvailable", @"FnLockHotkeys", @"TrackpadControlAvailable", @"TrackpadReadingValid", @"TrackpadEnabled",
        @"PerformanceOnBattery", @"PerformanceMinimumBattery", @"FullSpeedOnBattery"];
    for (NSString *key in keys) if (values[key]) status[key] = values[key];
    status[@"ControlAPIVersion"] = values[@"AsusControlAPIVersion"] ?: values[@"X1605VA-ControlAPIVersion"] ?: @0;
    return AsusControlNormalizeFnStatus(status);
}

static BOOL sendCommand(BOOL keyboard, BOOL refresh, BOOL device, uint32_t value, NSError **error) {
    if (device ? value < 1 || value > 11 : refresh ? value != 1 : (keyboard && value > 100) || (!keyboard && (value < 1 || value > 5)))
        return fail(error, @"Invalid control value.", 1);
    if (!keyboard && !refresh && !device && geteuid() != 0)
        return fail(error, @"Administrator authorization is required for fan settings.", 2);
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusSMC"));
    if (!service) return fail(error, @"AsusSMC is not loaded.", 3);
    NSDictionary *before = properties(service);
    NSInteger api = [before[@"AsusControlAPIVersion"] ?: before[@"X1605VA-ControlAPIVersion"] integerValue];
    if (api < 1 || api > 2 || (device && api < 2) ||
        ![before[device ? @"DeviceControlAllowed" : refresh ? @"SettingsRefreshAvailable" : keyboard ? @"KeyboardControlAvailable" : @"FanControlAllowed"] boolValue]) {
        IOObjectRelease(service);
        return fail(error, device ? @"Device controls require the matching AsusSMC functions and compatible firmware." : refresh ? @"This driver does not support on-demand settings reads." : keyboard ? @"The keyboard-backlight interface is unavailable." :
            @"Fan controls are unavailable with this driver or firmware.", 4);
    }
    NSString *completed = device ? @"DeviceCompletedRequestID" : refresh ? @"SettingsCompletedRequestID" : keyboard ? @"KeyboardCompletedRequestID" : @"FanCompletedRequestID";
    uint32_t previous = 0;
    AsusControlDecodeNumber32(before[completed], &previous);
    uint32_t request;
    do { request = arc4random_uniform(INT32_MAX) + 1; } while (request == previous);
    uint32_t wireValue = device ? AsusControlDeviceCommandForHardware(value, before) : value;
    NSDictionary *command = device ? @{@"DeviceCommand": @(wireValue), @"DeviceRequestID": @(request)} : refresh ? @{@"SettingsCommand": @1, @"SettingsRequestID": @(request)} : keyboard ? @{@"KeyboardPercent": @(value), @"KeyboardRequestID": @(request)} :
        @{@"FanCommand": @(value), @"FanRequestID": @(request)};
    kern_return_t ret = kIOReturnBusy;
    // Competing pane/agent clients share one workloop queue. Retry only an
    // unaccepted busy submission; never resubmit an accepted firmware request.
    for (unsigned attempt = 0; attempt < 20 && ret == kIOReturnBusy; ++attempt) {
        ret = IORegistryEntrySetCFProperties(service, (__bridge CFTypeRef)command);
        if (ret == kIOReturnBusy) usleep(100000);
    }
    if (ret != KERN_SUCCESS) {
        IOObjectRelease(service);
        return fail(error, [NSString stringWithFormat:@"The driver rejected the request (0x%08x).", ret], ret == kIOReturnBusy ? 8 : ret);
    }
    for (unsigned attempt = 0; attempt < 150; ++attempt) {
        NSDictionary *reply = properties(service);
        uint32_t identifier = 0;
        if (AsusControlDecodeNumber32(reply[completed], &identifier) && identifier == request) {
            BOOL success = NO;
            if (device) {
                success = [reply[@"DeviceCommandSucceeded"] isEqual:@YES];
            } else if (refresh) {
                success = [reply[@"SettingsCommandSucceeded"] isEqual:@YES];
            } else if (keyboard) {
                success = [reply[@"KeyboardCommandSucceeded"] isEqual:@YES];
            } else {
                uint32_t firmwareReply = 0;
                success = AsusControlDecodeNumber32(reply[@"FanCommandReply"], &firmwareReply) && firmwareReply == 1;
            }
            IOObjectRelease(service);
            return success ? YES : fail(error, @"Firmware did not accept the requested setting.", 5);
        }
        usleep(100000);
    }
    IOObjectRelease(service);
    return fail(error, @"The request timed out. It may still complete; it has not been retried.", 6);
}

BOOL AsusControlSendCommand(BOOL keyboard, uint32_t value, NSError **error) {
    return sendCommand(keyboard, NO, NO, value, error);
}
BOOL AsusControlRefreshSettings(NSError **error) {
    return sendCommand(NO, YES, NO, 1, error);
}
BOOL AsusControlSendDeviceCommand(uint32_t command, NSError **error) {
    return sendCommand(NO, NO, YES, command, error);
}
