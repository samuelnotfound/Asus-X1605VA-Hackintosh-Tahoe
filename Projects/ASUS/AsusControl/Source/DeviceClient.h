// Copyright (c) 2026 samuelnotfound. MIT License.
#import <Foundation/Foundation.h>

// Only cached IORegistry properties are read. Firmware calls run in AsusSMC's
// workloop, never in this client or the driver's property handler.
NSDictionary *AsusControlReadStatus(void);
BOOL AsusControlSendCommand(BOOL keyboard, uint32_t value, NSError **error);
// Explicit userspace refresh from the pane or opted-in user-session agent.
BOOL AsusControlRefreshSettings(NSError **error);
// Model-approved device controls; available only with explicit driver opt-in.
BOOL AsusControlSendDeviceCommand(uint32_t command, NSError **error);
BOOL AsusControlDecodeNumber32(id value, uint32_t *result);
NSString *AsusControlProfileName(NSInteger profile);
