// Copyright (c) 2026 samuelnotfound. MIT License.
#import "DeviceClient.h"
#import <IOKit/IOKitLib.h>
#include <limits.h>
#include <unistd.h>

static NSString * const ErrorDomain = @"com.samuelnotfound.X1605VASettings";

static BOOL fail(NSError **error, NSString *message, NSInteger code) {
    if (error) *error = [NSError errorWithDomain:ErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

BOOL X1605VADecodeNumber32(id value, uint32_t *result) {
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return NO;
    int64_t number = 0;
    if (!CFNumberGetValue((__bridge CFNumberRef)value, kCFNumberSInt64Type, &number) ||
        number < INT32_MIN || number > UINT32_MAX) return NO;
    *result = (uint32_t)number;
    return YES;
}

NSString *X1605VAProfileName(NSInteger profile) {
    switch (profile) {
        case 0: return @"Standard";
        case 1: return @"Whisper";
        case 2: return @"Performance";
        default: return @"Unavailable";
    }
}

static NSDictionary *properties(io_service_t service) {
    CFMutableDictionaryRef values = NULL;
    if (IORegistryEntryCreateCFProperties(service, &values, kCFAllocatorDefault, 0) != KERN_SUCCESS)
        return @{};
    return CFBridgingRelease(values);
}

NSDictionary *X1605VAReadStatus(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusSMC"));
    if (!service) return @{@"Available": @NO};
    NSDictionary *values = properties(service);
    IOObjectRelease(service);
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithObject:@YES forKey:@"Available"];
    NSArray *keys = @[@"AsusSMC-Version", @"X1605VA-ControlAPIVersion", @"FanBackend",
        @"FanRPM", @"FanReadingValid", @"FanSamples", @"FanControlAllowed",
        @"FanRequestedMode", @"ThermalProfile", @"ThermalProfileValid",
        @"KeyboardControlAvailable", @"KeyboardPercent", @"KeyboardReadingValid"];
    for (NSString *key in keys) if (values[key]) status[key] = values[key];
    return status;
}

BOOL X1605VASendCommand(BOOL keyboard, uint32_t value, NSError **error) {
    if ((keyboard && value > 100) || (!keyboard && (value < 1 || value > 5)))
        return fail(error, @"Invalid control value.", 1);
    if (!keyboard && geteuid() != 0)
        return fail(error, @"Administrator authorization is required for fan settings.", 2);
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusSMC"));
    if (!service) return fail(error, @"AsusSMC is not loaded.", 3);
    NSDictionary *before = properties(service);
    if ([before[@"X1605VA-ControlAPIVersion"] integerValue] != 1 ||
        ![before[keyboard ? @"KeyboardControlAvailable" : @"FanControlAllowed"] boolValue]) {
        IOObjectRelease(service);
        return fail(error, keyboard ? @"The keyboard-backlight interface is unavailable." :
            @"Fan controls are unavailable. Check the AsusSMC version and boot arguments.", 4);
    }
    NSString *completed = keyboard ? @"KeyboardCompletedRequestID" : @"FanCompletedRequestID";
    uint32_t previous = 0;
    X1605VADecodeNumber32(before[completed], &previous);
    uint32_t request;
    do { request = arc4random_uniform(INT32_MAX) + 1; } while (request == previous);
    NSDictionary *command = keyboard ? @{@"KeyboardPercent": @(value), @"KeyboardRequestID": @(request)} :
        @{@"FanCommand": @(value), @"FanRequestID": @(request)};
    kern_return_t ret = IORegistryEntrySetCFProperties(service, (__bridge CFTypeRef)command);
    if (ret != KERN_SUCCESS) {
        IOObjectRelease(service);
        return fail(error, [NSString stringWithFormat:@"The driver rejected the request (0x%08x).", ret], ret);
    }
    for (unsigned attempt = 0; attempt < 150; ++attempt) {
        NSDictionary *reply = properties(service);
        uint32_t identifier = 0;
        if (X1605VADecodeNumber32(reply[completed], &identifier) && identifier == request) {
            BOOL success = NO;
            if (keyboard) {
                success = [reply[@"KeyboardCommandSucceeded"] isEqual:@YES];
            } else {
                uint32_t firmwareReply = 0;
                success = X1605VADecodeNumber32(reply[@"FanCommandReply"], &firmwareReply) && firmwareReply == 1;
            }
            IOObjectRelease(service);
            return success ? YES : fail(error, @"Firmware did not accept the requested setting.", 5);
        }
        usleep(100000);
    }
    IOObjectRelease(service);
    return fail(error, @"The request timed out. It may still complete; it has not been retried.", 6);
}
