// Pure decisions, separated from firmware, launchd and the preference pane.
#import "Policy.h"

NSDictionary *AsusDefaultPreferences(void) {
    return @{@"FanManaged":@NO, @"ManualProfile":@0,
        @"FnManaged":@NO, @"FnHotkeys":@YES,
        @"BacklightSleepMode":@0, @"BacklightTimeout":@60};
}
BOOL AsusNeedsAgent(NSDictionary *p) {
    return [p[@"FanManaged"] boolValue] || [p[@"FnManaged"] boolValue] ||
        [p[@"BacklightSleepMode"] integerValue] != 0;
}
NSInteger AsusEffectiveProfile(NSDictionary *p, NSDictionary *system) {
    BOOL ac = [system[@"ACPower"] boolValue];
    NSInteger profile = [p[@"ManualProfile"] integerValue];
    if (profile < 0 || profile > 3) return 0;
    // This is a capability of the current hardware profile, not every ASUS.
    if (!ac && profile == 2 && ![system[@"PerformanceOnBattery"] boolValue]) return 0;
    if (profile == 3 && (!ac || ![system[@"PowerSourceKnown"] boolValue] || ![system[@"BatteryKnown"] boolValue] || [system[@"BatteryPercent"] doubleValue] <= 40)) return 0;
    NSInteger minimum = system[@"PerformanceMinimumBattery"] ? [system[@"PerformanceMinimumBattery"] integerValue] : 40;
    if (profile == 2 && minimum > 0) {
        BOOL active = [system[@"PerformanceActive"] boolValue];
        if (![system[@"BatteryKnown"] boolValue]) return active ? 2 : 0;
        double percent = [system[@"BatteryPercent"] doubleValue];
        if (percent < minimum || (percent == minimum && !active)) return 0;
    }
    return profile;
}
static BOOL performanceActive(NSDictionary *h) {
    return [h[@"ThermalProfileValid"] boolValue] && [h[@"ThermalProfile"] integerValue] == 2 &&
        [h[@"FanRequestedMode"] integerValue] != 1;
}
NSDictionary *AsusFanSessionPreferences(NSDictionary *p, NSDictionary *h, NSDictionary *system, NSDictionary *state) {
    NSMutableDictionary *next = [p mutableCopy];
    [next removeObjectsForKeys:@[@"AutoPerformanceOnAC",@"BatteryManaged",@"BatteryCare",@"FullChargeUntil"]];
    if (![p[@"FanManaged"] boolValue] || [p[@"ManualProfile"] integerValue] != 2) return next;
    NSString *boot = h[@"BootSessionID"];
    BOOL restarted = boot && ![state[@"FanBootSessionID"] isEqual:boot];
    BOOL unplugged = [system[@"PowerSourceKnown"] boolValue] && ![system[@"ACPower"] boolValue] &&
        ![h[@"PerformanceOnBattery"] boolValue];
    double minimum = h[@"PerformanceMinimumBattery"] ? [h[@"PerformanceMinimumBattery"] doubleValue] : 40;
    double percent = [system[@"BatteryPercent"] doubleValue];
    BOOL low = minimum > 0 && [system[@"BatteryKnown"] boolValue] &&
        (percent < minimum || (percent == minimum && !performanceActive(h)));
    // Retire the preference, rather than temporarily overriding it and later
    // restoring Performance on reconnect. This runs in the user session only.
    if (restarted || unplugged || low) next[@"ManualProfile"] = @0;
    return next;
}
void AsusRetireChargingState(NSMutableDictionary *state) {
    [state removeObjectForKey:@"ChargeIntent"];
    NSMutableDictionary *failures=[state[@"FailedFamilies"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *retired=failures[@"ChargeIntent"];
    [failures removeObjectForKey:@"ChargeIntent"];state[@"FailedFamilies"]=failures;
    NSMutableDictionary *contexts=[state[@"FailedFamilyContexts"] mutableCopy] ?: [NSMutableDictionary dictionary];
    [contexts removeObjectForKey:@"ChargeIntent"];state[@"FailedFamilyContexts"]=contexts;
    if(retired && [state[@"Error"] isEqual:retired]) {
        if(failures.count)state[@"Error"]=failures.allValues.firstObject;
        else[state removeObjectForKey:@"Error"];
    }
}
NSString *AsusFnPolicyContext(NSDictionary *p, NSDictionary *h) {
    return [NSString stringWithFormat:@"fn:%@:semantics:1:driver:%@", [p[@"FnHotkeys"] boolValue] ? @"hotkeys" : @"functions",
        h[@"DriverSessionID"] ?: h[@"DriverRegistryEntryID"] ?: @"unknown"];
}
BOOL AsusFnReadbackReliable(NSDictionary *h) {
    return !h[@"FnLockReadbackReliable"] || [h[@"FnLockReadbackReliable"] boolValue];
}
void AsusRecoverFnReadbackState(NSDictionary *p, NSDictionary *h, NSMutableDictionary *state) {
    if (![p[@"FnManaged"] boolValue] || AsusFnReadbackReliable(h)) return;
    NSString *intent = AsusFnPolicyContext(p,h);
    NSMutableDictionary *failures = [state[@"FailedFamilies"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *failure = failures[@"FnIntent"];
    BOOL priorSuccess = !failure && [state[@"FnIntent"] isEqual:intent];
    BOOL acceptedMismatch = [state[@"FnPendingIntent"] isEqual:intent] &&
        [failure hasPrefix:@"Firmware acknowledged the function-key mode, but readback did not confirm it."];
    if (!priorSuccess && !acceptedMismatch) return;
    state[@"FnAcceptedIntent"] = intent;
    state[@"FnVerification"] = @"acknowledged";
    [state removeObjectForKey:@"FnIntent"];
    [state removeObjectForKey:@"FnPendingIntent"];
    if (acceptedMismatch) {
        [failures removeObjectForKey:@"FnIntent"]; state[@"FailedFamilies"] = failures;
        NSMutableDictionary *contexts = [state[@"FailedFamilyContexts"] mutableCopy] ?: [NSMutableDictionary dictionary];
        [contexts removeObjectForKey:@"FnIntent"]; state[@"FailedFamilyContexts"] = contexts;
        if ([state[@"Error"] isEqual:failure]) {
            if (failures.count) state[@"Error"] = failures.allValues.firstObject;
            else [state removeObjectForKey:@"Error"];
        }
    }
}
static BOOL fnAccepted(NSDictionary *p, NSDictionary *h, NSDictionary *state) {
    return [p[@"FnManaged"] boolValue] && !AsusFnReadbackReliable(h) &&
        [state[@"FnAcceptedIntent"] isEqual:AsusFnPolicyContext(p,h)];
}
NSString *AsusPolicyCompletionResult(NSDictionary *p, NSDictionary *h, NSDictionary *state) {
    return fnAccepted(p,h,state) ? @"accepted" : @"applied";
}
NSDictionary *AsusFnStatusForUI(NSDictionary *p, NSDictionary *h, NSDictionary *state) {
    NSMutableDictionary *display = [h mutableCopy] ?: [NSMutableDictionary dictionary];
    if (fnAccepted(p,h,state)) {
        display[@"FnSelectedHotkeys"] = p[@"FnHotkeys"];
        display[@"FnSelectionSource"] = @"acknowledged";
    } else if (AsusFnReadbackReliable(h) && [h[@"FnLockAvailable"] boolValue] && h[@"FnLockHotkeys"]) {
        display[@"FnSelectedHotkeys"] = h[@"FnLockHotkeys"];
        display[@"FnSelectionSource"] = @"readback";
    }
    return display;
}
NSArray<NSDictionary *> *AsusPolicyActions(NSDictionary *p, NSDictionary *h,
    NSDictionary *system, NSDictionary *state, NSTimeInterval now) {
    if (![h[@"DeviceControlAllowed"] boolValue]) return @[];
    NSMutableArray *actions = [NSMutableArray array];
    (void)now;
    if ([p[@"FanManaged"] boolValue] && [h[@"ThermalProfileValid"] boolValue] && [system[@"PowerSourceKnown"] boolValue]) {
        NSMutableDictionary *eligibility = [system mutableCopy];
        eligibility[@"PerformanceActive"] = @(performanceActive(h));
        NSInteger profile = AsusEffectiveProfile(p, eligibility);
        NSString *intent = [NSString stringWithFormat:@"profile:%ld", (long)profile];
        BOOL actualMatches = h[@"FanRequestedMode"] && (profile == 3 ? [h[@"FanRequestedMode"] integerValue] == 1 :
            [h[@"ThermalProfile"] integerValue] == profile && [h[@"FanRequestedMode"] integerValue] != 1);
        if (![state[@"ThermalIntent"] isEqual:intent] || !actualMatches)
            [actions addObject:@{@"Kind":actualMatches ? @"remember" : @"device", @"Value":@(profile == 3 ? 10 : 7 + profile), @"IntentKey":@"ThermalIntent", @"Intent":intent}];
    }
    if ([p[@"FnManaged"] boolValue] && [h[@"FnLockAvailable"] boolValue]) {
        BOOL hotkeys = [p[@"FnHotkeys"] boolValue];
        NSString *intent = AsusFnPolicyContext(p, h);
        BOOL matches=[h[@"FnLockHotkeys"] boolValue]==hotkeys;
        // DSTS reads a firmware mirror; a matching value does not establish
        // that this saved selection was actually sent in this driver session.
        BOOL reliable = AsusFnReadbackReliable(h);
        BOOL needsRequest = reliable ? ![state[@"FnIntent"] isEqual:intent] || !matches :
            ![state[@"FnAcceptedIntent"] isEqual:intent];
        if (needsRequest)
            [actions addObject:@{@"Kind":@"device", @"Value":@(hotkeys ? 3 : 4), @"IntentKey":@"FnIntent", @"Intent":intent,
                @"FnReadbackReliable":@(reliable)}];
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
    if (value == 3 || value == 4) return [hardware[@"FnLockAvailable"] boolValue] && [hardware[@"FnLockHotkeys"] boolValue] == (value == 3);
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
        BOOL fn = [action[@"IntentKey"] isEqual:@"FnIntent"];
        if (fn) [state removeObjectForKey:@"FnPendingIntent"];
        if (!sender([kind isEqual:@"keyboard"], [action[@"Value"] unsignedIntValue], error)) return NO;
        if (fn && action[@"FnReadbackReliable"] && ![action[@"FnReadbackReliable"] boolValue]) {
            // Accepted is explicitly distinct from verified. Do not poll a
            // known unreliable mirror or repeatedly rewrite a working mode.
            state[@"FnAcceptedIntent"] = action[@"Intent"];
            state[@"FnVerification"] = @"acknowledged";
            [state removeObjectForKey:@"FnIntent"];
            continue;
        }
        if (fn) state[@"FnPendingIntent"] = action[@"Intent"];
        BOOL confirmed = NO;
        // Observe an accepted Fn request for longer; never resend the write.
        // This runs on the worker, not the UI thread or a kernel workloop.
        for (unsigned attempt = 0; attempt < (fn ? 10U : 3U); ++attempt) {
            if (fn && attempt) [NSThread sleepForTimeInterval:0.1];
            NSDictionary *hardware = reader(error);
            if (!hardware) return NO;
            if (matches(action, hardware)) { confirmed = YES; break; }
        }
        if (!confirmed) {
            uint32_t value = [action[@"Value"] unsignedIntValue];
            NSString *setting = [kind isEqual:@"keyboard"] ? @"the keyboard-light level" : value <= 4 ? @"the function-key mode" : value == 10 ? @"Full Speed" : value >= 7 && value <= 9 ? @[@"Standard", @"Whisper", @"Performance"][value - 7] : @"the requested setting";
            if (error) *error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:9
                userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Firmware acknowledged %@, but readback did not confirm it. Choose Try Again to reapply it.", setting]}];
            return NO;
        }
        if (action[@"IntentKey"]) state[action[@"IntentKey"]] = action[@"Intent"];
        if (fn) {
            [state removeObjectForKey:@"FnPendingIntent"];
            [state removeObjectForKey:@"FnAcceptedIntent"];
            state[@"FnVerification"] = @"readback";
        }
        if (action[@"SaveKeyboard"]) { state[@"RestoreKeyboard"] = action[@"SaveKeyboard"]; state[@"Dimmed"] = @YES; }
        if (action[@"Restore"]) [state removeObjectForKey:@"Dimmed"];
    }
    return YES;
}
