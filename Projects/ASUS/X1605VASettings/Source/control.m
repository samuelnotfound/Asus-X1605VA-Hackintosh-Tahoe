// Copyright (c) 2026 samuelnotfound. MIT License.
#import "DeviceClient.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int usage(void) {
    fputs("Usage: x1605vactl status | profile standard|whisper|performance | fan auto|full | keyboard 0..100 | --version\n", stderr);
    return 2;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], "--version")) { puts(X1605VA_VERSION); return 0; }
        if (argc == 2 && !strcmp(argv[1], "status")) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:X1605VAReadStatus() options:NSJSONWritingPrettyPrinted error:NULL];
            fwrite(json.bytes, 1, json.length, stdout); puts(""); return 0;
        }
        if (argc != 3) return usage();
        BOOL keyboard = !strcmp(argv[1], "keyboard");
        BOOL profile = !strcmp(argv[1], "profile");
        uint32_t command = 0;
        if (keyboard) {
            char *end; errno = 0;
            unsigned long value = strtoul(argv[2], &end, 10);
            if (errno || end == argv[2] || *end || value > 100 || argv[2][0] == '-') return usage();
            command = (uint32_t)value;
        } else if (profile) {
            if (!strcmp(argv[2], "standard")) command = 3;
            else if (!strcmp(argv[2], "whisper")) command = 4;
            else if (!strcmp(argv[2], "performance")) command = 5;
            else return usage();
        } else if (!strcmp(argv[1], "fan")) {
            if (!strcmp(argv[2], "auto")) command = 1;
            else if (!strcmp(argv[2], "full")) command = 2;
            else return usage();
        } else return usage();
        NSError *error = nil;
        // A profile uses firmware's automatic fan policy. Explicitly release a
        // previous full-speed override first, under the same authorization.
        if (profile && !X1605VASendCommand(NO, 1, &error)) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1;
        }
        if (!X1605VASendCommand(keyboard, command, &error)) {
            fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1;
        }
        puts("Firmware accepted the setting.");
        return 0;
    }
}
