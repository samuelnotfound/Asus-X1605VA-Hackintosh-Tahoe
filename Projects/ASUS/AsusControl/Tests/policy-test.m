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
    p=[AsusDefaultPreferences()mutableCopy];p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@NO;
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"device")[@"Value"]isEqual:@4]);
    h[@"FnLockHotkeys"]=@NO;
    assert(action(AsusPolicyActions(p,h,s,@{},1000),@"remember"));
    p=[AsusDefaultPreferences()mutableCopy];p[@"BacklightSleepMode"]=@1;s[@"IdleSeconds"]=@60;
    assert([action(AsusPolicyActions(p,h,s,@{},1000),@"keyboard")[@"Value"]isEqual:@0]);
    h[@"KeyboardPercent"]=@0;s[@"IdleSeconds"]=@0;
    assert([action(AsusPolicyActions(p,h,s,@{@"Dimmed":@YES,@"RestoreKeyboard":@67},1000),@"keyboard")[@"Value"]isEqual:@67]);
    NSDictionary *request=@{@"Kind":@"device",@"Value":@8,@"IntentKey":@"ThermalIntent",@"Intent":@"whisper"};
    NSMutableDictionary *state=[NSMutableDictionary dictionary];__block unsigned sends=0;NSError *error=nil;
    BOOL result=AsusExecutePolicyActions(@[request],state,^BOOL(BOOL keyboard,uint32_t value,NSError **failure){(void)keyboard;(void)value;(void)failure;sends++;return YES;},
      ^NSDictionary *(NSError **failure){(void)failure;return @{@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0};},&error);
    assert(!result && sends==1 && error.code==9 && !state[@"ThermalIntent"]);
    puts("PASS: direct profiles, capability restrictions, battery deadline, Fn/idle state and readback mismatch. No switching policies.");
} }
