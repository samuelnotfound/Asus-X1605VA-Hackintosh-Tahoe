#import "../Source/DeviceEnvironment.h"
#import <IOKit/ps/IOPSKeys.h>
#include <assert.h>
int main(void) { @autoreleasepool {
    NSMutableDictionary *battery=[@{@kIOPSTypeKey:@kIOPSInternalBatteryType,@kIOPSPowerSourceStateKey:@kIOPSBatteryPowerValue,
        @kIOPSCurrentCapacityKey:@70,@kIOPSMaxCapacityKey:@100,@kIOPSIsChargingKey:@NO}mutableCopy];
    NSDictionary *s=AsusPowerSourceSnapshot(@kIOPSACPowerValue,@[battery]);
    assert([s[@"PowerSourceKnown"]boolValue] && ![s[@"ACPower"]boolValue]);
    assert([s[@"BatteryPercent"]intValue]==70);
    battery[@kIOPSPowerSourceStateKey]=@kIOPSACPowerValue;
    s=AsusPowerSourceSnapshot(@kIOPSBatteryPowerValue,@[battery]);
    assert([s[@"ACPower"]boolValue] && ![s[@"Charging"]boolValue]);
    [battery removeObjectForKey:@kIOPSPowerSourceStateKey];
    s=AsusPowerSourceSnapshot(@kIOPSBatteryPowerValue,@[battery]);assert(![s[@"ACPower"]boolValue]);
    assert(![AsusPowerSourceSnapshot(nil,@[]) [@"PowerSourceKnown"]boolValue]);
    puts("PASS: explicit internal-battery power source, paused charging on AC, provider fallback and unknown source.");
} }
