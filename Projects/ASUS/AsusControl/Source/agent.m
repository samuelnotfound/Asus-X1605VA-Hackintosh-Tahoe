// User-session policy agent. No event tap, Accessibility permission, or root service.
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "SystemStatus.h"
#include <unistd.h>
#include <signal.h>
static void wakeAgent(int signalNumber) { (void)signalNumber; }

int main(void) {
    @autoreleasepool {
        signal(SIGUSR1, wakeAgent);
        AsusSystemStatus *monitor = [[AsusSystemStatus alloc] init];
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        NSDictionary *previous = AsusReadAgentState();
        // Recover a light dimmed by a previous agent instance. Desired policy
        // intents are deliberately not restored: apply once per login/session.
        if ([previous[@"Dimmed"] boolValue]) {
            state[@"Dimmed"] = @YES;
            state[@"RestoreKeyboard"] = previous[@"RestoreKeyboard"] ?: @0;
        }
        NSString *haltedConfiguration = nil;
        while (YES) {
            @autoreleasepool {
                NSDictionary *preferences = AsusReadPreferences();
                NSString *bundle = preferences[@"SourceBundlePath"];
                BOOL removed = ![bundle isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:bundle];
                if (removed || !AsusNeedsAgent(preferences)) {
                    if ([state[@"Dimmed"] boolValue] && [state[@"RestoreKeyboard"] unsignedIntValue] <= 100)
                        AsusControlSendCommand(YES, [state[@"RestoreKeyboard"] unsignedIntValue], NULL);
                    if (removed) AsusRemoveAgent(NULL);
                    return 0;
                }
                NSData *serialized = [NSJSONSerialization dataWithJSONObject:preferences options:NSJSONWritingSortedKeys error:NULL];
                NSString *fingerprint = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
                if (haltedConfiguration && [haltedConfiguration isEqual:fingerprint]) { sleep(5); continue; }
                NSDictionary *hardware = AsusControlReadStatus();
                NSError *error = nil;
                if (![hardware[@"DeviceControlAllowed"] boolValue]) {
                    state[@"Error"] = @"Automatic settings require the matching driver and settings opt-in.";
                    AsusWriteAgentState(state, NULL); sleep(5); continue;
                }
                if (!AsusControlRefreshSettings(&error)) {
                    state[@"Error"] = error.localizedDescription;
                    if (error.code == 6) haltedConfiguration = fingerprint;
                    AsusWriteAgentState(state, NULL); sleep(5); continue;
                }
                hardware = AsusControlReadStatus();
                NSMutableDictionary *system = [[monitor sample] mutableCopy];
                for (NSString *key in @[@"PerformanceOnBattery", @"PerformanceMinimumBattery", @"FullSpeedOnBattery"])
                    if (hardware[key]) system[key] = hardware[key];
                NSTimeInterval now = NSDate.date.timeIntervalSince1970;
                NSArray *actions = AsusPolicyActions(preferences, hardware, system, state, now);
                [state removeObjectForKey:@"Error"];
                for (NSDictionary *action in actions) {
                    NSString *kind = action[@"Kind"];
                    if ([kind isEqual:@"clear-dim"]) { [state removeObjectForKey:@"Dimmed"]; continue; }
                    BOOL success = [kind isEqual:@"device"] ? AsusControlSendDeviceCommand([action[@"Value"] unsignedIntValue], &error) :
                        AsusControlSendCommand(YES, [action[@"Value"] unsignedIntValue], &error);
                    if (!success) {
                        state[@"Error"] = error.localizedDescription;
                        // Avoid repeatedly writing a setting the firmware rejected.
                        if (error.code != 8) haltedConfiguration = fingerprint;
                        break;
                    }
                    if (action[@"IntentKey"]) state[action[@"IntentKey"]] = action[@"Intent"];
                    if (action[@"SaveKeyboard"]) {
                        state[@"RestoreKeyboard"] = action[@"SaveKeyboard"]; state[@"Dimmed"] = @YES;
                    }
                    if (action[@"Restore"]) [state removeObjectForKey:@"Dimmed"];
                }
                state[@"Version"] = @ASUS_CONTROL_VERSION;
                state[@"UpdatedAt"] = @(now);
                AsusWriteAgentState(state, NULL);
            }
            sleep(5);
        }
    }
}
