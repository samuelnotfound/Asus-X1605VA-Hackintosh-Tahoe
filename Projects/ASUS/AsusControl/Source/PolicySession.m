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
BOOL AsusApplyPolicyFamily(NSDictionary *p,NSString *family,AsusDeviceEnvironment *environment,NSMutableDictionary *state,NSError **error) {
    NSDictionary *hardware=AsusControlReadStatus();
    if(![hardware[@"DeviceControlAllowed"] boolValue]) {
        if(error)*error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:4 userInfo:@{NSLocalizedDescriptionKey:@"The driver has not enabled device controls."}];
        return NO;
    }
    NSMutableDictionary *system=[[environment sample] mutableCopy];
    for(NSString *key in @[@"PerformanceOnBattery",@"PerformanceMinimumBattery",@"FullSpeedOnBattery"])
        if(hardware[key]) system[key]=hardware[key];
    BOOL fan=([family isEqual:@"all"] || [family isEqual:@"ThermalIntent"]) && [p[@"FanManaged"] boolValue];
    NSString *unavailable=nil;
    if(fan && (![hardware[@"ThermalProfileValid"] boolValue] || ![system[@"PowerSourceKnown"] boolValue])) unavailable=@"The current fan profile or power source is unavailable.";
    if(([family isEqual:@"all"] || [family isEqual:@"FnIntent"]) && [p[@"FnManaged"] boolValue] && ![hardware[@"FnLockAvailable"] boolValue]) unavailable=@"Function-key mode is unavailable with the current firmware.";
    if(([family isEqual:@"all"] || [family isEqual:@"ChargeIntent"]) && [p[@"BatteryManaged"] boolValue] && ![hardware[@"BatteryCareAvailable"] boolValue]) unavailable=@"Charging control is unavailable with the current firmware.";
    if(fan && [family isEqual:@"ThermalIntent"] && AsusEffectiveProfile(p,system)!=[p[@"ManualProfile"] integerValue])
        unavailable=@"This profile is unavailable on the power source macOS currently reports. Connect the power adapter; Performance also requires more than 40% battery.";
    if(unavailable) { if(error)*error=[NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Policy" code:4 userInfo:@{NSLocalizedDescriptionKey:unavailable}];return NO; }
    NSArray *all=AsusPolicyActions(p,hardware,system,state,NSDate.date.timeIntervalSince1970);
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
