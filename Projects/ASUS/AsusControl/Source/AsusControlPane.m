// Copyright (c) 2026 samuelnotfound. MIT License.
#import "AsusControlPane.h"
#import "PaneActions.h"
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "DeviceEnvironment.h"
#import "PolicySession.h"
#import "AsusControlUI-Swift.h"

@interface AsusControlPane () <AsusPaneActions> {
    AsusSettingsUI *_ui;
    dispatch_queue_t _worker;
    NSTimer *_timer;
    AsusDeviceEnvironment *_monitor;
    NSDictionary *_hardware, *_system, *_preferences, *_agentState;
    BOOL _active, _refreshing, _busy, _refreshStopped;
    NSString *_lastError, *_policyErrorRevision, *_policyErrorFamily;
    NSTimeInterval _submittedAt;
}
@end
@implementation AsusControlPane
- (NSView *)loadMainView {
    if (self.mainView) return self.mainView;
    _worker = dispatch_queue_create("com.samuelnotfound.AsusControl.controls", DISPATCH_QUEUE_SERIAL);
    _monitor = [[AsusDeviceEnvironment alloc] init];
    _preferences = AsusReadPreferences();
    _ui = [[AsusSettingsUI alloc] initWithActions:self];
    [self setMainView:[_ui makeView]];
    [self displayStatus];
    return self.mainView;
}
- (void)didSelect {
    _active = YES; _refreshStopped = NO; _lastError = nil; _policyErrorRevision = nil;
    NSDictionary *state = AsusReadAgentState();
    // Upgrade an already opted-in service when the updated pane is opened.
    if (AsusNeedsAgent(_preferences) && ![state[@"Version"] isEqual:@ASUS_CONTROL_VERSION])
        [self savePreferences:_preferences];
    else [self refresh];
    __weak typeof(self) weakSelf = self;
    [_timer invalidate];
    _timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { (void)timer; [weakSelf refresh]; }];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)willUnselect { _active = NO; [_timer invalidate]; _timer = nil; }
- (void)dealloc { [_timer invalidate]; }
- (void)refresh {
    if (!_active || _refreshing || _busy) return;
    _refreshing = YES; BOOL query = !_refreshStopped;
    dispatch_async(_worker, ^{
        NSDictionary *hardware = AsusControlReadStatus(); NSError *error = nil;
        if (query && [hardware[@"SettingsRefreshAvailable"] boolValue]) {
            AsusControlRefreshSettings(&error); hardware = AsusControlReadStatus();
        }
        NSDictionary *system = [self->_monitor sample], *preferences = AsusReadPreferences(), *agent = AsusReadAgentState();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_refreshing = NO; if (!self->_active) return;
            self->_hardware = hardware; self->_system = system; self->_preferences = preferences; self->_agentState = agent;
            if(self->_policyErrorRevision && [self->_policyErrorRevision isEqual:agent[@"Revision"]] &&
                [agent[@"Revision"] isEqual:preferences[@"Revision"]] &&
                ([@[@"applied",@"accepted"] containsObject:agent[@"Result"] ?: @""] ||
                    (self->_policyErrorFamily && ![self->_policyErrorFamily isEqual:@"all"] &&
                        !agent[@"FailedFamilies"][self->_policyErrorFamily]))) {
                self->_lastError=nil; self->_policyErrorRevision=nil;
            }
            if (error.code == 6) { self->_refreshStopped = YES; self->_lastError = error.localizedDescription; self->_policyErrorRevision = nil; }
            [self displayStatus];
        });
    });
}
- (void)displayStatus {
    NSMutableDictionary *preferences = [_preferences mutableCopy] ?: [AsusDefaultPreferences() mutableCopy];
    if (![preferences[@"FnManaged"] boolValue] && _hardware[@"FnLockHotkeys"])
        preferences[@"FnHotkeys"] = _hardware[@"FnLockHotkeys"];
    if (![preferences[@"BatteryManaged"] boolValue])
        preferences[@"BatteryCare"] = @([_hardware[@"ChargeLimitRequested"] integerValue] == 80);
    if (![preferences[@"FanManaged"] boolValue])
        preferences[@"ManualProfile"] = [_hardware[@"FanRequestedMode"] integerValue] == 1 ? @3 : _hardware[@"ThermalProfile"] ?: @0;
    NSString *message = @""; BOOL failed = NO;
    if (_lastError.length) { message = _lastError; failed = YES; }
    else if (_busy) message = @"Applying settings…";
    else if (![_hardware[@"DeviceControlAllowed"] boolValue])
        message = @"Device controls require the matching AsusSMC functions and compatible firmware.";
    else if (AsusNeedsAgent(preferences)) {
        BOOL same = [_agentState[@"Revision"] isEqual:preferences[@"Revision"]];
        if (same && [_agentState[@"Result"] isEqual:@"failed"]) {
            message = _agentState[@"Error"] ?: @"The setting could not be confirmed."; failed = YES;
        } else if (!same || [_agentState[@"Result"] isEqual:@"applying"]) {
            NSTimeInterval started = same ? [_agentState[@"UpdatedAt"] doubleValue] : (_submittedAt ?: [_agentState[@"UpdatedAt"] doubleValue]);
            NSTimeInterval age = NSDate.date.timeIntervalSince1970 - started;
            message = age > 30 ? @"Automatic settings have not responded. Choose Try Again to restart them." : @"Applying settings…";
            failed = age > 30;
        } else if ([_agentState[@"Result"] isEqual:@"accepted"]) {
            // An accepted request is not a claim of physical verification.
            message = @"";
        } else {
            // The UI reports completion only for this saved revision.
            message = @"Settings applied.";
        }
    }
    NSString *version = [NSString stringWithFormat:@"ASUS Control %s · AsusSMC %@", ASUS_CONTROL_VERSION, _hardware[@"AsusSMC-Version"] ?: @"Unavailable"];
    [_ui updateWithHardware:AsusFnStatusForUI(preferences,_hardware ?: @{},_agentState ?: @{}) system:_system ?: @{} preferences:preferences message:message error:failed busy:_busy version:version];
}
- (void)savePreferences:(NSDictionary *)preferences { [self savePreferences:preferences family:@"all"]; }
- (void)savePreferences:(NSDictionary *)preferences family:(NSString *)family {
    if (_busy) return;
    _busy=YES; _lastError=nil; _policyErrorRevision=nil; [self displayStatus];
    dispatch_async(_worker, ^{
        NSError *error=nil;
        int lock=AsusAcquirePolicyLock(3000,&error);
        BOOL configured=lock>=0 && AsusConfigureAgent(self.bundle,preferences,&error);
        NSDictionary *saved=configured ? AsusReadPreferences() : self->_preferences;
        BOOL success=NO;
        if(configured) {
            NSMutableDictionary *state=[AsusReadAgentState() mutableCopy];
            // Migrate accepted legacy Fn mismatches before an explicit retry
            // clears failures; this avoids rewriting the already-working mode.
            AsusRecoverFnReadbackState(saved,AsusControlReadStatus(),state);
            if([family isEqual:@"all"]) {
                if(state[@"FailedFamilies"][@"FnIntent"]) {
                    // A genuine failed Fn request must be retried explicitly,
                    // even if an older accepted selection happens to match.
                    [state removeObjectForKey:@"FnIntent"];
                    [state removeObjectForKey:@"FnAcceptedIntent"];
                }
                [state removeObjectForKey:@"FailedFamilies"];
            }
            success=AsusApplyPolicyFamily(saved,family,self->_monitor,state,&error);
            state[@"Revision"]=saved[@"Revision"] ?: @"";
            NSDictionary *failures=state[@"FailedFamilies"];
            state[@"Result"]=success && !failures.count ? AsusPolicyCompletionResult(saved,AsusControlReadStatus(),state) : @"failed";
            state[@"Version"]=@ASUS_CONTROL_VERSION;
            state[@"UpdatedAt"]=@(NSDate.date.timeIntervalSince1970);
            if(failures.count)state[@"Error"]=failures.allValues.firstObject;
            else if(error)state[@"Error"]=error.localizedDescription;
            else[state removeObjectForKey:@"Error"];
            AsusWriteAgentState(state,NULL);
        }
        AsusReleasePolicyLock(lock);
        NSDictionary *hardware=AsusControlReadStatus(), *agent=AsusReadAgentState();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy=NO; self->_preferences=saved; self->_hardware=hardware; self->_agentState=agent;
            self->_submittedAt=NSDate.date.timeIntervalSince1970;
            self->_lastError=success ? nil : error.localizedDescription ?: @"The setting could not be applied.";
            self->_policyErrorRevision=!success && configured ? saved[@"Revision"] : nil;
            self->_policyErrorFamily=self->_policyErrorRevision ? family : nil;
            [self displayStatus];
        });
    });
}
- (void)changeSetting:(NSString *)key value:(id)value {
    if (_busy || ![_hardware[@"DeviceControlAllowed"] boolValue] || ![value isKindOfClass:NSNumber.class]) return;
    NSMutableDictionary *preferences = [_preferences mutableCopy]; NSInteger number = [value integerValue];
    if ([key isEqual:@"QuickProfile"]) {
        if (number < 0 || number > 3) return;
        preferences[@"ManualProfile"] = @(number); preferences[@"FanManaged"] = @YES; preferences[@"AutoPerformanceOnAC"] = @NO;
    } else if ([key isEqual:@"ManualProfile"]) {
        if (number < 0 || number > 3) return;
        preferences[key] = @(number); preferences[@"FanManaged"] = @YES; preferences[@"AutoPerformanceOnAC"] = @NO;
    } else if ([key isEqual:@"AutoPerformanceOnAC"]) {
        preferences[key] = @([value boolValue]); preferences[@"FanManaged"] = @YES;
        // A single automatic mode: Performance on eligible AC, Standard otherwise.
        // Turning it off leaves Standard until another profile is selected.
        preferences[@"ManualProfile"] = @0;
    } else if ([key isEqual:@"BatteryCare"]) {
        preferences[@"BatteryManaged"] = @YES; preferences[key] = @([value boolValue]); preferences[@"FullChargeUntil"] = @0;
    } else if ([key isEqual:@"FullCharge"]) {
        preferences[@"BatteryManaged"] = @YES; preferences[@"BatteryCare"] = @YES;
        preferences[@"FullChargeUntil"] = @([value boolValue] ? NSDate.date.timeIntervalSince1970 + 86400 : 0);
    } else if ([key isEqual:@"FnHotkeys"]) {
        preferences[@"FnManaged"] = @YES; preferences[key] = @([value boolValue]);
    } else if ([key isEqual:@"BacklightSleepMode"]) {
        if (number < 0 || number > 2) return; preferences[key] = @(number);
    } else if ([key isEqual:@"BacklightTimeout"]) {
        if (![@[@30,@60,@180,@300,@600,@900] containsObject:@(number)]) return; preferences[key] = @(number);
    } else return;
    NSString *family=[@[@"QuickProfile",@"ManualProfile",@"AutoPerformanceOnAC"] containsObject:key] ? @"ThermalIntent" :
        [key isEqual:@"FnHotkeys"] ? @"FnIntent" : [@[@"BatteryCare",@"FullCharge"] containsObject:key] ? @"ChargeIntent" : @"keyboard";
    [self savePreferences:preferences family:family];
}
- (void)retrySettings { _refreshStopped = NO; [self savePreferences:_preferences]; }
- (void)setTouchpadEnabled:(BOOL)enabled {
    if (_busy || ![_hardware[@"TrackpadControlAvailable"] boolValue]) return;
    _busy = YES; _lastError = nil; _policyErrorRevision = nil; [self displayStatus];
    dispatch_async(_worker, ^{
        NSError *error = nil;
        BOOL success = AsusControlSendDeviceCommand(enabled ? 5 : 6, &error), confirmed = NO;
        if (success) for (unsigned i = 0; i < 3; ++i) {
            if (!AsusControlRefreshSettings(&error)) break;
            NSDictionary *hardware = AsusControlReadStatus();
            if ([hardware[@"TrackpadReadingValid"] boolValue] && [hardware[@"TrackpadEnabled"] boolValue] == enabled) { confirmed = YES; break; }
        }
        NSDictionary *hardware = AsusControlReadStatus();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO; self->_hardware = hardware;
            NSDictionary *fnStatus = AsusFnStatusForUI(self->_preferences,hardware,self->_agentState);
            NSString *recovery = !fnStatus[@"FnSelectedHotkeys"] ? @"Use the touchpad key to enable it." :
                [fnStatus[@"FnSelectedHotkeys"] boolValue] ? @"Press F6 to enable it." : @"Press Fn + F6 to enable it.";
            self->_lastError = confirmed ? nil : error.localizedDescription ?: [@"The touchpad change was not confirmed. " stringByAppendingString:recovery];
            [self displayStatus]; [self refresh];
        });
    });
}
@end
