#import "../Source/PolicySession.h"
#import "../Source/Policy.h"
#import "../Source/DeviceClient.h"
#include <assert.h>
static NSMutableDictionary *hardware;
static NSMutableArray *commands;
static NSURL *directory;
NSURL *AsusSupportDirectory(void) { return directory; }
NSDictionary *AsusControlReadStatus(void) { return hardware; }
BOOL AsusControlRefreshSettings(NSError **error) { (void)error; return YES; }
BOOL AsusControlSendCommand(BOOL keyboard,uint32_t value,NSError **error) { (void)keyboard;(void)value;(void)error; assert(0); return NO; }
BOOL AsusControlSendDeviceCommand(uint32_t value,NSError **error) {
    (void)error;[commands addObject:@(value)];
    if(value>=7 && value<=9){hardware[@"ThermalProfile"]=@(value-7);hardware[@"FanRequestedMode"]=@0;}
    if(value==4)hardware[@"FnLockHotkeys"]=@NO;
    return YES;
}
@implementation AsusDeviceEnvironment
- (NSDictionary *)sample { return @{@"PowerSourceKnown":@YES,@"ACPower":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75}; }
@end
int main(void) { @autoreleasepool {
    directory=[[NSURL fileURLWithPath:NSTemporaryDirectory()]URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    hardware=[@{@"DeviceControlAllowed":@YES,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0,
        @"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,@"BatteryCareAvailable":@YES} mutableCopy];
    commands=[NSMutableArray array];NSMutableDictionary *p=[AsusDefaultPreferences()mutableCopy],*state=[NSMutableDictionary dictionary];
    p[@"FanManaged"]=@YES;p[@"ManualProfile"]=@2;p[@"FnManaged"]=@YES;p[@"FnHotkeys"]=@NO;p[@"BatteryManaged"]=@YES;
    AsusDeviceEnvironment *environment=[[AsusDeviceEnvironment alloc]init];NSError *error=nil;
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,state,&error));
    assert([commands isEqual:@[@9]] && !state[@"FnIntent"] && !state[@"ChargeIntent"]);
    assert([hardware[@"ThermalProfile"] isEqual:@2]);
    assert(AsusApplyPolicyFamily(p,@"FnIntent",environment,state,&error));
    assert(([commands isEqual:@[@9,@4]] && [state[@"FnIntent"] isEqual:@"fn:functions"]));
    // The agent must adopt an already-confirmed foreground selection without
    // issuing a duplicate hardware command.
    assert(AsusApplyPolicyFamily(p,@"ThermalIntent",environment,[NSMutableDictionary dictionary],&error));
    assert(commands.count==2);
    int first=AsusAcquirePolicyLock(0,&error);assert(first>=0);
    int second=AsusAcquirePolicyLock(0,&error);assert(second<0 && error.code==8);
    AsusReleasePolicyLock(first);second=AsusAcquirePolicyLock(0,&error);assert(second>=0);AsusReleasePolicyLock(second);
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    puts("PASS: foreground fan/Fn isolation, immediate execution, no duplicate agent write, and cross-process serialization. Fake driver only.");
} }
