#import <Foundation/Foundation.h>
#import "DeviceEnvironment.h"
// The pane and login agent share one policy transaction at a time.
int AsusAcquirePolicyLock(unsigned waitMilliseconds, NSError **error);
void AsusReleasePolicyLock(int descriptor);
BOOL AsusApplyPolicyFamily(NSDictionary *preferences, NSString *family, AsusDeviceEnvironment *environment, NSMutableDictionary *state, NSError **error);
