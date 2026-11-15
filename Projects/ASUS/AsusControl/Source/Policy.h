// Copyright (c) 2026 samuelnotfound. MIT License.
#import <Foundation/Foundation.h>
NSDictionary *AsusDefaultPreferences(void);
BOOL AsusNeedsAgent(NSDictionary *preferences);
NSInteger AsusEffectiveProfile(NSDictionary *preferences, NSDictionary *system);
NSArray<NSDictionary *> *AsusPolicyActions(NSDictionary *preferences, NSDictionary *hardware,
    NSDictionary *system, NSDictionary *state, NSTimeInterval now);
