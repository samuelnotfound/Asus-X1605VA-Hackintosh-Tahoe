#import "PolicySession.h"
#import "Preferences.h"
#import "Policy.h"
#import "DeviceClient.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
int AsusAcquirePolicyLock(unsigned waitMilliseconds, NSError **error) {
    if (![NSFileManager.defaultManager createDirectoryAtURL:AsusSupportDirectory() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return -1;
    NSURL *url=[AsusSupportDirectory() URLByAppendingPathComponent:@"policy.lock"];
    int descriptor=open(url.fileSystemRepresentation,O_CREAT|O_RDWR,0600);
    if(descriptor<0) { if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; return -1; }
    for(unsigned elapsed=0;;elapsed+=20) {
        if(flock(descriptor,LOCK_EX|LOCK_NB)==0) return descriptor;
        if(elapsed>=waitMilliseconds) break;
        usleep(20000);
    }
    close(descriptor);
    if(error)*error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:8 userInfo:@{NSLocalizedDescriptionKey:@"Another setting is finishing. Please try again."}];
    return -1;
}
void AsusReleasePolicyLock(int descriptor) { if(descriptor>=0) {flock(descriptor,LOCK_UN);close(descriptor);} }
static BOOL applyOne(NSDictionary *p,NSString *family,BOOL foreground,NSDictionary *system,NSMutableDictionary *state,NSError **error) {
    if(([family isEqual:@"ThermalIntent"] && ![p[@"FanManaged"] boolValue]) ||
        ([family isEqual:@"FnIntent"] && ![p[@"FnManaged"] boolValue]) ||
        ([family isEqual:@"keyboard"] && [p[@"BacklightSleepMode"] integerValue]==0 && ![state[@"Dimmed"] boolValue])) return YES;
    NSDictionary *hardware=AsusControlReadStatus();
    if(![hardware[@"DeviceControlAllowed"] boolValue]) {
        if(error)*error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:4 userInfo:@{NSLocalizedDescriptionKey:@"The driver has not enabled device controls."}];
        return NO;
    }
    BOOL fan=([family isEqual:@"all"] || [family isEqual:@"ThermalIntent"]) && [p[@"FanManaged"] boolValue];
    NSString *unavailable=nil;
    if(fan && (![hardware[@"ThermalProfileValid"] boolValue] || ![system[@"PowerSourceKnown"] boolValue])) unavailable=@"The current fan profile or power source is unavailable.";
    if(([family isEqual:@"all"] || [family isEqual:@"FnIntent"]) && [p[@"FnManaged"] boolValue] && ![hardware[@"FnLockAvailable"] boolValue]) unavailable=@"Function-key mode is unavailable with the current firmware.";
    if(fan && foreground && [family isEqual:@"ThermalIntent"] && AsusEffectiveProfile(p,system)!=[p[@"ManualProfile"] integerValue])
        unavailable=@"This profile is unavailable on the power source macOS currently reports. Connect the power adapter; Performance also requires more than 40% battery.";
    if(unavailable) { if(error)*error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:4 userInfo:@{NSLocalizedDescriptionKey:unavailable}];return NO; }
    NSMutableDictionary *decisionState=[state mutableCopy];
    // A deliberate Fn selection/retry must reach firmware even if its status
    // mirror already equals the requested value.
    if(foreground && [family isEqual:@"FnIntent"]) {
        [decisionState removeObjectForKey:@"FnIntent"];
        [decisionState removeObjectForKey:@"FnAcceptedIntent"];
    }
    NSArray *all=AsusPolicyActions(p,hardware,system,decisionState,NSDate.date.timeIntervalSince1970);
    NSMutableArray *selected=[NSMutableArray array];
    for(NSDictionary *action in all) {
        NSString *intent=action[@"IntentKey"];
        if([family isEqual:@"all"] || [intent isEqual:family] || ([family isEqual:@"keyboard"] && !intent)) [selected addObject:action];
    }
    return AsusExecutePolicyActions(selected,state,^BOOL(BOOL keyboard,uint32_t value,NSError **failure) {
        return keyboard ? AsusControlSendCommand(YES,value,failure) : AsusControlSendDeviceCommand(value,failure);
    },^NSDictionary *(NSError **failure) {
        return AsusControlRefreshSettings(failure) ? AsusControlReadStatus() : nil;
    },error);
}

BOOL AsusApplyPolicyFamily(NSDictionary *p,NSString *family,AsusDeviceEnvironment *environment,NSMutableDictionary *state,NSError **error) {
    if(error)*error=nil;
    AsusRetireChargingState(state);
    NSDictionary *hardware=AsusControlReadStatus();
    if(hardware[@"BootSessionID"]) state[@"FanBootSessionID"]=hardware[@"BootSessionID"];
    AsusRecoverFnReadbackState(p,hardware,state);
    NSMutableDictionary *failures=[state[@"FailedFamilies"] mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL all=[family isEqual:@"all"], requestedSucceeded=YES;
    NSMutableDictionary *system=[[environment sample] mutableCopy];
    system[@"PerformanceActive"]=@([hardware[@"ThermalProfileValid"] boolValue] &&
        [hardware[@"ThermalProfile"] integerValue]==2 && [hardware[@"FanRequestedMode"] integerValue]!=1);
    for(NSString *key in @[@"PerformanceOnBattery",@"PerformanceMinimumBattery",@"FullSpeedOnBattery"])
        if(hardware[key]) system[key]=hardware[key];
    NSDictionary *contexts=@{
        @"ThermalIntent":[NSString stringWithFormat:@"driver:%@:power:%@:effective:%ld:requested:%ld",
            hardware[@"DriverSessionID"] ?: hardware[@"DriverRegistryEntryID"] ?: @"unknown", system[@"PowerSourceKnown"] ? system[@"ACPower"] : @"unknown",
            (long)AsusEffectiveProfile(p,system),(long)[p[@"ManualProfile"] integerValue]],
        @"FnIntent":AsusFnPolicyContext(p,hardware)};
    NSMutableDictionary *failedContexts=[state[@"FailedFamilyContexts"] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Read-only recovery: an accepted Fn request can complete after the short
    // foreground observation window. Adopt only its exact target/session.
    if(all && AsusFnReadbackReliable(hardware) && failures[@"FnIntent"] && [p[@"FnManaged"] boolValue] &&
        [state[@"FnPendingIntent"] isEqual:contexts[@"FnIntent"]] &&
        [hardware[@"FnLockAvailable"] boolValue] && hardware[@"FnLockHotkeys"] &&
        [hardware[@"FnLockHotkeys"] boolValue]==[p[@"FnHotkeys"] boolValue]) {
        state[@"FnIntent"]=contexts[@"FnIntent"];
        [state removeObjectForKey:@"FnPendingIntent"];
        [failures removeObjectForKey:@"FnIntent"];
        [failedContexts removeObjectForKey:@"FnIntent"];
    }
    NSArray *families=all ? @[@"ThermalIntent",@"FnIntent",@"keyboard"] : @[family];
    for(NSString *item in families) {
        // A new effective target, driver session or power source gets one fresh
        // attempt. An unchanged failed request is not written every agent tick.
        if(all && failures[item] && contexts[item] && ![failedContexts[item] isEqual:contexts[item]])
            [failures removeObjectForKey:item];
        if(all && failures[item]) continue;
        NSError *failure=nil;
        if(applyOne(p,item,!all,system,state,&failure)) {
            [failures removeObjectForKey:item]; [failedContexts removeObjectForKey:item];
        }
        else {
            requestedSucceeded=NO;
            failures[item]=failure.localizedDescription ?: @"The setting could not be confirmed.";
            if(contexts[item]) failedContexts[item]=contexts[item];
            if(error)*error=failure;
        }
    }
    state[@"FailedFamilies"]=failures;
    state[@"FailedFamilyContexts"]=failedContexts;
    if(all && failures.count && error && !*error)
        *error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:9 userInfo:@{NSLocalizedDescriptionKey:failures.allValues.firstObject}];
    return requestedSucceeded && (!all || failures.count==0);
}
