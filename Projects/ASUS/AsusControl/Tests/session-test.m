#import "../Source/PolicySession.h"
#import "../Source/Policy.h"
#import "../Source/DeviceClient.h"
#include <assert.h>
static NSMutableDictionary *hardware;
static NSMutableArray *commands;
static NSURL *directory;
static BOOL ignoreFn, rejectFn;
static NSMutableDictionary *systemState;
NSURL *AsusSupportDirectory(void) { return directory; }
NSDictionary *AsusControlReadStatus(void) { return hardware; }
BOOL AsusControlRefreshSettings(NSError **error) { (void)error; return YES; }
BOOL AsusControlSendCommand(BOOL keyboard,uint32_t value,NSError **error) { (void)keyboard;(void)value;(void)error; assert(0); return NO; }
BOOL AsusControlSendDeviceCommand(uint32_t value,NSError **error) {
    [commands addObject:@(value)];
    if(rejectFn && (value==3 || value==4)) {
        if(error)*error=[NSError errorWithDomain:@"test" code:5 userInfo:@{NSLocalizedDescriptionKey:@"Firmware did not accept the requested setting."}];
        return NO;
    }
    if(value>=7 && value<=9){hardware[@"ThermalProfile"]=@(value-7);hardware[@"FanRequestedMode"]=@0;}
    if(value<=2)hardware[@"ChargeLimitRequested"]=@(value==1?80:100);
    if((value==3 || value==4) && !ignoreFn)hardware[@"FnLockHotkeys"]=@(value==3);
    return YES;
}
@implementation AsusDeviceEnvironment
- (NSDictionary *)sample { return systemState; }
@end
static BOOL background(NSMutableDictionary *p,AsusDeviceEnvironment *environment,NSMutableDictionary *state,NSError **error) {
    [p setDictionary:AsusFanSessionPreferences(p,hardware,systemState,state)];
    return AsusApplyPolicyFamily(p,@"all",environment,state,error);
}
int main(void) { @autoreleasepool {
    directory=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    hardware=[@{@"BootSessionID":@"boot-a",@"DeviceControlAllowed":@YES,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0,
        @"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,@"BatteryCareAvailable":@YES} mutableCopy];
    systemState=[@{@"PowerSourceKnown":@YES,@"ACPower":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75}mutableCopy];
    commands=[NSMutableArray array];NSMutableDictionary *p=[AsusDefaultPreferences()mutableCopy],*state=[NSMutableDictionary dictionary];
    p[@"FanManaged"]=@YES;p[@"ManualProfile"]=@2;p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@NO;p[@"BatteryManaged"]=@YES;
    AsusDeviceEnvironment *environment=[[AsusDeviceEnvironment alloc]init];NSError *error=nil;
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    assert([commands isEqual:@[@9]] && !state[@"FnIntent"] && !state[@"ChargeIntent"]);
    assert([hardware[@"ThermalProfile"] isEqual:@2]);
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@9,@4]] && [state[@"FnIntent"] isEqual:AsusFnPolicyContext(p,hardware)]));
    // The agent must adopt an already-confirmed foreground selection without
    // issuing a duplicate hardware command.
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,[NSMutableDictionary dictionary],&error));
    assert(commands.count==2);
    hardware[@"FnLockHotkeys"]=@YES;ignoreFn=YES;[commands removeAllObjects];
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(state[@"FailedFamilies"][@"FnIntent"]);
    p[@"ManualProfile"]=@1;p[@"BatteryManaged"]=@NO;
    assert(!background(p,environment,state,&error));
    assert(([commands isEqual:@[@4,@8]]));
    assert([hardware[@"ThermalProfile"] isEqual:@1]);
    // Fn failure cannot block Standard fallback; reconnect must not resurrect
    // Performance after the saved selection has been retired.
    [commands removeAllObjects];p[@"ManualProfile"]=@2;
    assert(!background(p,environment,state,&error));
    systemState[@"ACPower"]=@NO;
    assert(!background(p,environment,state,&error));
    assert(([commands isEqual:@[@9,@7]]));
    assert([p[@"ManualProfile"]isEqual:@0]);
    systemState[@"ACPower"]=@YES;
    assert(!background(p,environment,state,&error));
    assert(([commands isEqual:@[@9,@7]]));
    p[@"ManualProfile"]=@2;
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    NSUInteger count=commands.count;
    systemState[@"BatteryPercent"]=@40;
    assert(!background(p,environment,state,&error));
    assert(commands.count==count && [p[@"ManualProfile"]isEqual:@2]);
    systemState[@"BatteryPercent"]=@39.9;
    assert(!background(p,environment,state,&error));
    assert([commands.lastObject isEqual:@7] && [p[@"ManualProfile"]isEqual:@0]);
    count=commands.count;systemState[@"BatteryPercent"]=@75;
    assert(!background(p,environment,state,&error) && commands.count==count);
    // A fresh manual choice is valid in this boot; another boot resets it.
    p[@"FnManaged"]=@NO;[state removeObjectForKey:@"FailedFamilies"];
    p[@"ManualProfile"]=@2;
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    hardware[@"BootSessionID"]=@"boot-b";
    assert(background(p,environment,state,&error));
    assert([p[@"ManualProfile"]isEqual:@0] && [commands.lastObject isEqual:@7]);
    p[@"ManualProfile"]=@2;
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    count=commands.count;
    assert(background(p,environment,state,&error) && commands.count==count);
    // An ineligible click is rejected; background retirement clears that
    // obsolete restriction without restoring Performance on reconnect.
    systemState[@"ACPower"]=@NO;
    assert(!AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    assert(background(p,environment,state,&error));
    assert(!state[@"FailedFamilies"][@"ThermalIntent"] && [p[@"ManualProfile"]isEqual:@0]);
    count=commands.count;systemState[@"ACPower"]=@YES;
    assert(background(p,environment,state,&error) && commands.count==count);
    // Charge requests are adopted within a session and refreshed after source
    // transitions or driver replacement, even when an old cache says 80.
    p[@"FanManaged"]=@NO;p[@"FnManaged"]=@NO;p[@"BatteryManaged"]=@YES;
    hardware[@"DriverSessionID"]=@"boot-a:100";systemState[@"ACPower"]=@NO;[commands removeAllObjects];
    assert(background(p,environment,state,&error));
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@1]]));
    systemState[@"ACPower"]=@YES;
    assert(background(p,environment,state,&error));
    hardware[@"DriverSessionID"]=@"boot-b:100";
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@1,@1,@1]]));
    // Deliberate selections always send once, even when mirror + intent match;
    // background reconciliation must then stay quiet.
    p[@"BatteryManaged"]=@NO;p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@YES;
    ignoreFn=NO;hardware[@"FnLockHotkeys"]=@YES;[state removeAllObjects];[commands removeAllObjects];
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@3]]));
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@3,@3]]));
    // A late status update clears the exact pending error without a second write.
    ignoreFn=YES;hardware[@"FnLockHotkeys"]=@NO;[commands removeAllObjects];
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert([state[@"FnPendingIntent"]isEqual:AsusFnPolicyContext(p,hardware)]);
    assert(!background(p,environment,state,&error));
    assert(([commands isEqual:@[@3]]));
    hardware[@"FnLockHotkeys"]=@YES;
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@3]]) && !state[@"FnPendingIntent"] && !state[@"FailedFamilies"][@"FnIntent"]);
    // Reloading the driver invalidates an old success even with the same mirror.
    hardware[@"DriverSessionID"]=@"boot-c:100";
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@3,@3]]));
    // An old pending request cannot clear a failure for the opposite selection.
    hardware[@"FnLockHotkeys"]=@NO;p[@"FnHotkeys"]=@YES;
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    p[@"FnHotkeys"]=@NO;hardware[@"FnLockHotkeys"]=@YES;
    assert(!background(p,environment,state,&error));
    assert(state[@"FailedFamilies"][@"FnIntent"]);
    // Migrate the actual reported condition without rewriting the working mode.
    hardware[@"FnLockReadbackReliable"]=@NO;hardware[@"FnLockHotkeys"]=@YES;
    p[@"FnHotkeys"]=@NO;[state removeAllObjects];[commands removeAllObjects];
    NSString *mismatch=@"Firmware acknowledged the function-key mode, but readback did not confirm it. Choose Try Again to reapply it.";
    state[@"FnPendingIntent"]=AsusFnPolicyContext(p,hardware);
    state[@"FailedFamilies"]=@{@"FnIntent":mismatch};state[@"Error"]=mismatch;
    assert(background(p,environment,state,&error));
    assert(commands.count==0 && !state[@"FailedFamilies"][@"FnIntent"] && !state[@"FnIntent"] && !state[@"Error"]);
    assert([AsusPolicyCompletionResult(p,hardware,state)isEqual:@"accepted"]);
    NSDictionary *display=AsusFnStatusForUI(p,hardware,state);
    assert(![display[@"FnSelectedHotkeys"]boolValue] && [display[@"FnSelectionSource"]isEqual:@"acknowledged"]);
    assert([display[@"FnLockHotkeys"]boolValue]); // Raw normalized mirror is preserved.
    assert(background(p,environment,state,&error) && commands.count==0);
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@4]]));
    assert(background(p,environment,state,&error) && commands.count==1);
    p[@"FnHotkeys"]=@YES;
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@4,@3]]) && !state[@"FnIntent"]);
    hardware[@"DriverSessionID"]=@"boot-d:100";
    assert(background(p,environment,state,&error));
    assert(([commands isEqual:@[@4,@3,@3]]));
    // A real write rejection stays an error even if a prior request succeeded.
    rejectFn=YES;
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error) && error.code==5);
    NSUInteger rejectedCount=commands.count;
    assert(!background(p,environment,state,&error));
    assert(commands.count==rejectedCount && state[@"FailedFamilies"][@"FnIntent"]);
    int first=AsusAcquirePolicyLock(0,&error);assert(first>=0);
    int second=AsusAcquirePolicyLock(0,&error);assert(second<0 && error.code==8);
    AsusReleasePolicyLock(first);second=AsusAcquirePolicyLock(0,&error);assert(second>=0);AsusReleasePolicyLock(second);
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    puts("PASS: profile transitions, stale Fn-error migration without writes, accepted-mode hints, real rejection preservation, session refresh and serialization. Fake driver only.");
} }
