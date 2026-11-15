// Pure decisions, separated from firmware, launchd and the preference pane.
#import "Policy.h"

NSDictionary *AsusDefaultPreferences(void) {
    return @{@"FanManaged":@NO, @"ManualProfile":@0, @"BatteryManaged":@NO, @"BatteryCare":@YES, @"FullChargeUntil":@0,
        @"FnManaged":@NO, @"FnHotkeys":@YES,
        @"BacklightSleepMode":@0, @"BacklightTimeout":@60};
}
BOOL AsusNeedsAgent(NSDictionary *p) {
    return [p[@"FanManaged"] boolValue] || [p[@"BatteryManaged"] boolValue] || [p[@"FnManaged"] boolValue] ||
        [p[@"BacklightSleepMode"] integerValue] != 0;
}
NSInteger AsusEffectiveProfile(NSDictionary *p, NSDictionary *system) {
    BOOL ac = [system[@"ACPower"] boolValue];
    NSInteger profile = [p[@"ManualProfile"] integerValue];
    if (profile < 0 || profile > 3) return 0;
    // This is a capability of the current hardware profile, not every ASUS.
    if (!ac && profile == 2 && ![system[@"PerformanceOnBattery"] boolValue]) return 0;
    if (!ac && profile == 3 && ![system[@"FullSpeedOnBattery"] boolValue]) return 0;
    NSInteger minimum = system[@"PerformanceMinimumBattery"] ? [system[@"PerformanceMinimumBattery"] integerValue] : 40;
    if (profile == 2 && minimum > 0 && (![system[@"BatteryKnown"] boolValue] || [system[@"BatteryPercent"] integerValue] <= minimum)) return 0;
    return profile;
}
NSString *AsusChargePolicyContext(NSDictionary *p, NSDictionary *h, NSDictionary *system, NSTimeInterval now) {
    BOOL temporary = [p[@"BatteryCare"] boolValue] && [p[@"FullChargeUntil"] doubleValue] > now;
    NSInteger limit = [p[@"BatteryCare"] boolValue] && !temporary ? 80 : 100;
    return [NSString stringWithFormat:@"charge:%ld:driver:%@:ac:%@", (long)limit,
        h[@"DriverSessionID"] ?: h[@"DriverRegistryEntryID"] ?: @"unknown", system[@"PowerSourceKnown"] ? system[@"ACPower"] : @"unknown"];
}
NSArray<NSDictionary *> *AsusPolicyActions(NSDictionary *p, NSDictionary *h,
    NSDictionary *system, NSDictionary *state, NSTimeInterval now) {
    if (![h[@"DeviceControlAllowed"] boolValue]) return @[];
    NSMutableArray *actions = [NSMutableArray array];
    if ([p[@"BatteryManaged"] boolValue] && [h[@"BatteryCareAvailable"] boolValue]) {
        BOOL care = [p[@"BatteryCare"] boolValue];
        BOOL temporary = care && [p[@"FullChargeUntil"] doubleValue] > now;
        NSInteger limit = care && !temporary ? 80 : 100;
        NSString *intent = AsusChargePolicyContext(p, h, system, now);
        if (![state[@"ChargeIntent"] isEqual:intent] || [h[@"ChargeLimitRequested"] integerValue] != limit)
            [actions addObject:@{@"Kind":@"device", @"Value":@(limit == 80 ? 1 : 2), @"IntentKey":@"ChargeIntent", @"Intent":intent}];
    }
    if ([p[@"FanManaged"] boolValue] && [h[@"ThermalProfileValid"] boolValue] && [system[@"PowerSourceKnown"] boolValue]) {
        NSInteger profile = AsusEffectiveProfile(p, system);
        NSString *intent = [NSString stringWithFormat:@"profile:%ld", (long)profile];
        BOOL actualMatches = h[@"FanRequestedMode"] && (profile == 3 ? [h[@"FanRequestedMode"] integerValue] == 1 :
            [h[@"ThermalProfile"] integerValue] == profile && [h[@"FanRequestedMode"] integerValue] != 1);
        if (![state[@"ThermalIntent"] isEqual:intent] || !actualMatches)
            [actions addObject:@{@"Kind":actualMatches ? @"remember" : @"device", @"Value":@(profile == 3 ? 10 : 7 + profile), @"IntentKey":@"ThermalIntent", @"Intent":intent}];
    }
    if ([p[@"FnManaged"] boolValue] && [h[@"FnLockAvailable"] boolValue]) {
        BOOL hotkeys = [p[@"FnHotkeys"] boolValue];
        NSString *intent = hotkeys ? @"fn:hotkeys" : @"fn:functions";
        BOOL matches=[h[@"FnLockHotkeys"] boolValue]==hotkeys;
        if (![state[@"FnIntent"] isEqual:intent] || !matches)
            [actions addObject:@{@"Kind":matches ? @"remember" : @"device", @"Value":@(hotkeys ? 3 : 4), @"IntentKey":@"FnIntent", @"Intent":intent}];
    }
    NSInteger sleepMode = [p[@"BacklightSleepMode"] integerValue];
    NSInteger timeout = [p[@"BacklightTimeout"] integerValue];
    BOOL applicable = sleepMode == 1 || (sleepMode == 2 && [system[@"PowerSourceKnown"] boolValue] && ![system[@"ACPower"] boolValue]);
    BOOL dimmed = [state[@"Dimmed"] boolValue];
    if (system[@"IdleSeconds"] && [h[@"KeyboardReadingValid"] boolValue] && [h[@"KeyboardControlAvailable"] boolValue]) {
        NSInteger level = [h[@"KeyboardPercent"] integerValue];
        double idle = [system[@"IdleSeconds"] doubleValue];
        if (dimmed && (!applicable || timeout <= 0 || idle < timeout)) {
            if (level == 0 && [state[@"RestoreKeyboard"] integerValue] > 0)
                [actions addObject:@{@"Kind":@"keyboard", @"Value":state[@"RestoreKeyboard"], @"Restore":@YES}];
            else [actions addObject:@{@"Kind":@"clear-dim"}];
        } else if (!dimmed && applicable && timeout >= 30 && idle >= timeout && level > 0) {
            [actions addObject:@{@"Kind":@"keyboard", @"Value":@0, @"SaveKeyboard":@(level)}];
        }
    }
    return actions;
}

// A successful property submission is an acknowledgement. Confirm the resulting
// cache before recording an applied intent; never repeat an accepted write.
static BOOL matches(NSDictionary *action, NSDictionary *hardware) {
    uint32_t value = [action[@"Value"] unsignedIntValue];
    if ([action[@"Kind"] isEqual:@"keyboard"])
        return [hardware[@"KeyboardReadingValid"] boolValue] && [hardware[@"KeyboardPercent"] unsignedIntValue] == value;
    if (value <= 2) return [hardware[@"ChargeLimitRequested"] integerValue] == (value == 1 ? 80 : 100);
    if (value <= 4) return [hardware[@"FnLockAvailable"] boolValue] && [hardware[@"FnLockHotkeys"] boolValue] == (value == 3);
    if (value >= 7 && value <= 9)
        return [hardware[@"ThermalProfileValid"] boolValue] && [hardware[@"ThermalProfile"] unsignedIntValue] == value - 7 &&
            [hardware[@"FanRequestedMode"] integerValue] == 0;
    if (value == 10) return [hardware[@"FanRequestedMode"] integerValue] == 1;
    return NO;
}
BOOL AsusExecutePolicyActions(NSArray<NSDictionary *> *actions, NSMutableDictionary *state,
    AsusPolicySender sender, AsusPolicyReader reader, NSError **error) {
    for (NSDictionary *action in actions) {
        NSString *kind = action[@"Kind"];
        if ([kind isEqual:@"remember"]) { state[action[@"IntentKey"]]=action[@"Intent"]; continue; }
        if ([kind isEqual:@"clear-dim"]) { [state removeObjectForKey:@"Dimmed"]; continue; }
        if (!sender([kind isEqual:@"keyboard"], [action[@"Value"] unsignedIntValue], error)) return NO;
        BOOL confirmed = NO;
        for (unsigned attempt = 0; attempt < 3; ++attempt) {
            NSDictionary *hardware = reader(error);
            if (!hardware) return NO;
            if (matches(action, hardware)) { confirmed = YES; break; }
        }
        if (!confirmed) {
            uint32_t value = [action[@"Value"] unsignedIntValue];
            NSString *setting = [kind isEqual:@"keyboard"] ? @"the keyboard-light level" : value <= 2 ? @"the charging limit" : value <= 4 ? @"the function-key mode" : value == 10 ? @"Full Speed" : value >= 7 && value <= 9 ? @[@"Standard", @"Whisper", @"Performance"][value - 7] : @"the requested setting";
            if (error) *error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:9
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Firmware acknowledged %@, but readback did not confirm it. Choose Try Again to reapply it.", setting]}];
            return NO;
        }
        if (action[@"IntentKey"]) state[action[@"IntentKey"]] = action[@"Intent"];
        if (action[@"SaveKeyboard"]) { state[@"RestoreKeyboard"] = action[@"SaveKeyboard"]; state[@"Dimmed"] = @YES; }
        if (action[@"Restore"]) [state removeObjectForKey:@"Dimmed"];
    }
    return YES;
}
