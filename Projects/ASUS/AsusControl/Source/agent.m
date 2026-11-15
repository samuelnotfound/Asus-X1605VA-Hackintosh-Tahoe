// Per-user policy service. Settings requests are explicit and confirmed by readback.
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "SystemStatus.h"
#include <unistd.h>

static void publish(NSMutableDictionary *state, NSString *revision, NSString *result, NSString *error) {
    state[@"Revision"] = revision ?: @"";
    state[@"Result"] = result;
    state[@"Version"] = @ASUS_CONTROL_VERSION;
    state[@"UpdatedAt"] = @(NSDate.date.timeIntervalSince1970);
    if (error) state[@"Error"] = error; else [state removeObjectForKey:@"Error"];
    AsusWriteAgentState(state, NULL);
}
int main(void) {
    @autoreleasepool {
        AsusSystemStatus *monitor = [[AsusSystemStatus alloc] init];
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        NSDictionary *previous = AsusReadAgentState();
        if ([previous[@"Dimmed"] boolValue]) {
            state[@"Dimmed"] = @YES; state[@"RestoreKeyboard"] = previous[@"RestoreKeyboard"] ?: @0;
        }
        NSString *haltedRevision = nil;
        while (YES) {
            @autoreleasepool {
                NSDictionary *p = AsusReadPreferences();
                NSString *bundle = p[@"SourceBundlePath"], *revision = p[@"Revision"] ?: @"legacy";
                BOOL removed = ![bundle isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:bundle];
                if (removed || !AsusNeedsAgent(p)) {
                    if (removed) AsusRemoveAgent(NULL);
                    return 0;
                }
                if ([haltedRevision isEqual:revision]) { sleep(5); continue; }
                if (![state[@"Revision"] isEqual:revision]) publish(state, revision, @"applying", nil);
                NSError *error = nil;
                BOOL success = AsusControlRefreshSettings(&error);
                NSDictionary *hardware = AsusControlReadStatus();
                if (success && (![hardware[@"DeviceControlAllowed"] boolValue] ||
                    (([p[@"FanManaged"] boolValue] || [p[@"SplitProfiles"] boolValue] || [p[@"FollowLowPower"] boolValue]) && ![hardware[@"ThermalProfileValid"] boolValue]) ||
                    ([p[@"BatteryManaged"] boolValue] && ![hardware[@"BatteryCareAvailable"] boolValue]) ||
                    ([p[@"FnManaged"] boolValue] && ![hardware[@"FnLockAvailable"] boolValue]) ||
                    ([p[@"BacklightSleepMode"] integerValue] && ![hardware[@"KeyboardControlAvailable"] boolValue]))) {
                    success = NO;
                    error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:4 userInfo:@{NSLocalizedDescriptionKey:@"A configured setting is unavailable with the current driver or firmware."}];
                }
                if (success) {
                    NSMutableDictionary *system = [[monitor sample] mutableCopy];
                    for (NSString *key in @[@"PerformanceOnBattery", @"PerformanceMinimumBattery", @"FullSpeedOnBattery"])
                        if (hardware[key]) system[key] = hardware[key];
                    if (([p[@"FanManaged"] boolValue] || [p[@"SplitProfiles"] boolValue] || [p[@"FollowLowPower"] boolValue]) && ![system[@"PowerSourceKnown"] boolValue]) {
                        success = NO;
                        error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:10 userInfo:@{NSLocalizedDescriptionKey:@"The current power source is unavailable. The fan profile has not been changed."}];
                    } else {
                        NSArray *actions = AsusPolicyActions(p, hardware, system, state, NSDate.date.timeIntervalSince1970);
                        if (actions.count) publish(state, revision, @"applying", nil);
                        success = AsusExecutePolicyActions(actions, state, ^BOOL(BOOL keyboard, uint32_t value, NSError **failure) {
                            return keyboard ? AsusControlSendCommand(YES, value, failure) : AsusControlSendDeviceCommand(value, failure);
                        }, ^NSDictionary *(NSError **failure) {
                            return AsusControlRefreshSettings(failure) ? AsusControlReadStatus() : nil;
                        }, &error);
                    }
                }
                publish(state, revision, success ? @"applied" : @"failed", error.localizedDescription);
                // A rejected/mismatched request is visible until a new explicit
                // configuration/retry. Never loop writes against a failed device.
                if (!success && error.code != 8) haltedRevision = revision;
            }
            sleep(5);
        }
    }
}
