#import <Foundation/Foundation.h>
NSDictionary *AsusDefaultPreferences(void);
BOOL AsusNeedsAgent(NSDictionary *preferences);
NSInteger AsusEffectiveProfile(NSDictionary *preferences, NSDictionary *system);
NSArray<NSDictionary *> *AsusPolicyActions(NSDictionary *preferences, NSDictionary *hardware, NSDictionary *system, NSDictionary *state, NSTimeInterval now);
typedef BOOL (^AsusPolicySender)(BOOL keyboard, uint32_t value, NSError **error);
typedef NSDictionary *(^AsusPolicyReader)(NSError **error);
BOOL AsusExecutePolicyActions(NSArray<NSDictionary *> *actions, NSMutableDictionary *state, AsusPolicySender sender, AsusPolicyReader reader, NSError **error);

// Also used to recover a failed charging request after a driver/power transition.
NSString *AsusChargePolicyContext(NSDictionary *preferences, NSDictionary *hardware, NSDictionary *system, NSTimeInterval now);
