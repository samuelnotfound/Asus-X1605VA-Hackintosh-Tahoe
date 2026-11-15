#import "../Source/DeviceClient.h"
#include <assert.h>
#include <unistd.h>
int main(void) {
    @autoreleasepool {
        uint32_t result;
        assert(AsusControlDecodeNumber32(@((int32_t)-783307621), &result) && result == 3511659675U);
        assert(AsusControlDecodeNumber32(@UINT32_MAX, &result) && result == UINT32_MAX);
        assert(!AsusControlDecodeNumber32(@YES, &result));
        assert(!AsusControlDecodeNumber32(@1.5, &result));
        assert(!AsusControlDecodeNumber32(@4294967296LL, &result));
        assert(!AsusControlDecodeNumber32(@"1", &result));
        NSError *error = nil;
        // These invalid values must fail before opening a driver service.
        assert(!AsusControlSendCommand(YES, 101, &error) && error.code == 1);
        assert(!AsusControlSendCommand(NO, 0, &error) && error.code == 1);
        assert(!AsusControlSendCommand(NO, 6, &error) && error.code == 1);
        assert(!AsusControlSendDeviceCommand(0, &error) && error.code == 1);
        assert(!AsusControlSendDeviceCommand(12, &error) && error.code == 1);
        if (geteuid() != 0) assert(!AsusControlSendCommand(NO, 1, &error) && error.code == 2);
        puts("PASS: completion ID compatibility, invalid values, and command boundaries.");
    }
}
