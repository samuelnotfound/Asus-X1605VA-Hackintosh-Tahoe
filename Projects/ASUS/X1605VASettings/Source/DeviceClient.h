// Copyright (c) 2026 samuelnotfound. MIT License.
#import <Foundation/Foundation.h>

// Only cached IORegistry properties are read. Firmware calls run in AsusSMC's
// workloop, never in this client or the driver's property handler.
NSDictionary *X1605VAReadStatus(void);
BOOL X1605VASendCommand(BOOL keyboard, uint32_t value, NSError **error);
// Explicit userspace refresh; never called at boot or by a login service.
BOOL X1605VARefreshSettings(NSError **error);
BOOL X1605VADecodeNumber32(id value, uint32_t *result);
NSString *X1605VAProfileName(NSInteger profile);
