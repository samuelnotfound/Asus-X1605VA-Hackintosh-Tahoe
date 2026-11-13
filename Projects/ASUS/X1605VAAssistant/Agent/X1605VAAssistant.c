// AsusMicLED — samuelnotfound (https://github.com/samuelnotfound)
#include <IOKit/IOKitLib.h>
#include <CoreAudio/CoreAudio.h>
#include <ApplicationServices/ApplicationServices.h>
#include <dispatch/dispatch.h>
#include <Carbon/Carbon.h>
#include <math.h>
#include "mic-mute.h"
#include "menu.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>

enum { kGLED = 0, kSLED = 1 };
int X1605VAAssistantSetup(bool loginAgent);

static io_connect_t gConn = 0;
static AudioObjectID gDev = kAudioObjectUnknown;
static AudioObjectPropertyScope gScope = kAudioDevicePropertyScopeInput;
static int gEnableLED = 0, gLEDFailed = 0;
static int gInvert = 0, gLastLED = -1, gDebug = 0;
static int64_t gKeycode = -1; // existing SSDT sends F18/F19; F20 toggles
static CFMachPortRef gTap = NULL;
static CFRunLoopSourceRef gTapSource = NULL;
static bool gMenuEnabled = false;
static bool gScreenLocked, gSyncFromLED;
static bool gKeyboardFailed = false;

// App controls and hotkeys share one gate; re-check it at the write boundary
// so a queued action cannot run after Accessibility has been revoked.
static bool appControlAllowed(void) {
    bool ready = !gMenuEnabled || (AXIsProcessTrusted() &&
                                  gTap && CFMachPortIsValid(gTap) && CGEventTapIsEnabled(gTap));
    if (gMenuEnabled && !ready) AsusMenuSetKeyAccess(false);
    return ready;
}
static void onMainCommon(dispatch_block_t block) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, block);
    CFRunLoopWakeUp(CFRunLoopGetMain());
}

// ---------- LED ----------
static bool ledOpen(void) {
    if (gConn) return true;
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("X1605VAAssistant"));
    if (!svc) svc = IOServiceGetMatchingService(0, IOServiceMatching("X1605VAFnHelper"));
    if (!svc) svc = IOServiceGetMatchingService(0, IOServiceMatching("AsusMicLED"));
    // Same restricted protocol as the original, working 0.2.1 bridge.
    if (!svc) svc = IOServiceGetMatchingService(0, IOServiceMatching("ASUSF901LED"));
    if (!svc) return false;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gConn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { gConn = 0; return false; }
    return true;
}

static void setLED(int on) {
    if (gInvert) on = !on;
    if (!gEnableLED || gLEDFailed || gScreenLocked || gSyncFromLED || !appControlAllowed()) return;
    if (on == gLastLED) return;
    if (!ledOpen()) { fprintf(stderr, "LED bridge unavailable; no automatic retries.\n"); gLEDFailed = 1; return; }
    uint64_t in = on, out = 0;
    uint32_t n = 1;
    if (IOConnectCallScalarMethod(gConn, kSLED, &in, 1, &out, &n) == KERN_SUCCESS && n == 1 && out == in) {
        gLastLED = on;
        if (gDebug) printf("LED -> %d\n", on);
    } else {
        gLEDFailed = 1; fprintf(stderr, "LED request/readback failed; no retries.\n");
        IOServiceClose(gConn);
        gConn = 0;
        gLastLED = -1;
    }
}

bool AsusKeyboardGet(int *percent) {
    if (!percent || gKeyboardFailed || !ledOpen()) return false;
    uint64_t value = 0;
    uint32_t count = 1;
    if (IOConnectCallScalarMethod(gConn, 2, NULL, 0, &value, &count) || count != 1 || value > 100) return false;
    *percent = (int)value;
    return true;
}

bool AsusKeyboardSet(int percent, int *confirmed) {
    if (!appControlAllowed()) return false;
    if (!confirmed || percent < 0 || percent > 100 || gKeyboardFailed || !ledOpen()) return false;
    uint64_t input = (uint64_t)percent, value = 0;
    uint32_t count = 1;
    if (IOConnectCallScalarMethod(gConn, 3, &input, 1, &value, &count) || count != 1 || value != input) {
        gKeyboardFailed = true;
        return false;
    }
    *confirmed = (int)value;
    return true;
}

// Optional trackpad API: old drivers return unsupported, leaving the switch disabled.
bool AsusTrackpadGet(int *enabled) {
    if (!enabled || !ledOpen()) return false;
    uint64_t value = 0; uint32_t count = 1;
    if (IOConnectCallScalarMethod(gConn, 4, NULL, 0, &value, &count) || count != 1 || value > 1) return false;
    *enabled = (int)value;
    return true;
}
bool AsusTrackpadAvailable(void) {
    if (!ledOpen()) return false;
    uint64_t value = 0; uint32_t count = 1;
    return !IOConnectCallScalarMethod(gConn, 6, NULL, 0, &value, &count) && count == 1 && (value & 1);
}
bool AsusTrackpadSet(bool enabled) {
    if (!appControlAllowed()) return false;
    if (!AsusTrackpadAvailable()) return false;
    uint64_t input = enabled, value = 2; uint32_t count = 1;
    return !IOConnectCallScalarMethod(gConn, 5, &input, 1, &value, &count) && count == 1 && value == input;
}

// ---------- Core Audio ----------
static AudioObjectID defaultDevice(void) {
    AudioObjectPropertyAddress a = {
        gScope == kAudioDevicePropertyScopeInput ? kAudioHardwarePropertyDefaultInputDevice
                                                 : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectID d = kAudioObjectUnknown;
    UInt32 sz = sizeof d;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &d) != noErr)
        return kAudioObjectUnknown;
    return d;
}

static void bindDevice(void);
static bool getVol(float *value) {
    AudioObjectPropertyAddress p = {kAudioDevicePropertyVolumeScalar, gScope, 0};
    Float32 v = 0; UInt32 bytes = sizeof(v);
    if (AudioObjectHasProperty(gDev, &p)) {
        if (AudioObjectGetPropertyData(gDev, &p, 0, NULL, &bytes, &v) || !isfinite(v) || v < 0 || v > 1) return false;
        *value = v; return true;
    }
    p = (AudioObjectPropertyAddress){kAudioDevicePropertyStreamConfiguration, gScope, 0};
    bytes = 0;
    if (AudioObjectGetPropertyDataSize(gDev, &p, 0, NULL, &bytes) || bytes < sizeof(AudioBufferList) || bytes > 65536) return false;
    AudioBufferList *buffers = calloc(1, bytes);
    if (!buffers) return false;
    OSStatus rc = AudioObjectGetPropertyData(gDev, &p, 0, NULL, &bytes, buffers);
    UInt32 channels = 0;
    if (!rc && buffers->mNumberBuffers <= (bytes - offsetof(AudioBufferList, mBuffers)) / sizeof(AudioBuffer)) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
            if (buffers->mBuffers[i].mNumberChannels > 32 - channels) { rc = -1; break; }
            channels += buffers->mBuffers[i].mNumberChannels;
        }
    } else rc = -1;
    free(buffers);
    if (rc || !channels || channels > 32) return false;
    float maximum = 0;
    for (UInt32 ch = 1; ch <= channels; ++ch) {
        p = (AudioObjectPropertyAddress){kAudioDevicePropertyVolumeScalar, gScope, ch};
        bytes = sizeof(v);
        if (!AudioObjectHasProperty(gDev, &p) || AudioObjectGetPropertyData(gDev, &p, 0, NULL, &bytes, &v) || !isfinite(v) || v < 0 || v > 1) return false;
        if (v > maximum) maximum = v;
    }
    *value = maximum; return true;
}
static void syncAudio(bool forceRefresh) {
    (void)forceRefresh;
    AudioDeviceID selected = defaultDevice();
    if (selected != gDev) bindDevice();
    MicrophoneMuteState state; char error[512];
    if (gDev == kAudioObjectUnknown || microphone_mute_action(-1, &state, error, sizeof(error)) || state.device != gDev) {
        if (gDebug) fprintf(stderr, "Microphone state unknown; LED unchanged.\n");
        if (gMenuEnabled) AsusMenuMicrophoneUnavailable();
        return;
    }
    float volume = 1;
    bool zero = getVol(&volume) && volume == 0.0f;
    bool muted = state.muted || zero;
    if (gSyncFromLED && !gScreenLocked && appControlAllowed() && ledOpen()) {
        uint64_t led = 0;
        uint32_t count = 1;
        if (IOConnectCallScalarMethod(gConn, kGLED, NULL, 0, &led, &count) == KERN_SUCCESS &&
            count == 1 && led <= 1) {
            bool desiredMute = (led != 0) != (gInvert != 0);
            if (muted == desiredMute ||
                microphone_mute_action(desiredMute ? 1 : 0, &state, error, sizeof(error)) == 0) {
                muted = desiredMute;
                zero = state.volume == 0.0f;
                gLastLED = (int)led;
                gSyncFromLED = false;
            }
        }
    }
    if (gDebug) printf("input muted=%d input-zero=%d LED target=%d%s\n", state.muted, zero, muted, gEnableLED ? "" : " (monitor only)");
    if (gMenuEnabled) AsusMenuMute(muted, state.writable, zero ? 0 : state.volume);
    setLED(muted);
}
static void screenLockChanged(CFNotificationCenterRef center, void *observer, CFNotificationName name,
                              const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)object; (void)userInfo;
    gScreenLocked = CFEqual(name, CFSTR("com.apple.screenIsLocked"));
    if (!gScreenLocked) {
        gSyncFromLED = true;
        syncAudio(false);
    }
}

static int controlMicrophone(int action) {
    if (action >= 0 && (gScreenLocked || !appControlAllowed())) return -1;
    MicrophoneMuteState state; char error[512];
    if (microphone_mute_action(action, &state, error, sizeof(error))) {
        fprintf(stderr, "%s\n", error);
        if (gMenuEnabled && action >= 0) { syncAudio(false); AsusMenuMicrophoneError(); }
        return -1;
    }
    if (action >= 0) {
        gSyncFromLED = false;
        syncAudio(true);
    }
    return state.muted ? 1 : 0;
}

static void performMute(int action) {
    int muted = controlMicrophone(action);
    if (muted >= 0 && gMenuEnabled) AsusMenuMicrophoneKey(muted != 0);
}

void AsusMicrophoneSetEnabled(bool enabled) { (void)controlMicrophone(enabled ? 0 : 1); }

// ---------- listeners ----------
static OSStatus onChange(AudioObjectID id, UInt32 n, const AudioObjectPropertyAddress *a, void *ctx) {
    onMainCommon(^{ syncAudio(false); });
    return noErr;
}

static void listen(AudioObjectID dev, bool add) {
    if (dev == kAudioObjectUnknown) return;
    UInt32 sels[2] = { kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute };
    for (int s = 0; s < 2; s++)
        for (UInt32 el = 0; el <= 2; el++) {
            AudioObjectPropertyAddress a = { sels[s], gScope, el };
            if (add) AudioObjectAddPropertyListener(dev, &a, onChange, NULL);
            else AudioObjectRemovePropertyListener(dev, &a, onChange, NULL);
        }
}

static void bindDevice(void) {
    listen(gDev, false);
    gDev = defaultDevice();
    listen(gDev, true);
    if (gDebug) printf("device id %u\n", (unsigned)gDev);
}

static OSStatus onDefaultChange(AudioObjectID id, UInt32 n, const AudioObjectPropertyAddress *a, void *ctx) {
    onMainCommon(^{ bindDevice(); syncAudio(false); });
    return noErr;
}

// ---------- keyboard shortcuts ----------
static const int64_t shortcutEventTag = 0x583136464e;
static const CGEventFlags captureModifiers = kCGEventFlagMaskCommand | kCGEventFlagMaskShift;
static const CGEventFlags shortcutModifiers = kCGEventFlagMaskCommand | kCGEventFlagMaskControl |
    kCGEventFlagMaskAlternate | kCGEventFlagMaskShift | kCGEventFlagMaskSecondaryFn;
static bool finderDeleteHeld, printScreenHeld, launcherHeld, fnModifierHeld;
static int64_t regionCaptureHeldKey = -1;
static int64_t finderDeleteKey;
static void postShortcut(CGKeyCode key, CGEventFlags flags) {
    if (!appControlAllowed()) return;
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, key, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, key, false);
    if (down && up) {
        CGEventSetFlags(down, flags); CGEventSetFlags(up, flags);
        CGEventSetIntegerValueField(down, kCGEventSourceUserData, shortcutEventTag);
        CGEventSetIntegerValueField(up, kCGEventSourceUserData, shortcutEventTag);
        CGEventPost(kCGHIDEventTap, down); CGEventPost(kCGHIDEventTap, up);
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);
}

// On the X1605VA, Fn+F11 is a six-event burst from the built-in PS/2
// keyboard (type 40). There is no separate Fn event. Buffer only the S
// events in a plausible burst, and replay them if the release sequence
// fails to match. Ordinary Shift–Command–S never needs a global remap.
typedef struct {
    CGEventType type;
    CGKeyCode key;
    CGEventFlags modifiers;
    uint64_t maxGapNs;
} ScreenshotStep;

static const ScreenshotStep screenshotSteps[] = {
    { kCGEventFlagsChanged, kVK_Command, kCGEventFlagMaskCommand, 0 },
    { kCGEventFlagsChanged, kVK_Shift,   captureModifiers,        3000000 },
    { kCGEventKeyDown,      kVK_ANSI_S,  captureModifiers,        3000000 },
    { kCGEventKeyUp,        kVK_ANSI_S,  captureModifiers,        7000000 },
    { kCGEventFlagsChanged, kVK_Shift,   kCGEventFlagMaskCommand, 7000000 },
    { kCGEventFlagsChanged, kVK_Command, 0,                      7000000 },
};

static size_t screenshotStep;
static CGEventTimestamp screenshotTimestamp;
static CGEventRef screenshotDown, screenshotUp;
static CFRunLoopTimerRef screenshotDeadline;

static void finishScreenshotBurst(CGEventTapProxy proxy, bool replay) {
    if (screenshotDeadline) {
        CFRunLoopTimerInvalidate(screenshotDeadline);
        CFRelease(screenshotDeadline);
        screenshotDeadline = NULL;
    }
    CGEventRef events[] = { screenshotDown, screenshotUp };
    screenshotDown = screenshotUp = NULL;
    screenshotStep = 0;
    for (size_t i = 0; i < sizeof(events) / sizeof(events[0]); ++i) {
        if (!events[i]) continue;
        if (replay && AXIsProcessTrusted()) {
            CGEventSetIntegerValueField(events[i], kCGEventSourceUserData, shortcutEventTag);
            if (proxy) CGEventTapPostEvent(proxy, events[i]);
            else CGEventPost(kCGHIDEventTap, events[i]);
        }
        CFRelease(events[i]);
    }
}

static bool matchesScreenshotStep(size_t index, CGEventType type, CGEventRef event) {
    const ScreenshotStep *step = &screenshotSteps[index];
    CGEventTimestamp now = CGEventGetTimestamp(event);
    return type == step->type &&
        CGEventGetIntegerValueField(event, kCGKeyboardEventKeyboardType) == 40 &&
        CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == step->key &&
        (CGEventGetFlags(event) & shortcutModifiers) == step->modifiers &&
        !CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) &&
        (!index || (now >= screenshotTimestamp && now - screenshotTimestamp <= step->maxGapNs));
}

static bool handleScreenshotBurst(CGEventTapProxy proxy, CGEventType type, CGEventRef event) {
    if (!matchesScreenshotStep(screenshotStep, type, event)) {
        finishScreenshotBurst(proxy, true);
        if (!matchesScreenshotStep(0, type, event)) return false;
    }
    if (screenshotStep == 2) {
        screenshotDown = CGEventCreateCopy(event);
        screenshotDeadline = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + 0.030, 0, 0, 0,
            ^(CFRunLoopTimerRef timer) { (void)timer; finishScreenshotBurst(NULL, true); });
        if (!screenshotDown || !screenshotDeadline) { finishScreenshotBurst(NULL, false); return false; }
        CFRunLoopAddTimer(CFRunLoopGetMain(), screenshotDeadline, kCFRunLoopCommonModes);
    } else if (screenshotStep == 3) {
        screenshotUp = CGEventCreateCopy(event);
        if (!screenshotUp) { finishScreenshotBurst(proxy, true); return false; }
    }
    screenshotTimestamp = CGEventGetTimestamp(event);
    if (++screenshotStep == sizeof(screenshotSteps) / sizeof(screenshotSteps[0])) {
        finishScreenshotBurst(NULL, false);
        onMainCommon(^{ postShortcut(kVK_ANSI_4, captureModifiers); });
    }
    return type == kCGEventKeyDown || type == kCGEventKeyUp;
}

// ---------- F9 key ----------
static CGEventRef tapCb(CGEventTapProxy p, CGEventType t, CGEventRef e, void *u) {
    if (t == kCGEventTapDisabledByTimeout || t == kCGEventTapDisabledByUserInput) {
        finishScreenshotBurst(p, true);
        if (gTap && (!gMenuEnabled || AXIsProcessTrusted())) CGEventTapEnable(gTap, true);
        return e;
    }
    if (t != kCGEventKeyDown && t != kCGEventKeyUp && t != kCGEventFlagsChanged) return e;
    if (CGEventGetIntegerValueField(e, kCGEventSourceUserData) == shortcutEventTag) return e;
    CGEventFlags modifiers = CGEventGetFlags(e);
    if (t == kCGEventFlagsChanged) fnModifierHeld = (modifiers & kCGEventFlagMaskSecondaryFn) != 0;
    if (gMenuEnabled && !appControlAllowed()) { finishScreenshotBurst(NULL, false); return e; }
    if (gMenuEnabled && AsusMenuFirmwareKeyboardAvailable() && handleScreenshotBurst(p, t, e)) return NULL;
    if (t == kCGEventFlagsChanged) return e;
    int64_t kc = CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode);
    const CGEventFlags nonFnModifiers = shortcutModifiers & ~kCGEventFlagMaskSecondaryFn;
    bool plain = !(modifiers & nonFnModifiers);
    bool down = t == kCGEventKeyDown;
    bool firstDown = down && !CGEventGetIntegerValueField(e, kCGKeyboardEventAutorepeat);
    if (firstDown && (kc == kVK_F11 || kc == kVK_F13))
        fprintf(stderr, "Screenshot key: code=%lld flags=0x%llx physicalFn=%d\n", (long long)kc, (unsigned long long)modifiers, CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, kVK_Function));
    if (gMenuEnabled) {
        if (kc == kVK_ForwardDelete) {
            if (!down && finderDeleteHeld && kc == finderDeleteKey) { finderDeleteHeld = false; return NULL; }
            if (finderDeleteHeld) return NULL;
            pid_t finderPID = firstDown && plain ? AsusFinderFrontmostPID() : 0;
            if (finderPID) {
                finderDeleteHeld = true; finderDeleteKey = kc;
                // AX IPC must not run inside the keyboard tap callback.
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    bool selected = AsusFinderItemsFocused();
                    onMainCommon(^{
                        if (AsusFinderFrontmostPID() != finderPID) return;
                        fprintf(stderr, "Finder Delete: selected-items=%d\n", selected);
                        postShortcut(selected ? kVK_Delete : kVK_ForwardDelete, selected ? kCGEventFlagMaskCommand : modifiers);
                    });
                });
                return NULL;
            }
            return e; // Forward-delete text; never alter the separate Backspace key.
        }
        // Print Screen is F13 in the default VoodooPS2 map. Preserve the old
        // ASUSB401 F13 brightness transport; ASUSB402 uses F17 instead.
        if (kc == kVK_F13 && (!AsusMenuFirmwareKeyboardAvailable() || AsusMenuFirmwareKeyboardContinuous())) {
            if (!down && printScreenHeld) { printScreenHeld = false; return NULL; }
            if (printScreenHeld) return NULL;
            if (plain) {
                if (firstDown) {
                    printScreenHeld = true;
                    onMainCommon(^{ postShortcut(kVK_ANSI_3, kCGEventFlagMaskCommand | kCGEventFlagMaskShift); });
                }
                return NULL;
            }
        }
        if (kc == regionCaptureHeldKey) {
            if (!down) regionCaptureHeldKey = -1;
            return NULL;
        }
        bool screenshotChord = kc == kVK_ANSI_S &&
            (modifiers & nonFnModifiers) == captureModifiers;
        if (firstDown && regionCaptureHeldKey < 0 && ((kc == kVK_F11 && plain) || screenshotChord)) {
            bool physicalFn = fnModifierHeld || CGEventSourceKeyState(kCGEventSourceStateHIDSystemState, kVK_Function);
            if (physicalFn) {
                regionCaptureHeldKey = kc;
                onMainCommon(^{ postShortcut(kVK_ANSI_4, kCGEventFlagMaskCommand | kCGEventFlagMaskShift); });
                return NULL;
            }
        }
        // The generic function flag is also set for ordinary F keys. Only
        // the dedicated ACPI MyASUS transport is a trusted launcher notice.
        if (kc == kVK_F16 && AsusMenuFirmwareLauncherAvailable() && plain) {
            if (!down) { launcherHeld = false; return NULL; }
            if (firstDown && !launcherHeld) { launcherHeld = true; onMainCommon(^{ AsusMenuToggle(); }); }
            return NULL;
        }
    }
    bool firmware = gMenuEnabled && AsusMenuFirmwareKeyboardAvailable();
    bool rawControl = kc == kVK_F7 || kc == kVK_F9;
    bool transport = kc == kVK_F13 || kc == kVK_F14 || kc == kVK_F15 || kc == kVK_F16 ||
        kc == kVK_F17 || kc == kVK_F18 || kc == kVK_F19 || kc == kVK_F20;
    if (gDebug && t == kCGEventKeyDown && (rawControl || transport))
        printf("ASUS function event %lld\n", (long long)kc);
    // Firmware already changes the light and emits F17/F18/F19. Do not let
    // companion raw F7/F9 presses fall through and alert-beep in the front app.
    CGEventFlags shortcuts = kCGEventFlagMaskCommand | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskShift;
    if (firmware && rawControl && !(CGEventGetFlags(e) & shortcuts)) return NULL;
    if (gMenuEnabled && kc == kVK_F17 && AsusMenuFirmwareKeyboardContinuous()) {
        if (t == kCGEventKeyDown && !CGEventGetIntegerValueField(e, kCGKeyboardEventAutorepeat))
            onMainCommon(^{ AsusMenuRefreshKeyboard(); });
        return NULL;
    }
    int level = kc == kVK_F13 ? 0 : kc == kVK_F14 ? 1 : kc == kVK_F15 ? 2 : kc == kVK_F16 ? 3 : -1;
    if (gMenuEnabled && AsusMenuFirmwareKeyboardAvailable() && !AsusMenuFirmwareKeyboardContinuous() && level >= 0) {
        if (t == kCGEventKeyDown && !CGEventGetIntegerValueField(e, kCGKeyboardEventAutorepeat))
            onMainCommon(^{ AsusMenuKeyboardLevel(level); });
        return NULL;
    }
    int action = kc == kVK_F18 ? 0 : kc == kVK_F19 ? 1 : kc == kVK_F20 ? 2 : -1;
    if (gKeycode >= 0) action = kc == gKeycode ? 2 : -1;
    if (action < 0) return firmware && transport && plain ? NULL : e;
    if (t == kCGEventKeyDown && !CGEventGetIntegerValueField(e, kCGKeyboardEventAutorepeat))
        onMainCommon(^{ performMute(action); });
    return NULL; // swallow F9
}

// The modifying keyboard event tap uses Accessibility. Keep the UI running
// while the user grants permission.
static bool keyTapAttempted, keyPermissionSeen, keyWaitingLogged;
static CFAbsoluteTime lastTapAttempt;
static bool updateKeyTap(bool appMode) {
    bool accessibility = AXIsProcessTrusted();
    bool allowed = !appMode || accessibility;
    // Permission changes can invalidate the Mach port. Enabling that old port
    // cannot restore it; remove its source and create a fresh tap after approval.
    if (gTap && !CFMachPortIsValid(gTap)) {
        if (gTapSource) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gTapSource, kCFRunLoopCommonModes);
            CFRunLoopSourceInvalidate(gTapSource); CFRelease(gTapSource); gTapSource = NULL;
        }
        CFRelease(gTap); gTap = NULL; keyTapAttempted = false;
    }
    static int previousAccess = -1;
    int access = (accessibility ? 1 : 0) |
        (gTap && CGEventTapIsEnabled(gTap) ? 4 : 0);
    if (access != previousAccess) {
        fprintf(stderr, "Keyboard access: Accessibility=%d ActiveTap=%d\n",
                accessibility, (access & 4) != 0);
        previousAccess = access;
    }
    if (!allowed) {
        if (gTap) CGEventTapEnable(gTap, false);
        if (!keyWaitingLogged) {
            fprintf(stderr, "X1605VA Assistant is ready; Keyboard shortcuts need Accessibility.\n");
            keyWaitingLogged = true;
        }
        keyPermissionSeen = false; fnModifierHeld = false; regionCaptureHeldKey = -1;
        finishScreenshotBurst(NULL, false);
        if (gMenuEnabled) AsusMenuSetPermissions(accessibility, false);
        return false;
    }
    if (!keyPermissionSeen) keyTapAttempted = false;
    keyPermissionSeen = true; keyWaitingLogged = false;
    if (!gTap && (!keyTapAttempted || CFAbsoluteTimeGetCurrent() - lastTapAttempt >= 5)) {
        keyTapAttempted = true; lastTapAttempt = CFAbsoluteTimeGetCurrent();
        CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);
        gTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, tapCb, NULL);
        if (gTap) {
            gTapSource = CFMachPortCreateRunLoopSource(NULL, gTap, 0);
            if (gTapSource) CFRunLoopAddSource(CFRunLoopGetMain(), gTapSource, kCFRunLoopCommonModes);
            else { CFMachPortInvalidate(gTap); CFRelease(gTap); gTap = NULL; }
            if (gTap) puts("Keyboard access ready.");
        } else fprintf(stderr, "Keyboard event tap unavailable; controls remain locked until keyboard access is ready.\n");
    }
    if (gTap) CGEventTapEnable(gTap, true);
    bool ready = gTap && CFMachPortIsValid(gTap) && CGEventTapIsEnabled(gTap);
    if (gMenuEnabled) AsusMenuSetPermissions(accessibility, ready);
    return ready;
}

int main(int argc, char **argv) {
    bool useKey = false;
    bool loginAgent = false;
    CFStringRef bundleID = CFBundleGetIdentifier(CFBundleGetMainBundle());
    bool appMode = bundleID && CFEqual(bundleID, CFSTR("com.samuelnotfound.X1605VAAssistant.Agent"));
    if (appMode) {
        useKey = true;
        gEnableLED = 1;
    }
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--hardware-status")) return AsusMenuDiagnostics();
        if (!strcmp(argv[i], "--help")) { puts("X1605VAAssistant [--debug] [--enable-led] [--enable-key] [--keycode N] [--invert]"); puts(appMode ? "App bundle mode: F9 handling and LED synchronization enabled." : "Default: input-state monitoring only, no LED writes or key interception."); return 0; }
        else if (!strcmp(argv[i], "--output")) { fprintf(stderr, "This build controls the microphone only.\n"); return 2; }
        else if (!strcmp(argv[i], "--enable-led")) gEnableLED = 1;
        else if (!strcmp(argv[i], "--enable-key")) useKey = true;
        else if (!strcmp(argv[i], "--invert")) gInvert = 1;
        else if (!strcmp(argv[i], "--no-key")) useKey = false;
        else if (!strcmp(argv[i], "--debug")) gDebug = 1;
        else if (!strcmp(argv[i], "--login-agent")) loginAgent = true;
        else if (!strcmp(argv[i], "--keycode") && i + 1 < argc) gKeycode = atoll(argv[++i]);
    }
    if (appMode && X1605VAAssistantSetup(loginAgent)) return 1;
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (appMode) {
        // One background instance per user, including manual app launches.
        const char *home = getenv("HOME");
        char lockPath[PATH_MAX];
        if (!home || snprintf(lockPath, sizeof(lockPath), "%s/Library/Caches/com.samuelnotfound.X1605VAAssistant.lock", home) >= (int)sizeof(lockPath)) return 1;
        int lockFD = open(lockPath, O_CREAT | O_RDWR, 0600);
        if (lockFD < 0) return 1;
        if (flock(lockFD, LOCK_EX | LOCK_NB)) { close(lockFD); AsusMenuOpenExisting(); return 0; }
        // Keep lockFD open for the life of this process. Manual Finder starts
        // and login starts use the same diagnostic log; never log typed keys.
        char logPath[PATH_MAX];
        if (snprintf(logPath, sizeof(logPath), "%s/Library/Logs/X1605VA Assistant.log", home) < (int)sizeof(logPath)) {
            int logFD = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
            struct stat st;
            if (logFD >= 0) {
                if (!fstat(logFD, &st) && S_ISREG(st.st_mode) && st.st_uid == getuid()) {
                    dup2(logFD, STDOUT_FILENO); dup2(logFD, STDERR_FILENO);
                }
                close(logFD);
            }
        }
    }
    puts("X1605VA Assistant 0.9.13");
    printf("Keyboard handling: %s; LED synchronization: %s\n", useKey ? "enabled" : "disabled", gEnableLED ? "enabled" : "disabled");

    AudioObjectPropertyAddress da = {
        gScope == kAudioDevicePropertyScopeInput ? kAudioHardwarePropertyDefaultInputDevice
                                                 : kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &da, onDefaultChange, NULL);

    if (appMode) {
        gMenuEnabled = true;
        gSyncFromLED = useKey;
        if (useKey) {
            CFNotificationCenterRef notifications = CFNotificationCenterGetDistributedCenter();
            CFNotificationCenterAddObserver(notifications, &gScreenLocked, screenLockChanged,
                CFSTR("com.apple.screenIsLocked"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            CFNotificationCenterAddObserver(notifications, &gScreenLocked, screenLockChanged,
                CFSTR("com.apple.screenIsUnlocked"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        AsusMenuStart();
    }
    bindDevice();

    if (useKey) {
        if (appMode) {
            const void *key = kAXTrustedCheckOptionPrompt, *value = kCFBooleanTrue;
            CFDictionaryRef options = CFDictionaryCreate(NULL, &key, &value, 1,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            AXIsProcessTrustedWithOptions(options);
            CFRelease(options);
        }
        if (!updateKeyTap(appMode) && !appMode) return 1;
    }

    syncAudio(false);
    puts("Menu ready.");

    // safety net: resync every 2s (kext loads late, wake from sleep, missed events)
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + 2, 2, 0, 0,
        ^(CFRunLoopTimerRef t) { if (useKey) updateKeyTap(appMode); if (gDev == kAudioObjectUnknown) bindDevice(); syncAudio(false); });
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);

    if (appMode) AsusMenuRun();
    else CFRunLoopRun();
    return 0;
}
