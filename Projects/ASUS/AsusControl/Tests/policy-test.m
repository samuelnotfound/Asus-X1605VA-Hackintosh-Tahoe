#import "../Source/Policy.h"
#include <assert.h>
static NSDictionary *action(NSArray *items,NSString *kind) {for(NSDictionary *a in items)if([a[@"Kind"]isEqual:kind])return a;return nil;}
int main(void) { @autoreleasepool {
    NSMutableDictionary *p=[AsusDefaultPreferences()mutableCopy];
    NSMutableDictionary *h=[@{@"DeviceControlAllowed":@YES,@"BatteryCareAvailable":@YES,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,
        @"FanRequestedMode":@0,@"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,@"KeyboardReadingValid":@YES,@"KeyboardControlAvailable":@YES,@"KeyboardPercent":@67}mutableCopy];
    NSMutableDictionary *s=[@{@"PowerSourceKnown":@YES,@"ACPower":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75,@"IdleSeconds":@0}mutableCopy];
    assert(!AsusNeedsAgent(p));p[@"BatteryManaged"]=@YES;assert(AsusNeedsAgent(p));
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@1]);
    p[@"FullChargeUntil"]=@87400;
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@2]);
    assert([action(AsusPolicyActions(p,h,s,@{},87400),@"device")[@"Value"]isEqual:@1]);
    p=[AsusDefaultPreferences()mutableCopy];p[@"FanManaged"]=@YES;p[@"ManualProfile"]=@2;
    assert(AsusEffectiveProfile(p,s)==2);
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@9]);
    s[@"BatteryPercent"]=@40;assert(AsusEffectiveProfile(p,s)==0);
    s[@"BatteryPercent"]=@75;s[@"ACPower"]=@NO;assert(AsusEffectiveProfile(p,s)==0);
    p[@"ManualProfile"]=@3;assert(AsusEffectiveProfile(p,s)==0);
    s[@"ACPower"]=@YES;assert(AsusEffectiveProfile(p,s)==3);
    // Manual Performance expires after reboot or eligibility loss. Old auto
    // preferences cannot restore it when power returns.
    p[@"ManualProfile"]=@2;p[@"AutoPerformanceOnAC"]=@YES;
    h[@"BootSessionID"]=@"boot-a";h[@"ThermalProfile"]=@2;
    NSDictionary *session=@{@"FanBootSessionID":@"boot-a"};
    s[@"ACPower"]=@YES;s[@"BatteryPercent"]=@40;s[@"PerformanceActive"]=@YES;
    assert(AsusEffectiveProfile(p,s)==2);
    assert([AsusFanSessionPreferences(p,h,s,session)[@"ManualProfile"]intValue]==2);
    s[@"BatteryPercent"]=@39.9;
    NSDictionary *expired=AsusFanSessionPreferences(p,h,s,session);
    assert([expired[@"ManualProfile"]intValue]==0 && !expired[@"AutoPerformanceOnAC"]);
    s[@"BatteryPercent"]=@75;
    assert([AsusFanSessionPreferences(expired,h,s,session)[@"ManualProfile"]intValue]==0);
    assert([AsusFanSessionPreferences(p,h,s,@{@"FanBootSessionID":@"previous-boot"})[@"ManualProfile"]intValue]==0);
    assert([AsusFanSessionPreferences(p,h,s,@{})[@"ManualProfile"]intValue]==0);
    s[@"ACPower"]=@NO;
    expired=AsusFanSessionPreferences(p,h,s,session);
    s[@"ACPower"]=@YES;
    assert([AsusFanSessionPreferences(expired,h,s,session)[@"ManualProfile"]intValue]==0);
    [s removeObjectForKey:@"PerformanceActive"];
    p=[AsusDefaultPreferences()mutableCopy];p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@NO;
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@4]);
    h[@"FnLockHotkeys"]=@NO;
    // A matching mirror alone cannot substitute for sending the selection.
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@4]);
    h[@"DriverSessionID"]=@"boot-a:1";
    NSDictionary *appliedFn=@{@"FnIntent":AsusFnPolicyContext(p,h)};
    assert(AsusPolicyActions(p,h,s,appliedFn,1000).count==0);
    h[@"DriverSessionID"]=@"boot-b:1";
    assert(action(AsusPolicyActions(p,h,s,appliedFn,1000),@"device"));
    p=[AsusDefaultPreferences()mutableCopy];p[@"BacklightSleepMode"]=@1;s[@"IdleSeconds"]=@60;
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"keyboard")[@"Value"]isEqual:@0]);
    h[@"KeyboardPercent"]=@0;s[@"IdleSeconds"]=@0;
    assert([action(AsusPolicyActions(p,h,s,@{@"Dimmed":@YES,@"RestoreKeyboard":@67},1000),@"keyboard")[@"Value"]isEqual:@67]);
    NSDictionary *request=@{@"Kind":@"device",@"Value":@8,@"IntentKey":@"ThermalIntent",@"Intent":@"whisper"};
    NSMutableDictionary *state=[NSMutableDictionary dictionary];__block unsigned sends=0;NSError *error=nil;
    BOOL result=AsusExecutePolicyActions(@[request],state,^BOOL(BOOL keyboard,uint32_t value,NSError **failure){(void)keyboard;(void)value;(void)failure;sends++;return YES;},
      ^NSDictionary *(NSError **failure){(void)failure;return @{@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0};},&error);
    assert(!result && sends==1 && error.code==9 && !state[@"ThermalIntent"]);
    // Fn mirror changes asynchronously: poll reads while sending exactly once.
    NSDictionary *fn=@{@"Kind":@"device",@"Value":@3,@"IntentKey":@"FnIntent",@"Intent":@"fn:test"};
    [state removeAllObjects];sends=0;__block unsigned reads=0;
    result=AsusExecutePolicyActions(@[fn],state,^BOOL(BOOL keyboard,uint32_t value,NSError **failure){(void)keyboard;(void)value;(void)failure;sends++;return YES;},
      ^NSDictionary *(NSError **failure){(void)failure;reads++;return @{@"FnLockAvailable":@YES,@"FnLockHotkeys":@(reads>=5)};},&error);
    assert(result && sends==1 && reads==5 && [state[@"FnIntent"]isEqual:@"fn:test"] && !state[@"FnPendingIntent"]);
    // A known stale mirror cannot establish failure or physical verification.
    NSMutableDictionary *acceptedAction=[fn mutableCopy];acceptedAction[@"FnReadbackReliable"]=@NO;
    [state removeAllObjects];sends=0;reads=0;
    result=AsusExecutePolicyActions(@[acceptedAction],state,^BOOL(BOOL keyboard,uint32_t value,NSError **failure){(void)keyboard;(void)value;(void)failure;sends++;return YES;},
      ^NSDictionary *(NSError **failure){(void)failure;reads++;return @{};},&error);
    assert(result && sends==1 && reads==0 && [state[@"FnAcceptedIntent"]isEqual:@"fn:test"] && !state[@"FnIntent"]);
    assert([state[@"FnVerification"]isEqual:@"acknowledged"]);
    // Recovery is limited to the exact prior accepted readback mismatch. Keep
    // unrelated errors and never promote a transport failure to accepted.
    p=[AsusDefaultPreferences()mutableCopy];p[@"FnManaged"]=@YES;
    h[@"FnLockReadbackReliable"]=@NO;
    NSString *intent=AsusFnPolicyContext(p,h);
    NSString *mismatch=@"Firmware acknowledged the function-key mode, but readback did not confirm it. Choose Try Again to reapply it.";
    state=[@{@"FnPendingIntent":intent,@"FailedFamilies":@{@"FnIntent":mismatch,@"ChargeIntent":@"Charge rejected"},@"Error":mismatch}mutableCopy];
    AsusRecoverFnReadbackState(p,h,state);
    assert([state[@"FnAcceptedIntent"]isEqual:intent] && !state[@"FailedFamilies"][@"FnIntent"]);
    assert([state[@"FailedFamilies"][@"ChargeIntent"]isEqual:@"Charge rejected"] && [state[@"Error"]isEqual:@"Charge rejected"]);
    state=[@{@"FnPendingIntent":intent,@"FailedFamilies":@{@"FnIntent":@"The driver rejected the request."}}mutableCopy];
    AsusRecoverFnReadbackState(p,h,state);
    assert(state[@"FailedFamilies"][@"FnIntent"] && !state[@"FnAcceptedIntent"]);
    puts("PASS: manual profiles and restart/power resets, restrictions, deadlines, strict Fn readback, acknowledgement-only state and error-preserving recovery.");
} }
