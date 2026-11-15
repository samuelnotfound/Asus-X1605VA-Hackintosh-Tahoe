// Copyright (c) 2026 samuelnotfound. MIT License.
#import "AsusControlPane.h"
#import "PaneActions.h"
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "SystemStatus.h"
#import "AsusControlUI-Swift.h"

@interface AsusControlPane () <AsusPaneActions> {
    AsusSettingsUI *_ui;
    dispatch_queue_t _worker;
    NSTimer *_timer;
    AsusSystemStatus *_monitor;
    NSDictionary *_hardware, *_system, *_preferences, *_agentState;
    BOOL _active, _refreshing, _busy, _refreshStopped;
    NSString *_lastError;
    NSTimeInterval _submittedAt;
}
@end
@implementation AsusControlPane
- (NSView *)loadMainView {
    if (self.mainView) return self.mainView;
    _worker = dispatch_queue_create("com.samuelnotfound.AsusControl.controls", DISPATCH_QUEUE_SERIAL);
    _monitor = [[AsusSystemStatus alloc] init];
    _preferences = AsusReadPreferences();
    _ui = [[AsusSettingsUI alloc] initWithActions:self];
    [self setMainView:[_ui makeView]];
    [self displayStatus];
    return self.mainView;
}
- (void)didSelect {
    _active = YES; _refreshStopped = NO; _lastError = nil;
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
            if (error.code == 6) { self->_refreshStopped = YES; self->_lastError = error.localizedDescription; }
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
    if (![preferences[@"FanManaged"] boolValue] && ![preferences[@"SplitProfiles"] boolValue] && ![preferences[@"FollowLowPower"] boolValue])
        preferences[@"ManualProfile"] = [_hardware[@"FanRequestedMode"] integerValue] == 1 ? @3 : _hardware[@"ThermalProfile"] ?: @0;
    NSString *message = @""; BOOL failed = NO;
    if (_lastError.length) { message = _lastError; failed = YES; }
    else if (_busy) message = @"Applying settings…";
    else if (![_hardware[@"DeviceControlAllowed"] boolValue])
        message = @"Device controls require the matching AsusSMC driver and hardware-profile boot arguments.";
    else if (AsusNeedsAgent(preferences)) {
        BOOL same = [_agentState[@"Revision"] isEqual:preferences[@"Revision"]];
        if (same && [_agentState[@"Result"] isEqual:@"failed"]) {
            message = _agentState[@"Error"] ?: @"The setting could not be confirmed."; failed = YES;
        } else if (!same || [_agentState[@"Result"] isEqual:@"applying"]) {
            NSTimeInterval started = same ? [_agentState[@"UpdatedAt"] doubleValue] : (_submittedAt ?: [_agentState[@"UpdatedAt"] doubleValue]);
            NSTimeInterval age = NSDate.date.timeIntervalSince1970 - started;
            message = age > 30 ? @"Automatic settings have not responded. Choose Try Again to restart them." : @"Applying settings…";
            failed = age > 30;
        } else {
            // The UI reports completion only for this saved revision.
            message = @"Settings applied.";
        }
    }
    NSString *version = [NSString stringWithFormat:@"ASUS Control %s · AsusSMC %@", ASUS_CONTROL_VERSION, _hardware[@"AsusSMC-Version"] ?: @"Unavailable"];
    [_ui updateWithHardware:_hardware ?: @{} system:_system ?: @{} preferences:preferences message:message error:failed busy:_busy version:version];
}
- (void)savePreferences:(NSDictionary *)preferences {
    if (_busy) return;
    _busy = YES; _lastError = nil; [self displayStatus];
    NSDictionary *before = _preferences;
    dispatch_async(_worker, ^{
        NSError *error = nil; BOOL success = AsusConfigureAgent(self.bundle, preferences, &error);
        if (!success) AsusWritePreferences(before, NULL);
        NSDictionary *saved = success ? AsusReadPreferences() : before;
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO; self->_preferences = saved;
            self->_submittedAt = NSDate.date.timeIntervalSince1970;
            self->_lastError = success ? nil : error.localizedDescription ?: @"Automatic settings could not start.";
            [self displayStatus]; [self refresh];
        });
    });
}
- (void)changeSetting:(NSString *)key value:(id)value {
    if (_busy || ![_hardware[@"DeviceControlAllowed"] boolValue] || ![value isKindOfClass:NSNumber.class]) return;
    NSMutableDictionary *preferences = [_preferences mutableCopy]; NSInteger number = [value integerValue];
    if ([@[@"ManualProfile",@"ACProfile",@"BatteryProfile"] containsObject:key]) {
        if (number < 0 || number > 3) return;
        preferences[key] = @(number); preferences[@"FanManaged"] = @YES;
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
    [self savePreferences:preferences];
}
- (void)selectProfileMode:(NSInteger)mode {
    if (_busy || mode < 0 || mode > 3 || ![_hardware[@"DeviceControlAllowed"] boolValue]) return;
    NSMutableDictionary *preferences = [_preferences mutableCopy];
    preferences[@"SplitProfiles"] = @((mode & 1) != 0);
    preferences[@"FollowLowPower"] = @((mode & 2) != 0);
    preferences[@"FanManaged"] = @YES;
    if (![_preferences[@"FanManaged"] boolValue]) preferences[@"ManualProfile"] = [_hardware[@"FanRequestedMode"] integerValue] == 1 ? @3 : _hardware[@"ThermalProfile"] ?: @0;
    [self savePreferences:preferences];
}
- (void)retrySettings { _refreshStopped = NO; [self savePreferences:_preferences]; }
- (void)setTouchpadEnabled:(BOOL)enabled {
    if (_busy || ![_hardware[@"TrackpadControlAvailable"] boolValue]) return;
    _busy = YES; _lastError = nil; [self displayStatus];
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
            self->_lastError = confirmed ? nil : error.localizedDescription ?: @"The touchpad change was not confirmed. Press Fn + F6 to enable it.";
            [self displayStatus]; [self refresh];
        });
    });
}
- (void)openSystemTool:(NSString *)tool {
    if ([tool isEqual:@"activity"]) {
        NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.ActivityMonitor"];
        if (url) [NSWorkspace.sharedWorkspace openURL:url];
    } else if ([tool isEqual:@"storage"]) [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.settings.Storage"]];
}
@end
