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
        NSDictionary *legacy=@{@"AsusControlHardwareProfile":@"ASUS X1605VA / BIOS 305",@"FnLockAvailable":@YES,@"FnLockHotkeys":@NO};
        NSDictionary *normalized=AsusControlNormalizeFnStatus(legacy);
        assert([normalized[@"FnLockHotkeys"]boolValue] && [normalized[@"FnLockCompatibilityMapping"]boolValue]);
        assert([AsusControlNormalizeFnStatus(normalized)[@"FnLockHotkeys"]boolValue]); // Never invert twice.
        assert(AsusControlDeviceCommandForHardware(3,legacy)==4 && AsusControlDeviceCommandForHardware(4,legacy)==3);
        assert(AsusControlDeviceCommandForHardware(3,normalized)==3 && AsusControlDeviceCommandForHardware(4,normalized)==4);
        NSMutableDictionary *other=[legacy mutableCopy];other[@"AsusControlHardwareProfile"]=@"Other ASUS";
        assert(![AsusControlNormalizeFnStatus(other)[@"FnLockHotkeys"]boolValue] && AsusControlDeviceCommandForHardware(3,other)==3);
        NSMutableDictionary *opposite=[legacy mutableCopy];opposite[@"FnLockHotkeys"]=@YES;
        assert(![AsusControlNormalizeFnStatus(opposite)[@"FnLockHotkeys"]boolValue]);
        for(uint32_t cmd=1;cmd<=11;cmd++) if(cmd!=3 && cmd!=4) assert(AsusControlDeviceCommandForHardware(cmd,legacy)==cmd);
        NSError *error = nil;
        // These invalid values must fail before opening a driver service.
        assert(!AsusControlSendCommand(YES, 101, &error) && error.code == 1);
        assert(!AsusControlSendCommand(NO, 0, &error) && error.code == 1);
        assert(!AsusControlSendCommand(NO, 6, &error) && error.code == 1);
        assert(!AsusControlSendDeviceCommand(0, &error) && error.code == 1);
        assert(!AsusControlSendDeviceCommand(12, &error) && error.code == 1);
        if (geteuid() != 0) assert(!AsusControlSendCommand(NO, 1, &error) && error.code == 2);
        puts("PASS: legacy/normalized Fn mapping, profile isolation, completion IDs, invalid values and command boundaries.");
    }
}
