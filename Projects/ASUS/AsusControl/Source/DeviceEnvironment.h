#import <Foundation/Foundation.h>
@interface AsusDeviceEnvironment : NSObject
- (NSDictionary *)sample;
@end

// Pure parsing shared with power-source fixtures. Never infer AC from charging.
NSDictionary *AsusPowerSourceSnapshot(NSString *provider, NSArray<NSDictionary *> *sources);
