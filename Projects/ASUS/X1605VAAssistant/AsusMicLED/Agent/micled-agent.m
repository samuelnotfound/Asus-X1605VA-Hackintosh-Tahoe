// micled-agent — Fn+F9 mic mute sync + menu-bar indicator when muted
// samuelnotfound / X1605VA
//
// - SSDT toggles the orange LED on Fn+F9
// - This agent syncs CoreAudio to the LED
// - When muted: shows a red slashed-mic in the menu bar
//   tooltip: "Fn + F9 to unmute"
// - When unmuted: status item is removed
//
// Build:
//   clang -O2 -fobjc-arc \
//     -framework Cocoa -framework CoreAudio -framework CoreFoundation -framework IOKit \
//     -o micled-agent micled-agent.m mic-mute.c

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#include "mic-mute.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

enum { kGLED = 0, kSLED = 1 };

static io_connect_t gConn = 0;
static int gDebug = 0;
static int gInvert = 0;
static NSTimeInterval gInterval = 0.25;

static bool openBridge(void) {
    if (gConn) return true;
    const char *names[] = {
        "AsusMicLED", "X1605VAAssistant", "X1605VAFnHelper", "ASUSF901LED", NULL
    };
    for (int i = 0; names[i]; i++) {
        io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                                       IOServiceMatching(names[i]));
        if (!svc) continue;
        kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gConn);
        IOObjectRelease(svc);
        if (kr == KERN_SUCCESS && gConn) {
            if (gDebug) fprintf(stderr, "opened bridge %s\n", names[i]);
            return true;
        }
        gConn = 0;
    }
    return false;
}

static void closeBridge(void) {
    if (gConn) { IOServiceClose(gConn); gConn = 0; }
}

static int readLED(void) {
    if (!openBridge()) return -1;
    uint64_t val = 0;
    uint32_t cnt = 1;
    kern_return_t kr = IOConnectCallScalarMethod(gConn, kGLED, NULL, 0, &val, &cnt);
    if (kr != KERN_SUCCESS || cnt != 1 || val > 1) {
        closeBridge();
        return -1;
    }
    return (int)val;
}

static bool writeLED(int desired) {
    if (desired != 0 && desired != 1) return false;
    if (!openBridge()) return false;
    uint64_t in = (uint64_t)desired, out = 0;
    uint32_t cnt = 1;
    kern_return_t kr = IOConnectCallScalarMethod(gConn, kSLED, &in, 1, &out, &cnt);
    if (kr != KERN_SUCCESS || cnt != 1 || (int)out != desired) {
        closeBridge();
        return false;
    }
    return true;
}

static int desiredMuteFromLED(int led) {
    int muted = (led != 0);
    if (gInvert) muted = !muted;
    return muted;
}

/// Draw a template-friendly red microphone with a slash (18×18 pt @2x → 36×36).
static NSImage *MutedMicImage(void) {
    const CGFloat s = 18.0;
    NSImage *img = [NSImage imageWithSize:NSMakeSize(s, s)
                                  flipped:NO
                           drawingHandler:^BOOL(NSRect dst) {
        NSColor *red = [NSColor colorWithSRGBRed:0.90 green:0.20 blue:0.20 alpha:1.0];
        [red set];

        // Mic capsule
        NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:
            NSMakeRect(6.5, 7.5, 5.0, 8.0) xRadius:2.5 yRadius:2.5];
        [body fill];

        // Mic stand arc + stem
        NSBezierPath *stand = [NSBezierPath bezierPath];
        [stand setLineWidth:1.4];
        [stand setLineCapStyle:NSLineCapStyleRound];
        [stand appendBezierPathWithArcWithCenter:NSMakePoint(9.0, 9.5)
                                          radius:4.2
                                      startAngle:200
                                        endAngle:340
                                       clockwise:NO];
        [stand moveToPoint:NSMakePoint(9.0, 5.3)];
        [stand lineToPoint:NSMakePoint(9.0, 3.5)];
        [stand moveToPoint:NSMakePoint(6.5, 3.5)];
        [stand lineToPoint:NSMakePoint(11.5, 3.5)];
        [stand stroke];

        // Slash
        NSBezierPath *slash = [NSBezierPath bezierPath];
        [slash setLineWidth:1.8];
        [slash setLineCapStyle:NSLineCapStyleRound];
        [slash moveToPoint:NSMakePoint(3.5, 3.0)];
        [slash lineToPoint:NSMakePoint(14.5, 15.0)];
        [slash stroke];

        return YES;
    }];
    img.template = NO; // keep the red color
    return img;
}

@interface MicLEDAgent : NSObject
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) NSTimer *timer;
@property (nonatomic) int lastLED;
@property (nonatomic) int lastMuted; // -1 unknown, 0 unmuted, 1 muted
@property (nonatomic) NSImage *mutedIcon;
- (void)start;
- (void)sync;
- (void)setStatusVisible:(BOOL)visible;
@end

@implementation MicLEDAgent

- (void)start {
    self.lastLED = -1;
    self.lastMuted = -1;
    self.mutedIcon = MutedMicImage();
    self.timer = [NSTimer scheduledTimerWithTimeInterval:gInterval
                                                  target:self
                                                selector:@selector(sync)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self sync];
}

- (void)setStatusVisible:(BOOL)visible {
    if (visible) {
        if (!self.statusItem) {
            self.statusItem = [[NSStatusBar systemStatusBar]
                statusItemWithLength:NSSquareStatusItemLength];
            self.statusItem.button.image = self.mutedIcon;
            self.statusItem.button.imagePosition = NSImageOnly;
            self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;

            NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
            NSMenuItem *unmute = [[NSMenuItem alloc] initWithTitle:@"Unmute"
                                                            action:@selector(unmute:)
                                                     keyEquivalent:@""];
            unmute.target = self;
            [menu addItem:unmute];
            self.statusItem.menu = menu;
        }
    } else if (self.statusItem) {
        [self.statusItem.menu cancelTracking];
        [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
        self.statusItem = nil;
    }
}

- (void)unmute:(id)sender {
    (void)sender;
    // Dismiss the menu first so it does not linger after the item is gone.
    [self.statusItem.menu cancelTracking];

    int ledOff = gInvert ? 1 : 0;
    if (writeLED(ledOff)) {
        MicrophoneMuteState st;
        char err[256];
        microphone_mute_action(0, &st, err, sizeof(err));
        self.lastLED = ledOff;
        self.lastMuted = 0;
        // Remove on the next run-loop turn so menu teardown finishes cleanly.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setStatusVisible:NO];
        });
        if (gDebug) fprintf(stderr, "menu Unmute → unmuted\n");
    }
}

- (void)sync {
    int led = readLED();
    if (led < 0) {
        if (gDebug) fprintf(stderr, "LED read failed\n");
        return;
    }

    int wantMute = desiredMuteFromLED(led);

    MicrophoneMuteState st;
    char err[256];
    if (microphone_mute_action(-1, &st, err, sizeof(err)) != 0) {
        if (gDebug) fprintf(stderr, "mic read: %s\n", err);
        return;
    }
    bool isMuted = st.muted || (st.volume == 0.0f);

    if (led != self.lastLED) {
        if (gDebug) fprintf(stderr, "LED %d → want mute=%d (was %d)\n",
                            led, wantMute, isMuted);
        if (isMuted != (wantMute != 0)) {
            if (microphone_mute_action(wantMute ? 1 : 0, &st, err, sizeof(err)) != 0) {
                if (gDebug) fprintf(stderr, "mic set failed: %s\n", err);
            } else {
                isMuted = st.muted || (st.volume == 0.0f);
            }
        }
        self.lastLED = led;
        self.lastMuted = wantMute;
    } else if (isMuted != (self.lastMuted != 0) && self.lastMuted >= 0) {
        int newLED = gInvert ? (isMuted ? 0 : 1) : (isMuted ? 1 : 0);
        if (gDebug) fprintf(stderr, "mic changed → LED %d\n", newLED);
        if (writeLED(newLED)) {
            self.lastLED = newLED;
            self.lastMuted = isMuted ? 1 : 0;
        }
    }

    [self setStatusVisible:isMuted];
}

@end

static void usage(const char *argv0) {
    fprintf(stderr,
        "Usage: %s [--debug] [--invert] [--interval SECONDS]\n"
        "\n"
        "  Sync CoreAudio input mute to the X1605VA orange mic LED.\n"
        "  When muted, shows a red slashed-mic in the menu bar\n"
        "  (tooltip: \"Fn + F9 to unmute\"). Hidden when unmuted.\n"
        "  Click the icon to unmute.\n",
        argv0);
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(argv[0]);
            return 0;
        } else if (!strcmp(argv[i], "--debug")) {
            gDebug = 1;
        } else if (!strcmp(argv[i], "--invert")) {
            gInvert = 1;
        } else if (!strcmp(argv[i], "--interval") && i + 1 < argc) {
            gInterval = atof(argv[++i]);
            if (gInterval < 0.05) gInterval = 0.05;
            if (gInterval > 2.0)  gInterval = 2.0;
        } else {
            usage(argv[0]);
            return 1;
        }
    }

    @autoreleasepool {
        // Agent-style process: no dock icon
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

        if (!openBridge()) {
            fprintf(stderr, "micled-agent: cannot open AsusMicLED (or compatible) kext\n");
            return 1;
        }

        MicLEDAgent *agent = [MicLEDAgent new];
        [agent start];

        if (gDebug) fprintf(stderr, "micled-agent started (interval=%.2fs invert=%d)\n",
                            gInterval, gInvert);

        [NSApp run];
        closeBridge();
    }
    return 0;
}
