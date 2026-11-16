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
int main(void) { @autoreleasepool {
    directory=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    hardware=[@{@"DeviceControlAllowed":@YES,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0,
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
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@4,@8]]));
    assert([hardware[@"ThermalProfile"] isEqual:@1]);
    // Cached Fn failures cannot block AC fallback or restoration.
    [commands removeAllObjects];p[@"ManualProfile"]=@2;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    systemState[@"ACPower"]=@NO;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@9,@7]]));
    assert([p[@"ManualProfile"] isEqual:@2] && [hardware[@"ThermalProfile"] isEqual:@0]);
    systemState[@"ACPower"]=@YES;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@9,@7,@9]]));
    systemState[@"BatteryPercent"]=@40;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert([commands.lastObject isEqual:@7]);
    systemState[@"BatteryPercent"]=@75;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert([commands.lastObject isEqual:@9]);
    // An explicit ineligible click is rejected, but does not poison later
    // background Standard fallback or eligible Performance restoration.
    systemState[@"ACPower"]=@NO;
    assert(!AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    NSUInteger count=commands.count;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(commands.count==count); // Same failed context stays stopped.
    systemState[@"ACPower"]=@YES;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(!state[@"FailedFamilies"][@"ThermalIntent"]);
    // Migrate the former background restriction failure once, not every tick.
    p[@"FnManaged"]=@NO;
    state[@"FailedFamilies"]=@{@"ThermalIntent":@"Old restriction"};
    [state removeObjectForKey:@"FailedFamilyContexts"];
    systemState[@"ACPower"]=@NO;
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert([hardware[@"ThermalProfile"] isEqual:@0]);
    // Charge requests are adopted within a session and refreshed after source
    // transitions or driver replacement, even when an old cache says 80.
    p[@"FanManaged"]=@NO;p[@"FnManaged"]=@NO;p[@"BatteryManaged"]=@YES;
    hardware[@"DriverSessionID"]=@"boot-a:100";[commands removeAllObjects];
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@1]]));
    systemState[@"ACPower"]=@YES;
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    hardware[@"DriverSessionID"]=@"boot-b:100";
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@1,@1,@1]]));
    // Enabling automatic mode is valid even when ManualProfile is Standard.
    p[@"BatteryManaged"]=@NO;p[@"FnManaged"]=@NO;p[@"FanManaged"]=@YES;
    p[@"ManualProfile"]=@0;p[@"AutoPerformanceOnAC"]=@YES;
    hardware[@"ThermalProfile"]=@0;systemState[@"ACPower"]=@YES;[state removeAllObjects];[commands removeAllObjects];
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    systemState[@"ACPower"]=@NO;assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    systemState[@"ACPower"]=@YES;assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@9,@7,@9]]));
    p[@"AutoPerformanceOnAC"]=@NO;p[@"FanManaged"]=@NO;
    // Deliberate selections always send once, even when mirror + intent match;
    // background reconciliation must then stay quiet.
    p[@"BatteryManaged"]=@NO;p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@YES;
    ignoreFn=NO;hardware[@"FnLockHotkeys"]=@YES;[state removeAllObjects];[commands removeAllObjects];
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@3]]));
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@3,@3]]));
    // A late status update clears the exact pending error without a second write.
    ignoreFn=YES;hardware[@"FnLockHotkeys"]=@NO;[commands removeAllObjects];
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert([state[@"FnPendingIntent"]isEqual:AsusFnPolicyContext(p,hardware)]);
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@3]]));
    hardware[@"FnLockHotkeys"]=@YES;
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@3]]) && !state[@"FnPendingIntent"] && !state[@"FailedFamilies"][@"FnIntent"]);
    // Reloading the driver invalidates an old success even with the same mirror.
    hardware[@"DriverSessionID"]=@"boot-c:100";
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@3,@3]]));
    // An old pending request cannot clear a failure for the opposite selection.
    hardware[@"FnLockHotkeys"]=@NO;p[@"FnHotkeys"]=@YES;
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    p[@"FnHotkeys"]=@NO;hardware[@"FnLockHotkeys"]=@YES;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(state[@"FailedFamilies"][@"FnIntent"]);
    // Migrate the actual reported condition without rewriting the working mode.
    hardware[@"FnLockReadbackReliable"]=@NO;hardware[@"FnLockHotkeys"]=@YES;
    p[@"FnHotkeys"]=@NO;[state removeAllObjects];[commands removeAllObjects];
    NSString *mismatch=@"Firmware acknowledged the function-key mode, but readback did not confirm it. Choose Try Again to reapply it.";
    state[@"FnPendingIntent"]=AsusFnPolicyContext(p,hardware);
    state[@"FailedFamilies"]=@{@"FnIntent":mismatch};state[@"Error"]=mismatch;
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(commands.count==0 && !state[@"FailedFamilies"][@"FnIntent"] && !state[@"FnIntent"] && !state[@"Error"]);
    assert([AsusPolicyCompletionResult(p,hardware,state)isEqual:@"accepted"]);
    NSDictionary *display=AsusFnStatusForUI(p,hardware,state);
    assert(![display[@"FnSelectedHotkeys"]boolValue] && [display[@"FnSelectionSource"]isEqual:@"acknowledged"]);
    assert([display[@"FnLockHotkeys"]boolValue]); // Raw normalized mirror is preserved.
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error) && commands.count==0);
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@4]]));
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error) && commands.count==1);
    p[@"FnHotkeys"]=@YES;
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@4,@3]]) && !state[@"FnIntent"]);
    hardware[@"DriverSessionID"]=@"boot-d:100";
    assert(AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(([commands isEqual:@[@4,@3,@3]]));
    // A real write rejection stays an error even if a prior request succeeded.
    rejectFn=YES;
    assert(!AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error) && error.code==5);
    NSUInteger rejectedCount=commands.count;
    assert(!AsusApplyPolicyFamily(p,@"all",environment,state,&error));
    assert(commands.count==rejectedCount && state[@"FailedFamilies"][@"FnIntent"]);
    int first=AsusAcquirePolicyLock(0,&error);assert(first>=0);
    int second=AsusAcquirePolicyLock(0,&error);assert(second<0 && error.code==8);
    AsusReleasePolicyLock(first);second=AsusAcquirePolicyLock(0,&error);assert(second>=0);AsusReleasePolicyLock(second);
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    puts("PASS: profile transitions, stale Fn-error migration without writes, accepted-mode hints, real rejection preservation, session refresh and serialization. Fake driver only.");
} }
