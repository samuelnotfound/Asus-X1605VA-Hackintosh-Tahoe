#import <Foundation/Foundation.h>
NSURL *AsusSupportDirectory(void);
NSDictionary *AsusReadPreferences(void);
BOOL AsusWritePreferences(NSDictionary *preferences, NSError **error);
NSDictionary *AsusReadAgentState(void);
BOOL AsusWriteAgentState(NSDictionary *state, NSError **error);
BOOL AsusConfigureAgent(NSBundle *bundle, NSDictionary *preferences, NSError **error);
BOOL AsusRemoveAgent(NSError **error);
