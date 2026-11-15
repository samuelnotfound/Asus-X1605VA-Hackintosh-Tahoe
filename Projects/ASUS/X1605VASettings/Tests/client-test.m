#import "../Source/DeviceClient.h"
#include <assert.h>
#include <unistd.h>
int main(void) {
    @autoreleasepool {
        uint32_t result;
        assert(X1605VADecodeNumber32(@((int32_t)-783307621), &result) && result == 3511659675U);
        assert(X1605VADecodeNumber32(@UINT32_MAX, &result) && result == UINT32_MAX);
        assert(!X1605VADecodeNumber32(@YES, &result));
        assert(!X1605VADecodeNumber32(@1.5, &result));
        assert(!X1605VADecodeNumber32(@4294967296LL, &result));
        assert(!X1605VADecodeNumber32(@"1", &result));
        NSError *error = nil;
        // These invalid values must fail before opening a driver service.
        assert(!X1605VASendCommand(YES, 101, &error) && error.code == 1);
        assert(!X1605VASendCommand(NO, 0, &error) && error.code == 1);
        assert(!X1605VASendCommand(NO, 6, &error) && error.code == 1);
        if (geteuid() != 0) assert(!X1605VASendCommand(NO, 1, &error) && error.code == 2);
        puts("PASS: completion ID compatibility, invalid values, and command boundaries.");
    }
}
