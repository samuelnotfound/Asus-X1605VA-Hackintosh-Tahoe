#import "../Source/Policy.h"
#include <assert.h>
static NSDictionary *action(NSArray *actions, NSString *kind) {
    for (NSDictionary *item in actions) if ([item[@"Kind"] isEqual:kind]) return item;
    return nil;
}
int main(void) {
    @autoreleasepool {
        NSMutableDictionary *p = [AsusDefaultPreferences() mutableCopy];
        NSDictionary *h = @{@"DeviceControlAllowed":@YES, @"BatteryCareAvailable":@YES,
            @"ThermalProfileValid":@YES, @"FnLockAvailable":@YES,
            @"KeyboardReadingValid":@YES, @"KeyboardControlAvailable":@YES, @"KeyboardPercent":@67};
        NSMutableDictionary *s = [@{@"PowerSourceKnown":@YES, @"ACPower":@YES, @"BatteryKnown":@YES,
            @"BatteryPercent":@75, @"LowPowerMode":@NO, @"IdleSeconds":@0} mutableCopy];
        assert(!AsusNeedsAgent(p));
        assert(AsusPolicyActions(p,h,s,@{},1000).count == 0);
        p[@"BatteryManaged"]=@YES;
        assert(AsusNeedsAgent(p));
        assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"] isEqual:@1]);
        p[@"FullChargeUntil"]=@(1000+86400);
        assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"] isEqual:@2]);
        assert([action(AsusPolicyActions(p,h,s,@{},87400),@"device")[@"Value"] isEqual:@1]);
        assert(AsusPolicyActions(p,h,s,@{@"ChargeIntent":@"charge:100"},1000).count == 0);
        p[@"BatteryCare"]=@NO;
        assert([action(AsusPolicyActions(p,h,s,@{},87400),@"device")[@"Value"] isEqual:@2]);
        p=[AsusDefaultPreferences() mutableCopy]; p[@"SplitProfiles"]=@YES; p[@"ACProfile"]=@2; p[@"BatteryProfile"]=@1;
        assert(AsusEffectiveProfile(p,s)==2);
        assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"] isEqual:@9]);
        s[@"BatteryPercent"]=@40; assert(AsusEffectiveProfile(p,s)==0);
        s[@"BatteryPercent"]=@41; assert(AsusEffectiveProfile(p,s)==2);
        s[@"BatteryKnown"]=@NO; assert(AsusEffectiveProfile(p,s)==0);
        s[@"BatteryKnown"]=@YES; s[@"ACPower"]=@NO;
        assert(AsusEffectiveProfile(p,s)==1);
        p[@"BatteryProfile"]=@2; assert(AsusEffectiveProfile(p,s)==0);
        s[@"PerformanceOnBattery"]=@YES; assert(AsusEffectiveProfile(p,s)==2);
        p[@"BatteryProfile"]=@3; assert(AsusEffectiveProfile(p,s)==0);
        s[@"FullSpeedOnBattery"]=@YES; assert(AsusEffectiveProfile(p,s)==3);
        p[@"FollowLowPower"]=@YES; s[@"LowPowerMode"]=@YES; assert(AsusEffectiveProfile(p,s)==1);
        NSDictionary *a=action(AsusPolicyActions(p,h,s,@{},1000),@"device");
        assert([a[@"Value"] isEqual:@8]);
        NSMutableDictionary *matching = [h mutableCopy]; matching[@"ThermalProfile"] = @1; matching[@"FanRequestedMode"] = @0;
        assert(AsusPolicyActions(p,matching,s,@{@"ThermalIntent":a[@"Intent"]},1000).count==0);
        matching[@"ThermalProfile"] = @0;
        assert(AsusPolicyActions(p,matching,s,@{@"ThermalIntent":a[@"Intent"]},1000).count==1);
        p=[AsusDefaultPreferences() mutableCopy]; p[@"FnManaged"]=@YES;
        assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"] isEqual:@3]);
        p[@"FnHotkeys"]=@NO;
        assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"] isEqual:@4]);
        p=[AsusDefaultPreferences() mutableCopy]; p[@"BacklightSleepMode"]=@1;
        s[@"IdleSeconds"]=@60;
        a=action(AsusPolicyActions(p,h,s,@{},1000),@"keyboard");
        assert([a[@"Value"] isEqual:@0] && [a[@"SaveKeyboard"] isEqual:@67]);
        NSDictionary *dim=@{@"Dimmed":@YES,@"RestoreKeyboard":@67};
        NSMutableDictionary *off=[h mutableCopy]; off[@"KeyboardPercent"]=@0;
        assert(AsusPolicyActions(p,off,s,dim,1000).count==0);
        s[@"IdleSeconds"]=@0;
        a=action(AsusPolicyActions(p,off,s,dim,1000),@"keyboard");
        assert([a[@"Value"] isEqual:@67] && [a[@"Restore"] boolValue]);
        assert(action(AsusPolicyActions(p,h,s,dim,1000),@"clear-dim"));
        p[@"BacklightSleepMode"]=@2; s[@"ACPower"]=@YES; s[@"IdleSeconds"]=@100;
        assert(AsusPolicyActions(p,h,s,@{},1000).count==0);
        p[@"BacklightSleepMode"]=@1;
        assert(AsusPolicyActions(p,@{},s,@{},1000).count==0);
        NSMutableDictionary *missing=[h mutableCopy]; missing[@"KeyboardReadingValid"]=@NO;
        assert(AsusPolicyActions(p,missing,s,@{},1000).count==0);
        // Manual and Low Power Mode policies use one common profile. No AC/battery
        // controls compete when source-based switching is off.
        p=[AsusDefaultPreferences() mutableCopy]; p[@"FanManaged"]=@YES; p[@"ManualProfile"]=@1;
        s[@"ACPower"]=@YES; s[@"LowPowerMode"]=@NO;
        assert(AsusNeedsAgent(p) && AsusEffectiveProfile(p,s)==1);
        p[@"FollowLowPower"]=@YES; p[@"ManualProfile"]=@0;
        s[@"LowPowerMode"]=@YES; assert(AsusEffectiveProfile(p,s)==1);
        s[@"LowPowerMode"]=@NO; assert(AsusEffectiveProfile(p,s)==0);
        NSDictionary *request=@{@"Kind":@"device",@"Value":@8,@"IntentKey":@"ThermalIntent",@"Intent":@"test"};
        NSMutableDictionary *confirmedState=[NSMutableDictionary dictionary];
        __block unsigned sends=0, reads=0;
        NSError *failure=nil;
        BOOL result=AsusExecutePolicyActions(@[request],confirmedState,^BOOL(BOOL keyboard,uint32_t value,NSError **error) {
            (void)error; assert(!keyboard && value==8); sends++; return YES;
        },^NSDictionary *(NSError **error) {
            (void)error; reads++; return @{@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0};
        },&failure);
        assert(!result && sends==1 && reads==3 && failure.code==9 && !confirmedState[@"ThermalIntent"]);
        result=AsusExecutePolicyActions(@[request],confirmedState,^BOOL(BOOL keyboard,uint32_t value,NSError **error) {
            (void)keyboard; (void)value; (void)error; sends++; return YES;
        },^NSDictionary *(NSError **error) {
            (void)error; return @{@"ThermalProfileValid":@YES,@"ThermalProfile":@1,@"FanRequestedMode":@0};
        },&failure);
        assert(result && [confirmedState[@"ThermalIntent"] isEqual:@"test"]);
        puts("PASS: battery deadline, source/LPM profiles, model restrictions, intent deduplication, Fn mode, and idle restore.");
    }
}
