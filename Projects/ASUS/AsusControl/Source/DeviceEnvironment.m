#import "DeviceEnvironment.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

NSDictionary *AsusPowerSourceSnapshot(NSString *provider, NSArray<NSDictionary *> *sources) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if ([provider isEqual:@kIOPSACPowerValue] || [provider isEqual:@kIOPSBatteryPowerValue]) {
        result[@"PowerSourceKnown"] = @YES;
        result[@"ACPower"] = @([provider isEqual:@kIOPSACPowerValue]);
    }
    for (NSDictionary *battery in sources) {
        if (![battery[@kIOPSTypeKey] isEqual:@kIOPSInternalBatteryType]) continue;
        // Prefer the internal battery's explicit source over the aggregate
        // provider (which may describe a UPS). AC may be connected but not charging.
        NSString *source = battery[@kIOPSPowerSourceStateKey];
        if ([source isEqual:@kIOPSACPowerValue] || [source isEqual:@kIOPSBatteryPowerValue]) {
            result[@"PowerSourceKnown"] = @YES;
            result[@"ACPower"] = @([source isEqual:@kIOPSACPowerValue]);
        }
        double maximum = [battery[@kIOPSMaxCapacityKey] doubleValue];
        if (maximum > 0) {
            result[@"BatteryKnown"] = @YES;
            result[@"BatteryPercent"] = @(MAX(0, MIN(100, [battery[@kIOPSCurrentCapacityKey] doubleValue] * 100.0 / maximum)));
        }
        result[@"Charging"] = @([battery[@kIOPSIsChargingKey] boolValue]);
        NSString *health = battery[@"BatteryHealth"];
        if ([health isKindOfClass:NSString.class]) result[@"BatteryHealth"] = health;
        break;
    }
    return result;
}
@implementation AsusDeviceEnvironment
- (NSDictionary *)sample {
    NSString *provider = nil;
    NSMutableArray *batteries = [NSMutableArray array];
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info) {
        provider = (__bridge NSString *)IOPSGetProvidingPowerSourceType(info);
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        if (sources) {
            for (id item in (__bridge NSArray *)sources) {
                NSDictionary *battery = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, (__bridge CFTypeRef)item);
                if (battery) [batteries addObject:battery];
            }
            CFRelease(sources);
        }
    }
    NSMutableDictionary *result = [AsusPowerSourceSnapshot(provider, batteries) mutableCopy];
    if (info) CFRelease(info);
    double idle = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
    if (isfinite(idle) && idle >= 0) result[@"IdleSeconds"] = @(idle);
    return result;
}
@end
