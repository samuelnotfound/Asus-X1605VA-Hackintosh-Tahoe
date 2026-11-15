#import "DeviceEnvironment.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

@implementation AsusDeviceEnvironment
- (NSDictionary *)sample {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    double idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
    if (isfinite(idle) && idle >= 0) result[@"IdleSeconds"] = @(idle);
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info) {
        CFStringRef providing = IOPSGetProvidingPowerSourceType(info);
        if (providing && (CFEqual(providing, CFSTR(kIOPSACPowerValue)) || CFEqual(providing, CFSTR(kIOPSBatteryPowerValue)))) {
            result[@"PowerSourceKnown"] = @YES;
            result[@"ACPower"] = @([(__bridge NSString *)providing isEqualToString:@kIOPSACPowerValue]);
        }
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        if (sources) {
            for (id item in (__bridge NSArray *)sources) {
                NSDictionary *battery = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, (__bridge CFTypeRef)item);
                if (![battery[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
                double maximum = [battery[@kIOPSMaxCapacityKey] doubleValue];
                if (maximum > 0) {
                    result[@"BatteryKnown"] = @YES;
                    result[@"BatteryPercent"] = @(MAX(0, MIN(100, [battery[@kIOPSCurrentCapacityKey] doubleValue] * 100.0 / maximum)));
                }
                result[@"Charging"] = @([battery[@kIOPSIsChargingKey] boolValue]);
                NSString *health = battery[@"BatteryHealth"];
                if ([health isKindOfClass:NSString.class]) result[@"BatteryHealth"] = health;
            }
            CFRelease(sources);
        }
        CFRelease(info);
    }
    return result;
}
@end
