// AsusMicLED — samuelnotfound (https://github.com/samuelnotfound)
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

enum { kGLED = 0, kSLED = 1 };

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AsusMicLED"));
    if (!svc) svc = IOServiceGetMatchingService(0, IOServiceMatching("X1605VAAssistant"));
    if (!svc) svc = IOServiceGetMatchingService(0, IOServiceMatching("X1605VAFnHelper"));
    if (!svc) { fprintf(stderr, "AsusMicLED bridge not found\n"); return 1; }

    io_connect_t conn;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { fprintf(stderr, "open failed: 0x%x\n", kr); return 1; }

    uint64_t out = 0;
    uint32_t outCnt = 1;

    if (argc > 1) {
        char *end = NULL; errno = 0;
        uint64_t in = strtoull(argv[1], &end, 0);
        if (errno || !end || *end || in > 1) { fprintf(stderr, "State must be 0 or 1.\n"); IOServiceClose(conn); return 2; }
        kr = IOConnectCallScalarMethod(conn, kSLED, &in, 1, &out, &outCnt);
    } else {
        kr = IOConnectCallScalarMethod(conn, kGLED, NULL, 0, &out, &outCnt);
    }

    if (kr != KERN_SUCCESS) fprintf(stderr, "call failed: 0x%x\n", kr);
    else printf("%llu\n", (unsigned long long)out);

    IOServiceClose(conn);
    return kr == KERN_SUCCESS ? 0 : 1;
}
