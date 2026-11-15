// User-session automatic policies. Foreground clicks use the same transaction
// lock and executor directly; this process handles later transitions/deadlines.
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "DeviceEnvironment.h"
#import "PolicySession.h"
#import <IOKit/ps/IOPowerSources.h>
#include <signal.h>
#include <unistd.h>
static dispatch_source_t wakeSource;
static void powerChanged(void *context) { (void)context; CFRunLoopStop(CFRunLoopGetMain()); }
int main(void) {
    @autoreleasepool {
        signal(SIGUSR1,SIG_IGN);
        wakeSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGUSR1,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(wakeSource,^{CFRunLoopStop(CFRunLoopGetMain());});dispatch_resume(wakeSource);
        CFRunLoopSourceRef power=IOPSNotificationCreateRunLoopSource(powerChanged,NULL);
        if(power)CFRunLoopAddSource(CFRunLoopGetMain(),power,kCFRunLoopDefaultMode);
        AsusDeviceEnvironment *environment=[[AsusDeviceEnvironment alloc]init];
        while(YES) {
            @autoreleasepool {
                int lock=AsusAcquirePolicyLock(0,NULL);
                if(lock>=0) {
                    NSDictionary *p=AsusReadPreferences();
                    NSString *bundle=p[@"SourceBundlePath"],*revision=p[@"Revision"] ?: @"legacy";
                    BOOL removed=![bundle isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:bundle];
                    if(removed || !AsusNeedsAgent(p)) {
                        AsusReleasePolicyLock(lock);
                        if(removed)AsusRemoveAgent(NULL);
                        return 0;
                    }
                    NSMutableDictionary *state=[AsusReadAgentState() mutableCopy];
                    { // Failed families are skipped independently; other controls keep working.
                        NSError *error=nil;
                        BOOL success=AsusControlRefreshSettings(&error) && AsusApplyPolicyFamily(p,@"all",environment,state,&error);
                        state[@"Revision"]=revision;state[@"Version"]=@ASUS_CONTROL_VERSION;
                        state[@"Result"]=success ? @"applied" : @"failed";
                        state[@"UpdatedAt"]=@(NSDate.date.timeIntervalSince1970);
                        if(error)state[@"Error"]=error.localizedDescription;else[state removeObjectForKey:@"Error"];
                        AsusWriteAgentState(state,NULL);
                    }
                    AsusReleasePolicyLock(lock);
                }
            }
            // Service real power notifications and ProcessInfo changes. Sleeping
            // the main thread indefinitely can leave process-local state stale.
            if(CFRunLoopRunInMode(kCFRunLoopDefaultMode,5,true)==kCFRunLoopRunFinished) usleep(5000000);
        }
    }
}
