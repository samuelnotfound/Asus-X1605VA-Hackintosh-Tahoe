#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include "menu.h"

// AppleSMC structure protocol, also implemented by VirtualSMC. Only commands
// 9 (metadata) and 5 (read bytes) for the cached LKSB key are used here.
typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } version;
    struct { uint16_t version, length; uint32_t cpu, gpu, memory; } limits;
    struct { uint32_t size, type; uint8_t attributes; } info;
    uint8_t result, status, command;
    uint32_t data;
    uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "SMC message ABI");

static io_connect_t smc;
static io_service_t asus;
static IOReturn smcError;
static const char *smcIssue = "service not present";
static bool smcFailed, keyKnown, muteKnown, lastMute;
static int lastKeyboard = -1, lastTouchpad = -1;
static int firmwareKeyboard;
static bool firmwareLauncher;
static bool keyboardControllable, trackpadControllable, keyAccessReady;
static bool permissionAX;
static bool menuSliderTracking, microphoneError, trackpadError;
static NSTimer *sliderCommitTimer;
static int pendingKeyboard;
static CFAbsoluteTime lastKeyboardWrite;
static void requestKeyboard(int percent);
static void updateMenu(void);

static int hasFirmwareKeyboardMarker(void) {
    io_service_t service = IOServiceGetMatchingService(0, IOServiceNameMatching("BKOS"));
    if (!service) return false;
    bool matches = IOObjectConformsTo(service, "IOACPIPlatformDevice");
    CFTypeRef name = IORegistryEntryCreateCFProperty(service, CFSTR("name"), NULL, 0);
    int version = 0;
    if (matches && name && CFGetTypeID(name) == CFDataGetTypeID() && CFDataGetLength(name) >= 8) {
        if (!memcmp(CFDataGetBytePtr(name), "ASUSB401", 8)) version = 1;
        if (!memcmp(CFDataGetBytePtr(name), "ASUSB402", 8)) version = 2;
    }
    if (name) CFRelease(name);
    IOObjectRelease(service);
    return version;
}

@protocol AsusKeyboardBrightnessReading
- (NSArray *)copyKeyboardBacklightIDs;
- (BOOL)isKeyboardBuiltIn:(uint64_t)keyboard;
- (float)brightnessForKeyboard:(uint64_t)keyboard;
@end

static bool readCoreBrightness(int *percent) {
    static id<AsusKeyboardBrightnessReading> client;
    static bool tried;
    if (!tried) {
        tried = true;
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"] load];
        Class cls = NSClassFromString(@"KeyboardBrightnessClient");
        id candidate = [[cls alloc] init];
        NSMethodSignature *signature = [candidate methodSignatureForSelector:@selector(brightnessForKeyboard:)];
        if ([candidate respondsToSelector:@selector(copyKeyboardBacklightIDs)] &&
            signature.numberOfArguments == 3 && !strcmp(signature.methodReturnType, @encode(float)))
            client = candidate;
    }
    if (!client) return false;
    NSArray *ids = [client copyKeyboardBacklightIDs];
    if (![ids isKindOfClass:NSArray.class] || !ids.count || ![ids.firstObject isKindOfClass:NSNumber.class]) return false;
    uint64_t keyboard = [ids.firstObject unsignedLongLongValue];
    if ([(id)client respondsToSelector:@selector(isKeyboardBuiltIn:)])
        for (id identifier in ids)
            if ([identifier isKindOfClass:NSNumber.class] && [client isKeyboardBuiltIn:[identifier unsignedLongLongValue]]) {
                keyboard = [identifier unsignedLongLongValue]; break;
            }
    float level = [client brightnessForKeyboard:keyboard];
    if (!isfinite(level) || level < 0 || level > 1) return false;
    *percent = (int)lround(level * 100);
    return true;
}

static bool readSMCKeyboard(int *percent) {
    if (smcFailed) return false;
    if (!smc) {
        io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
        if (!service) return false;
        IOReturn rc = IOServiceOpen(service, mach_task_self(), 0, &smc);
        IOObjectRelease(service);
        if (rc != KERN_SUCCESS) { smcError = rc; smcIssue = "open denied"; smc = 0; smcFailed = true; return false; }
    }
    SMCMessage input = {0}, output = {0};
    input.key = 0x4c4b5342; // LKSB
    size_t size = sizeof(output);
    if (!keyKnown) {
        input.command = 9;
        smcIssue = "LKSB metadata unavailable or unsupported";
        if ((smcError = IOConnectCallStructMethod(smc, 2, &input, sizeof(input), &output, &size)) ||
            size != sizeof(output) || output.result || output.info.size != 2 || output.info.type != 0x7b6c6b62) goto unavailable;
        keyKnown = true;
    }
    input.command = 5;
    input.info.size = 2;
    size = sizeof(output);
    memset(&output, 0, sizeof(output));
    smcIssue = "LKSB read failed";
    if ((smcError = IOConnectCallStructMethod(smc, 2, &input, sizeof(input), &output, &size)) ||
        size != sizeof(output) || output.result) goto unavailable;
    // AsusSMC decodes the high twelve bits and keeps this value in VirtualSMC.
    *percent = (int)lround((((unsigned)output.bytes[0] << 4) | (output.bytes[1] >> 4)) * 100.0 / 4095.0);
    return true;
unavailable:
    IOServiceClose(smc); smc = 0; smcFailed = true;
    return false;
}

static bool readKeyboard(int *percent) {
    // Read the system setting first. Fall back to VirtualSMC's cached value.
    return readCoreBrightness(percent) || readSMCKeyboard(percent);
}

static bool readTouchpad(int *enabled) {
    if (!asus) asus = IOServiceGetMatchingService(0, IOServiceMatching("AsusSMC"));
    if (!asus) return false;
    CFTypeRef value = IORegistryEntryCreateCFProperty(asus, CFSTR("IsTouchpadEnabled"), NULL, 0);
    if (!value) { IOObjectRelease(asus); asus = 0; return false; }
    bool valid = CFGetTypeID(value) == CFBooleanGetTypeID();
    if (valid) *enabled = CFBooleanGetValue(value);
    CFRelease(value);
    return valid;
}

@interface FnBrightnessSlider : NSSlider
@end
@implementation FnBrightnessSlider
- (void)mouseDown:(NSEvent *)event {
    menuSliderTracking = true; [super mouseDown:event]; menuSliderTracking = false; updateMenu();
}
@end

@interface FnLamp : NSView
@end
@implementation FnLamp
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSColor *orange = [NSColor colorWithSRGBRed:1.0 green:106.0/255.0 blue:0 alpha:1];
    NSShadow *glow = [NSShadow new];
    glow.shadowColor = [orange colorWithAlphaComponent:0.8];
    glow.shadowBlurRadius = 3;
    [NSGraphicsContext saveGraphicsState];
    [glow set];
    [orange setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:0.6 yRadius:0.6] fill];
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface AccessibilityDragIcon : NSImageView <NSDraggingSource>
@property (nonatomic, strong) NSURL *appURL;
@property (nonatomic, strong) NSEvent *mouseDownEvent;
@end

@implementation AccessibilityDragIcon
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)mouseDown:(NSEvent *)event { self.mouseDownEvent = event; }
- (void)mouseUp:(NSEvent *)event { (void)event; self.mouseDownEvent = nil; }
- (void)mouseDragged:(NSEvent *)event {
    (void)event;
    NSEvent *mouseDown = self.mouseDownEvent;
    if (!mouseDown || !self.appURL) return;
    self.mouseDownEvent = nil;
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:self.appURL];
    [item setDraggingFrame:self.bounds contents:self.image];
    NSDraggingSession *session = [self beginDraggingSessionWithItems:@[item] event:mouseDown source:self];
    session.animatesToStartingPositionsOnCancelOrFail = NO;
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    (void)session; (void)context; return NSDragOperationCopy;
}
@end

@interface FnMenuController : NSObject <NSMenuDelegate, NSApplicationDelegate>
@end
static FnMenuController *menuController;
static bool menuVisible, menuOpening, trackpadConfirmPending, hideConfirmPending, optionsExpanded;
static NSUInteger menuGeneration;
static NSString *const openMenuNotification = @"com.samuelnotfound.X1605VAAssistant.Agent.OpenMenu";
static NSStatusItem *statusItem;
static FnLamp *muteLamp;
static NSMenuItem *microphoneItem, *trackpadItem, *keyboardItem, *headingItem, *hideItem, *hideConfirmationItem, *trackpadConfirmationItem, *accessibilityItem, *accessibilityHintItem, *monitoringStatusItem, *permissionSeparatorItem;
static NSSwitch *microphoneSwitch, *trackpadSwitch;
static NSButton *optionsButton, *hideButton, *updateButton;
static NSMenuItem *optionsItem;
static NSString *availableVersion;
static bool checkingUpdates;
static NSString *const releaseTagPrefix = @"x1605va-assistant-v";
static NSString *const installGuideURL = @"https://github.com/samuelnotfound/Asus-X1605VA-Hackintosh/tree/main/Projects/ASUS/X1605VAAssistant/Downloads";
static float microphoneVolume;
static NSView *trackpadConfirmation, *microphoneRow, *trackpadRow, *keyboardRow;
static NSImageView *microphoneIcon;
static NSTextField *microphoneTitle, *trackpadTitle, *microphoneStatus, *trackpadStatus, *menuKeyboardPercent;
static NSTimer *hardwarePollTimer, *feedbackTimer;
typedef NS_ENUM(NSInteger, FeedbackKind) { FeedbackFn, FeedbackMicrophone, FeedbackTrackpad, FeedbackKeyboard };
static FeedbackKind feedbackKind;
static bool feedbackEnabled;
static int feedbackLevel;
static NSString *renderedStatus;
static NSImage *fnImage(void);
static void showFeedback(FeedbackKind kind, bool enabled, int percent);
static void startHardwarePolling(void);
static FnBrightnessSlider *menuKeyboardSlider;
static NSSlider *menuDisplaySlider;
static NSTextField *menuDisplayPercent;
static int displayPercent = -1;

// XeShim's xe-brilho utility maps BAR0 and controls panel PWM controller 1.
// Read when requested is negative. Only the PWM duty register is writable here.
static int xeDisplayBrightness(int requested) {
    enum { pwmControl = 0xc8250, pwmFrequency = 0xc8254, pwmDuty = 0xc8258 };
    io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("XeShim"));
    if (!service) return -1;

    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return -1;

    mach_vm_address_t address = 0;
    mach_vm_size_t length = 0;
    IOOptionBits options = kIOMapAnywhere;
    if (requested < 0) options |= kIOMapReadOnly;
    result = IOConnectMapMemory64(connection, 0, mach_task_self(), &address, &length, options);
    int percent = -1;
    if (result == KERN_SUCCESS) {
        if (address && length >= pwmDuty + sizeof(uint32_t)) {
            volatile uint32_t *bar = (volatile uint32_t *)(uintptr_t)address;
            uint32_t period = bar[pwmFrequency / sizeof(uint32_t)];
            if ((bar[pwmControl / sizeof(uint32_t)] & 0x80000000u) && period && period != 0xdeadbeefu) {
                if (requested >= 0) {
                    double level = fmax(1, fmin(100, requested)) / 100.0;
                    uint32_t duty = (uint32_t)llround(period * pow(level, 2.2));
                    bar[pwmDuty / sizeof(uint32_t)] = duty ? duty : 1;
                }
                uint32_t duty = bar[pwmDuty / sizeof(uint32_t)];
                if (duty <= period)
                    percent = (int)fmax(1, lround(100.0 * pow((double)duty / period, 1.0 / 2.2)));
            }
        }
        IOConnectUnmapMemory64(connection, 0, mach_task_self(), address);
    }
    IOServiceClose(connection);
    return percent;
}
static int trackpadTarget = -1;
static CFAbsoluteTime trackpadDeadline;
static NSTimer *trackpadConfirmTimer;

static void positionLamp(void) {
    if (!statusItem.button || !muteLamp) return;
    NSRect image = [statusItem.button.cell imageRectForBounds:statusItem.button.bounds];
    // Place the 3pt lamp within the keycap, independent of status-button size.
    muteLamp.frame = NSMakeRect(NSMinX(image) + 17, NSMinY(image) + (statusItem.button.isFlipped ? 3 : 8), 7, 7);
}


static void pollHardware(void) {
    int keyboard, touchpad;
    int previousTouchpad = lastTouchpad;
    if (!firmwareKeyboard) lastKeyboard = readKeyboard(&keyboard) ? keyboard : -1;
    else if (menuVisible && firmwareKeyboard == 2 && !menuSliderTracking && AsusKeyboardGet(&keyboard)) lastKeyboard = keyboard;
    bool known = AsusTrackpadGet(&touchpad);
    trackpadControllable = known && AsusTrackpadAvailable();
    if (known) { lastTouchpad = touchpad; if (!touchpad) trackpadConfirmPending = false; }
    else lastTouchpad = readTouchpad(&touchpad) ? touchpad : -1;
    if (keyAccessReady && trackpadTarget < 0 && previousTouchpad >= 0 && lastTouchpad >= 0 && previousTouchpad != lastTouchpad)
        showFeedback(FeedbackTrackpad, lastTouchpad != 0, 0);
    if (trackpadTarget >= 0) {
        if (known && touchpad == trackpadTarget) { trackpadTarget = -1; trackpadError = false; }
        else if (CFAbsoluteTimeGetCurrent() >= trackpadDeadline) { trackpadTarget = -1; trackpadError = true; }
        if (trackpadTarget < 0) { [trackpadConfirmTimer invalidate]; trackpadConfirmTimer = nil; }
    }
    updateMenu();
}
static void startHardwarePolling(void) {
    [hardwarePollTimer invalidate];
    hardwarePollTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { (void)timer; pollHardware(); }];
    [NSRunLoop.mainRunLoop addTimer:hardwarePollTimer forMode:NSRunLoopCommonModes];
}

static void requestTrackpadState(bool desired) {
    if (!keyAccessReady || trackpadTarget >= 0 || !trackpadControllable) { updateMenu(); return; }
    trackpadError = !AsusTrackpadSet(desired);
    if (!trackpadError) {
        // ACPI queues a notification. Wait for actual driver state, without
        // sleeping the UI thread, repeating a toggle, or claiming early success.
        trackpadTarget = desired; trackpadDeadline = CFAbsoluteTimeGetCurrent() + 1.5;
        trackpadConfirmTimer = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
            (void)timer; pollHardware();
        }];
        [NSRunLoop.mainRunLoop addTimer:trackpadConfirmTimer forMode:NSRunLoopCommonModes];
    }
    pollHardware();
}

static NSString *installedVersion(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

static bool isReleaseVersion(NSString *version) {
    return [version isKindOfClass:NSString.class] &&
        [version rangeOfString:@"^[0-9]+[.][0-9]+[.][0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}

// Releases are published as prereleases, so GitHub's /latest endpoint would
// skip them. Match only Assistant releases that identify an exact source commit.
static NSString *newerReleaseVersion(id releases, NSString *current) {
    if (![releases isKindOfClass:NSArray.class] || !isReleaseVersion(current)) return nil;
    NSString *best = current;
    for (id release in releases) {
        if (![release isKindOfClass:NSDictionary.class]) continue;
        id tag = release[@"tag_name"];
        id draft = release[@"draft"];
        id commit = release[@"target_commitish"];
        if (![tag isKindOfClass:NSString.class] || ![tag hasPrefix:releaseTagPrefix] ||
            ![draft isKindOfClass:NSNumber.class] || [draft boolValue] ||
            ![commit isKindOfClass:NSString.class] || [commit length] != 40 ||
            [commit rangeOfString:@"^[0-9a-f]{40}$" options:NSRegularExpressionSearch].location == NSNotFound) continue;
        NSString *version = [tag substringFromIndex:releaseTagPrefix.length];
        if (isReleaseVersion(version) && [version compare:best options:NSNumericSearch] == NSOrderedDescending)
            best = version;
    }
    return [best isEqualToString:current] ? nil : best;
}

static void checkForUpdates(void) {
    NSString *version = installedVersion();
    if (checkingUpdates || !isReleaseVersion(version)) return;
    checkingUpdates = true;
    updateButton.enabled = NO;
    updateButton.title = @"Checking for Updates…";
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/samuelnotfound/Asus-X1605VA-Hackintosh/releases?per_page=30"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        id releases = !error && http.statusCode == 200 && data.length
            ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
            checkingUpdates = false;
            updateButton.enabled = YES;
            bool valid = [releases isKindOfClass:NSArray.class];
            if (valid) availableVersion = newerReleaseVersion(releases, version);
            updateButton.title = availableVersion
                ? [NSString stringWithFormat:@"Update Instructions %@…", availableVersion]
                : valid ? @"Up to Date · Check Again" : @"Check for Updates (Retry)";
        });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    }] resume];
}

@implementation FnMenuController
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return NO; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    (void)sender; (void)visible; AsusMenuOpen(); return YES;
}
- (void)microphoneChanged:(NSSwitch *)sender {
    if (!keyAccessReady) { updateMenu(); return; }
    AsusMicrophoneSetEnabled(sender.state == NSControlStateValueOn);
    updateMenu(); // The switch always returns to the confirmed state on failure.
}
- (void)trackpadChanged:(NSSwitch *)sender {
    if (!keyAccessReady || trackpadConfirmPending || trackpadTarget >= 0 || !trackpadControllable) { updateMenu(); return; }
    bool desired = sender.state == NSControlStateValueOn;
    if (!desired && lastTouchpad > 0) { trackpadConfirmPending = true; updateMenu(); }
    else requestTrackpadState(desired);
}
- (void)cancelTrackpad:(id)sender { (void)sender; trackpadConfirmPending = false; updateMenu(); }
- (void)confirmTrackpad:(id)sender {
    (void)sender;
    if (!trackpadConfirmPending) return;
    trackpadConfirmPending = false; requestTrackpadState(false);
}
- (void)menuBrightnessChanged:(NSSlider *)sender { requestKeyboard((int)lround(sender.doubleValue)); }
- (void)menuDisplayBrightnessChanged:(NSSlider *)sender {
    if (!keyAccessReady || displayPercent < 0) return;
    displayPercent = xeDisplayBrightness((int)lround(sender.doubleValue));
    if (displayPercent >= 0) sender.doubleValue = displayPercent;
    updateMenu();
}
- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu; menuVisible = true;
    displayPercent = xeDisplayBrightness(-1);
    if (displayPercent >= 0) menuDisplaySlider.doubleValue = displayPercent;
    if (firmwareKeyboard == 2) {
        int percent;
        keyboardControllable = AsusKeyboardGet(&percent);
        if (keyboardControllable) lastKeyboard = percent;
    }
    pollHardware();
}
- (void)menuDidClose:(NSMenu *)menu { (void)menu; menuVisible = false; menuOpening = false; trackpadConfirmPending = false; hideConfirmPending = false; optionsExpanded = false; ++menuGeneration; updateMenu(); }
- (void)openKeyboardPrivacy:(NSMenuItem *)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)toggleOptions:(NSButton *)sender {
    (void)sender;
    optionsExpanded = !optionsExpanded;
    updateMenu();
}
- (void)updateAction:(id)sender {
    (void)sender;
    if (!availableVersion) { checkForUpdates(); return; }
    [statusItem.menu cancelTracking];
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:installGuideURL]];
}
- (void)uninstall:(id)sender {
    (void)sender;
    [statusItem.menu cancelTracking];
    // Let menu tracking unwind before presenting the app's confirmation dialog.
    dispatch_async(dispatch_get_main_queue(), ^{ AsusHelperUninstall(); });
}
- (void)hide:(id)sender { (void)sender; hideConfirmPending = true; updateMenu(); }
- (void)cancelHide:(id)sender { (void)sender; hideConfirmPending = false; updateMenu(); }
- (void)confirmHide:(id)sender {
    (void)sender;
    if (!hideConfirmPending) return;
    hideConfirmPending = false;
    menuOpening = false;
    ++menuGeneration;
    [statusItem.menu cancelTracking];
    statusItem.visible = NO;
    updateMenu();
}
@end

static NSMenuItem *menuAction(NSMenu *menu, NSString *title, SEL action) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = menuController;
    [menu addItem:item];
    return item;
}
static NSImage *fnImage(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(28, 18) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        (void)bounds;
        [NSColor.blackColor setStroke];
        NSBezierPath *key = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 1, 25, 16) xRadius:3 yRadius:3];
        key.lineWidth = 1.2; [key stroke];
        [@"fn" drawAtPoint:NSMakePoint(4.5, 2.0) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium], NSForegroundColorAttributeName:NSColor.blackColor}];
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = @"Fn key";
    return image;
}
static NSMenuItem *switchRow(NSMenu *menu, NSString *title, NSString *symbol, SEL action,
                              NSSwitch *__strong *control, NSTextField *__strong *label, NSTextField *__strong *status, NSImageView *__strong *iconOut) {
    NSMenuItem *item = menuAction(menu, title, NULL);
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 52)];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 16, 20, 20)];
    icon.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    [row addSubview:icon];
    NSTextField *text = [NSTextField labelWithString:title];
    text.frame = NSMakeRect(46, 27, 167, 19);
    text.font = [NSFont menuFontOfSize:13];
    [row addSubview:text];
    NSTextField *detail = [NSTextField labelWithString:@"Unavailable"];
    detail.frame = NSMakeRect(46, 10, 167, 15);
    detail.font = [NSFont systemFontOfSize:11]; detail.textColor = NSColor.secondaryLabelColor;
    [row addSubview:detail]; *status = detail;
    NSSwitch *toggle = [[NSSwitch alloc] initWithFrame:NSMakeRect(229, 14, 38, 24)];
    toggle.target = menuController; toggle.action = action;
    [toggle setAccessibilityLabel:title];
    [row addSubview:toggle];
    *control = toggle; *label = text;
    if (iconOut) *iconOut = icon;
    item.view = row;
    return item;
}
static NSImage *feedbackImage(FeedbackKind kind, bool enabled, int percent) {
    NSString *symbol = kind == FeedbackMicrophone ? (enabled ? @"mic.fill" : @"mic.slash.fill") :
        kind == FeedbackTrackpad ? @"rectangle.and.hand.point.up.left" : @"light.max";
    NSImage *base = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    NSImageSymbolConfiguration *symbolStyle = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular];
    if (@available(macOS 13.0, *)) symbolStyle = [symbolStyle configurationByApplyingConfiguration:NSImageSymbolConfiguration.configurationPreferringMonochrome];
    if (@available(macOS 12.0, *)) {
        if (kind == FeedbackKeyboard) symbolStyle = [symbolStyle configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.whiteColor]]];
    }
    base = [base imageWithSymbolConfiguration:symbolStyle];
    CGFloat opacity = kind == FeedbackKeyboard && enabled ? (percent <= 33 ? 0.40 : percent <= 67 ? 0.70 : 1.0) : 1.0;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(20, 18) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        NSRect area = NSInsetRect(bounds, 1, 1);
        NSSize size = base.size;
        CGFloat scale = fmin(NSWidth(area)/fmax(1,size.width), NSHeight(area)/fmax(1,size.height));
        NSRect fitted = NSMakeRect(NSMidX(area)-size.width*scale/2, NSMidY(area)-size.height*scale/2, size.width*scale, size.height*scale);
        [base drawInRect:fitted fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:opacity];
        if ((kind == FeedbackMicrophone && !enabled) || kind == FeedbackKeyboard) {
            [NSGraphicsContext saveGraphicsState];
            [(kind == FeedbackKeyboard ? NSColor.whiteColor : NSColor.systemRedColor) setFill];
            NSRectFillUsingOperation(bounds, NSCompositingOperationSourceAtop);
            [NSGraphicsContext restoreGraphicsState];
        }
        if (!enabled && kind != FeedbackMicrophone) {
            NSBezierPath *slash = [NSBezierPath bezierPath]; [slash moveToPoint:NSMakePoint(2, 1)]; [slash lineToPoint:NSMakePoint(18, 17)];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationClear;
            slash.lineWidth = 3.5; [slash stroke];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationSourceOver;
            [(kind == FeedbackKeyboard ? NSColor.whiteColor : NSColor.blackColor) setStroke]; slash.lineWidth = 1.4; [slash stroke];
        }
        return YES;
    }];
    if (kind == FeedbackKeyboard && enabled) {
        // SF symbols can carry an intrinsic dimmed alpha. Normalize the mask,
        // then apply our explicit three brightness levels. Keep a 2x bitmap.
        NSBitmapImageRep *pixels = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:36 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:pixels];
        NSRect raster = NSMakeRect(0,0,40,36); NSRectFillUsingOperation(raster, NSCompositingOperationClear);
        [image drawInRect:raster fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [NSGraphicsContext restoreGraphicsState];
        unsigned char *rgba = pixels.bitmapData; NSInteger stride = pixels.bytesPerRow;
        unsigned char peak = 0;
        for (NSInteger y=0;y<36;y++) for (NSInteger x=0;x<40;x++) if (rgba[y*stride+x*4+3] > peak) peak=rgba[y*stride+x*4+3];
        if (peak) for (NSInteger y=0;y<36;y++) for (NSInteger x=0;x<40;x++) {
            unsigned char *sample = rgba+y*stride+x*4;
            unsigned char alpha = (unsigned char)lround(sample[3] * opacity * 255.0 / peak);
            sample[0] = sample[1] = sample[2] = sample[3] = alpha; // premultiplied white RGBA
        }
        pixels.size = NSMakeSize(20,18); image = [[NSImage alloc] initWithSize:pixels.size]; [image addRepresentation:pixels];
    }
    image.template = kind != FeedbackKeyboard && !(kind == FeedbackMicrophone && !enabled);
    return image;
}
static void renderStatusIcon(void) {
    int bucket = feedbackLevel <= 33 ? 1 : feedbackLevel <= 67 ? 2 : 3;
    NSString *key = [NSString stringWithFormat:@"%ld-%d-%d", (long)feedbackKind, feedbackEnabled, bucket];
    if ([renderedStatus isEqualToString:key]) return;
    statusItem.button.image = feedbackKind == FeedbackFn ? fnImage() : feedbackImage(feedbackKind, feedbackEnabled, feedbackLevel);
    renderedStatus = key;
}
static void showFeedback(FeedbackKind kind, bool enabled, int percent) {
    feedbackKind = kind; feedbackEnabled = enabled; feedbackLevel = percent;
    [feedbackTimer invalidate];
    feedbackTimer = [NSTimer timerWithTimeInterval:1.2 repeats:NO block:^(NSTimer *timer) {
        (void)timer; feedbackKind = FeedbackFn; updateMenu();
    }];
    [NSRunLoop.mainRunLoop addTimer:feedbackTimer forMode:NSRunLoopCommonModes];
}

static bool microphoneWritable;
static void updateMenu(void) {
    if (!statusItem) return;
    renderStatusIcon();
    positionLamp();
    muteLamp.hidden = feedbackKind != FeedbackFn || !muteKnown || !lastMute;
    microphoneSwitch.enabled = keyAccessReady && muteKnown && microphoneWritable;
    microphoneSwitch.state = muteKnown && !lastMute ? NSControlStateValueOn : NSControlStateValueOff;
    microphoneIcon.image = [NSImage imageWithSystemSymbolName:muteKnown && lastMute ? @"mic.slash.fill" : @"mic.fill" accessibilityDescription:@"Microphone"];
    microphoneTitle.textColor = microphoneSwitch.enabled ? NSColor.labelColor : NSColor.secondaryLabelColor;
    microphoneIcon.contentTintColor = muteKnown && lastMute ? NSColor.systemRedColor : NSColor.labelColor;
    microphoneRow.toolTip = nil; microphoneSwitch.toolTip = nil;
    microphoneStatus.stringValue = muteKnown
        ? [NSString stringWithFormat:@"Input volume %ld%%", lroundf(microphoneVolume * 100)]
        : @"Unavailable";
    trackpadSwitch.enabled = keyAccessReady && trackpadControllable && trackpadTarget < 0 && !trackpadConfirmPending;
    trackpadSwitch.state = lastTouchpad > 0 ? NSControlStateValueOn : NSControlStateValueOff;
    trackpadTitle.textColor = trackpadControllable ? NSColor.labelColor : NSColor.secondaryLabelColor;
    trackpadRow.toolTip = nil; trackpadSwitch.toolTip = nil;
    trackpadStatus.stringValue = lastTouchpad < 0 ? @"Unavailable" : lastTouchpad ? @"Enabled" : @"Disabled";
    menuDisplaySlider.enabled = keyAccessReady && displayPercent >= 0;
    menuDisplayPercent.stringValue = displayPercent >= 0
        ? [NSString stringWithFormat:@"%d%%", displayPercent] : @"Unavailable";
    menuKeyboardSlider.enabled = keyAccessReady && keyboardControllable;
    if (!menuSliderTracking) {
        if (lastKeyboard >= 0) menuKeyboardSlider.doubleValue = lastKeyboard;
        menuKeyboardPercent.stringValue = lastKeyboard >= 0 ? [NSString stringWithFormat:@"%d%%", lastKeyboard] : @"Unavailable";
    }
    accessibilityItem.title = permissionAX ? @"Accessibility: Granted" : @"Accessibility: Not Granted…";
    accessibilityItem.hidden = permissionAX;
    accessibilityHintItem.hidden = permissionAX;
    permissionSeparatorItem.hidden = permissionAX && keyAccessReady;
    accessibilityItem.state = permissionAX ? NSControlStateValueOn : NSControlStateValueOff;
    monitoringStatusItem.hidden = keyAccessReady || !permissionAX;
    trackpadConfirmationItem.hidden = !trackpadConfirmPending;
    optionsItem.hidden = !optionsExpanded;
    optionsButton.toolTip = optionsExpanded ? @"Hide options" : @"Show options";
    hideButton.enabled = !hideConfirmPending;
    hideConfirmationItem.hidden = !hideConfirmPending;
    statusItem.button.toolTip = [NSString stringWithFormat:@"X1605VA Assistant — %@", !muteKnown ? @"Microphone unavailable" : lastMute ? @"Microphone muted" : @"Microphone on"];
    [statusItem.button setAccessibilityLabel:statusItem.button.toolTip];
}
static void startMenu(void) {
    CFRunLoopAddCommonMode(CFRunLoopGetMain(), (__bridge CFStringRef)NSEventTrackingRunLoopMode);
    menuController = [FnMenuController new];
    NSApp.delegate = menuController;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:openMenuNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note; AsusMenuOpen();
    }];
    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:36];
    statusItem.button.image = fnImage();
    statusItem.button.imageScaling = NSImageScaleProportionallyDown;
    muteLamp = [[FnLamp alloc] initWithFrame:NSZeroRect];
    [muteLamp setAccessibilityElement:NO];
    [statusItem.button addSubview:muteLamp];
    statusItem.button.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:NSViewFrameDidChangeNotification object:statusItem.button queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        (void)note; positionLamp();
    }];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"X1605VA Assistant"];
    menu.autoenablesItems = NO; menu.delegate = menuController;
    headingItem = menuAction(menu, @"X1605VA Assistant", NULL);
    NSView *heading = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 30)];
    NSTextField *name = [NSTextField labelWithString:@"X1605VA Assistant"];
    name.frame = NSMakeRect(16, 6, 218, 19);
    name.font = [NSFont systemFontOfSize:13 weight:NSFontWeightBold]; name.textColor = NSColor.whiteColor;
    [heading addSubview:name];
    NSImage *ellipsis = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:@"More options"];
    optionsButton = [NSButton buttonWithImage:ellipsis target:menuController action:@selector(toggleOptions:)];
    optionsButton.frame = NSMakeRect(240, 2, 30, 26);
    optionsButton.bordered = NO;
    [optionsButton setAccessibilityLabel:@"More options"];
    [heading addSubview:optionsButton];
    headingItem.view = heading;

    optionsItem = menuAction(menu, @"Assistant Options", NULL);
    NSView *optionsRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 84)];
    NSString *version = installedVersion() ?: @"Unknown";
    NSTextField *versionLabel = [NSTextField labelWithString:[@"Version " stringByAppendingString:version]];
    versionLabel.frame = NSMakeRect(16, 60, 252, 18);
    versionLabel.font = [NSFont systemFontOfSize:11];
    versionLabel.textColor = NSColor.secondaryLabelColor;
    [optionsRow addSubview:versionLabel];
    updateButton = [NSButton buttonWithTitle:@"Check for Updates…" target:menuController action:@selector(updateAction:)];
    updateButton.frame = NSMakeRect(16, 33, 252, 25);
    [optionsRow addSubview:updateButton];
    NSButton *uninstallButton = [NSButton buttonWithTitle:@"Uninstall…" target:menuController action:@selector(uninstall:)];
    uninstallButton.frame = NSMakeRect(16, 5, 252, 25);
    [optionsRow addSubview:uninstallButton];
    optionsItem.view = optionsRow;

    accessibilityItem = menuAction(menu, @"Accessibility: Not Granted…", @selector(openKeyboardPrivacy:));
    accessibilityHintItem = menuAction(menu, @"Accessibility Setup", NULL);
    NSView *accessibilityHintRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 60)];
    AccessibilityDragIcon *permissionIcon = [[AccessibilityDragIcon alloc] initWithFrame:NSMakeRect(16, 10, 40, 40)];
    permissionIcon.appURL = NSBundle.mainBundle.bundleURL;
    permissionIcon.image = [NSWorkspace.sharedWorkspace iconForFile:permissionIcon.appURL.path];
    permissionIcon.imageScaling = NSImageScaleProportionallyUpOrDown;
    permissionIcon.toolTip = @"Drag X1605VA Assistant into Accessibility";
    [permissionIcon setAccessibilityLabel:permissionIcon.toolTip];
    [accessibilityHintRow addSubview:permissionIcon];
    NSTextField *accessibilityHint = [NSTextField wrappingLabelWithString:
        @"Remove any old entry, then drag this icon into the Accessibility list."];
    accessibilityHint.frame = NSMakeRect(66, 9, 202, 42);
    accessibilityHint.font = [NSFont systemFontOfSize:11];
    accessibilityHint.textColor = NSColor.secondaryLabelColor;
    [accessibilityHintRow addSubview:accessibilityHint];
    accessibilityHintItem.view = accessibilityHintRow;
    monitoringStatusItem = menuAction(menu, @"Keyboard monitoring: Not Ready", NULL); monitoringStatusItem.enabled = NO;
    permissionSeparatorItem = NSMenuItem.separatorItem; [menu addItem:permissionSeparatorItem];
    microphoneItem = switchRow(menu, @"Microphone", @"mic.fill", @selector(microphoneChanged:), &microphoneSwitch, &microphoneTitle, &microphoneStatus, &microphoneIcon);
    microphoneRow = microphoneItem.view;
    trackpadItem = switchRow(menu, @"Trackpad", @"rectangle.and.hand.point.up.left", @selector(trackpadChanged:), &trackpadSwitch, &trackpadTitle, &trackpadStatus, NULL);
    trackpadRow = trackpadItem.view;
    trackpadConfirmationItem = menuAction(menu, @"Confirm Trackpad Disable", NULL);
    trackpadConfirmation = [[NSView alloc] initWithFrame:NSMakeRect(0,0,284,96)];
    NSTextField *question = [NSTextField labelWithString:@"Are you sure?"];
    question.frame = NSMakeRect(16,71,252,18); question.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    NSTextField *hint = [NSTextField labelWithString:@"Press Fn+F6 to turn it back on."];
    hint.frame = NSMakeRect(16,48,252,18); hint.font = [NSFont systemFontOfSize:11]; hint.textColor = NSColor.secondaryLabelColor;
    [trackpadConfirmation addSubview:question]; [trackpadConfirmation addSubview:hint];
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:menuController action:@selector(cancelTrackpad:)]; cancel.frame=NSMakeRect(16,9,116,28);
    NSButton *disable = [NSButton buttonWithTitle:@"Disable Trackpad" target:menuController action:@selector(confirmTrackpad:)]; disable.frame=NSMakeRect(140,9,128,28);
    [trackpadConfirmation addSubview:cancel]; [trackpadConfirmation addSubview:disable]; trackpadConfirmationItem.view = trackpadConfirmation;
    [menu addItem:NSMenuItem.separatorItem];
    keyboardItem = menuAction(menu, @"Keyboard Backlight", NULL);
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 64)];
    NSTextField *title = [NSTextField labelWithString:@"Keyboard Backlight"];
    title.frame = NSMakeRect(16, 39, 188, 16);
    title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [row addSubview:title];
    menuKeyboardPercent = [NSTextField labelWithString:@"Unavailable"];
    menuKeyboardPercent.frame = NSMakeRect(198, 39, 70, 16);
    menuKeyboardPercent.alignment = NSTextAlignmentRight;
    menuKeyboardPercent.font = [NSFont systemFontOfSize:12];
    menuKeyboardPercent.textColor = NSColor.secondaryLabelColor;
    [row addSubview:menuKeyboardPercent];
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 11, 20, 20)];
    icon.image = [NSImage imageWithSystemSymbolName:@"light.max" accessibilityDescription:@"Keyboard backlight"];
    [row addSubview:icon];
    menuKeyboardSlider = [[FnBrightnessSlider alloc] initWithFrame:NSMakeRect(44, 9, 224, 24)];
    menuKeyboardSlider.minValue = 0; menuKeyboardSlider.maxValue = 100;
    menuKeyboardSlider.continuous = YES;
    menuKeyboardSlider.trackFillColor = NSColor.systemGrayColor;
    menuKeyboardSlider.target = menuController; menuKeyboardSlider.action = @selector(menuBrightnessChanged:);
    [menuKeyboardSlider setAccessibilityLabel:@"Keyboard brightness"];
    [row addSubview:menuKeyboardSlider]; keyboardItem.view = row;
    keyboardRow = keyboardItem.view;

    NSMenuItem *displayItem = menuAction(menu, @"Screen Brightness", NULL);
    NSView *displayRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 64)];
    NSTextField *displayTitle = [NSTextField labelWithString:@"Screen Brightness"];
    displayTitle.frame = NSMakeRect(16, 39, 188, 16);
    displayTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [displayRow addSubview:displayTitle];

    menuDisplayPercent = [NSTextField labelWithString:@"Unavailable"];
    menuDisplayPercent.frame = NSMakeRect(198, 39, 70, 16);
    menuDisplayPercent.alignment = NSTextAlignmentRight;
    menuDisplayPercent.font = [NSFont systemFontOfSize:12];
    menuDisplayPercent.textColor = NSColor.secondaryLabelColor;
    [displayRow addSubview:menuDisplayPercent];

    NSImageView *displayIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 11, 20, 20)];
    displayIcon.image = [NSImage imageWithSystemSymbolName:@"sun.max" accessibilityDescription:@"Screen brightness"];
    [displayRow addSubview:displayIcon];

    menuDisplaySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(44, 9, 224, 24)];
    menuDisplaySlider.minValue = 1;
    menuDisplaySlider.maxValue = 100;
    menuDisplaySlider.continuous = NO;
    menuDisplaySlider.trackFillColor = NSColor.systemGrayColor;
    menuDisplaySlider.target = menuController;
    menuDisplaySlider.action = @selector(menuDisplayBrightnessChanged:);
    [menuDisplaySlider setAccessibilityLabel:@"Screen brightness"];
    [displayRow addSubview:menuDisplaySlider];
    displayItem.view = displayRow;

    [menu addItem:NSMenuItem.separatorItem];
    hideItem = menuAction(menu, @"Hide", NULL);
    NSView *hideActionRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 24)];
    hideButton = [NSButton buttonWithTitle:@"Hide" target:menuController action:@selector(hide:)];
    // Match the original plain menu row while keeping clicks inside tracking.
    hideButton.bordered = NO;
    hideButton.alignment = NSTextAlignmentLeft;
    hideButton.font = [NSFont menuFontOfSize:0];
    hideButton.frame = NSMakeRect(16, 0, 252, 24);
    [hideActionRow addSubview:hideButton];
    hideItem.view = hideActionRow;
    hideConfirmationItem = menuAction(menu, @"Confirm Hide", NULL);
    NSView *hideRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 284, 96)];
    NSTextField *hideQuestion = [NSTextField labelWithString:@"Are you sure?"];
    hideQuestion.frame = NSMakeRect(16, 72, 252, 18);
    hideQuestion.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    NSTextField *hideHint = [NSTextField wrappingLabelWithString:@"Reopen X1605VA Assistant to bring it back to the menu bar."];
    hideHint.frame = NSMakeRect(16, 40, 252, 30);
    hideHint.font = [NSFont systemFontOfSize:11];
    hideHint.textColor = NSColor.secondaryLabelColor;
    NSButton *hideCancel = [NSButton buttonWithTitle:@"Cancel" target:menuController action:@selector(cancelHide:)];
    hideCancel.frame = NSMakeRect(16, 7, 116, 28);
    NSButton *hideConfirm = [NSButton buttonWithTitle:@"Hide" target:menuController action:@selector(confirmHide:)];
    hideConfirm.frame = NSMakeRect(144, 7, 124, 28);
    [hideRow addSubview:hideQuestion];
    [hideRow addSubview:hideHint];
    [hideRow addSubview:hideCancel];
    [hideRow addSubview:hideConfirm];
    hideConfirmationItem.view = hideRow;
    statusItem.menu = menu;
    updateMenu();
}
static void commitKeyboard(void) {
    int confirmed = pendingKeyboard;
    lastKeyboardWrite = CFAbsoluteTimeGetCurrent();
    if (!keyAccessReady) return;
    if (!AsusKeyboardSet(pendingKeyboard, &confirmed)) { if (keyAccessReady) keyboardControllable = false; }
    else lastKeyboard = confirmed;
    updateMenu();
}
static void requestKeyboard(int percent) {
    if (!keyAccessReady || !keyboardControllable || percent < 0 || percent > 100) return;
    pendingKeyboard = percent;
    menuKeyboardPercent.stringValue = [NSString stringWithFormat:@"%d%%", percent];
    [sliderCommitTimer invalidate];
    CFTimeInterval delay = fmax(0, 0.08 - (CFAbsoluteTimeGetCurrent() - lastKeyboardWrite));
    if (delay == 0) { commitKeyboard(); return; }
    sliderCommitTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) { (void)timer; commitKeyboard(); }];
    [NSRunLoop.mainRunLoop addTimer:sliderCommitTimer forMode:NSRunLoopCommonModes];
}
void AsusMenuStart(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    firmwareKeyboard = hasFirmwareKeyboardMarker();
    if (firmwareKeyboard == 2) keyboardControllable = AsusKeyboardGet(&lastKeyboard);
    io_service_t launcher = IOServiceGetMatchingService(0, IOServiceNameMatching("FNHK"));
    if (launcher) {
        CFTypeRef name = IORegistryEntryCreateCFProperty(launcher, CFSTR("name"), NULL, 0);
        firmwareLauncher = IOObjectConformsTo(launcher, "IOACPIPlatformDevice") && name &&
            CFGetTypeID(name) == CFDataGetTypeID() && CFDataGetLength(name) >= 8 &&
            !memcmp(CFDataGetBytePtr(name), "ASUSF121", 8);
        if (name) CFRelease(name);
        IOObjectRelease(launcher);
    }
    pollHardware(); startMenu();
    startHardwarePolling();
    checkForUpdates();
    NSTimer *updateTimer = [NSTimer timerWithTimeInterval:12 * 60 * 60 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        checkForUpdates();
    }];
    updateTimer.tolerance = 60 * 60;
    [NSRunLoop.mainRunLoop addTimer:updateTimer forMode:NSRunLoopCommonModes];
}
void AsusMenuMute(bool muted, bool writable, float volume) {
    microphoneVolume = volume;
    muteKnown = true; lastMute = muted; microphoneWritable = writable; microphoneError = false;
    updateMenu();
}
void AsusMenuMicrophoneKey(bool muted) {
    if (keyAccessReady && muteKnown && muted == lastMute) { showFeedback(FeedbackMicrophone, !muted, 0); updateMenu(); }
}
void AsusMenuMicrophoneUnavailable(void) { muteKnown = false; updateMenu(); }
void AsusMenuMicrophoneError(void) { microphoneError = true; updateMenu(); }
void AsusMenuSetPermissions(bool accessibility, bool ready) {
    permissionAX = accessibility;
    AsusMenuSetKeyAccess(ready);
}
void AsusMenuSetKeyAccess(bool ready) {
    keyAccessReady = ready;
    if (!ready) { [sliderCommitTimer invalidate]; sliderCommitTimer = nil; trackpadConfirmPending = false; }
    updateMenu();
}
bool AsusMenuFirmwareKeyboardAvailable(void) { return firmwareKeyboard != 0; }
bool AsusMenuFirmwareKeyboardContinuous(void) { return firmwareKeyboard == 2; }
void AsusMenuRefreshKeyboard(void) {
    int percent;
    if (firmwareKeyboard != 2) return;
    keyboardControllable = AsusKeyboardGet(&percent);
    if (keyboardControllable) {
        int previous = lastKeyboard; lastKeyboard = percent;
        if (previous >= 0 && previous != percent) showFeedback(FeedbackKeyboard, percent > 0, percent);
    }
    updateMenu();
}
void AsusMenuKeyboardLevel(int level) {
    if (!firmwareKeyboard || level < 0 || level > 3) return;
    int previous = lastKeyboard; lastKeyboard = (int)lround(level * 100.0 / 3.0);
    if (previous >= 0 && previous != lastKeyboard) showFeedback(FeedbackKeyboard, lastKeyboard > 0, lastKeyboard);
    updateMenu();
}
void AsusMenuRun(void) { [NSApp run]; }
int AsusMenuDiagnostics(void) {
    int keyboard, touchpad;
    printf("Keyboard firmware marker: %d\n", hasFirmwareKeyboardMarker());
    if (readKeyboard(&keyboard)) printf("Keyboard brightness cache: %d%%\n", keyboard);
    else printf("Keyboard brightness cache: unavailable (%s; 0x%08x)\n", smcIssue, smcError);
    if (AsusTrackpadGet(&touchpad)) printf("Trackpad bridge: %s\n", touchpad ? "enabled" : "disabled");
    else if (readTouchpad(&touchpad)) printf("AsusSMC trackpad cache (read-only): %s\n", touchpad ? "enabled" : "disabled");
    if (smc) IOServiceClose(smc);
    if (asus) IOObjectRelease(asus);
    return 0;
}

void AsusMenuOpen(void) {
    if (!statusItem || menuVisible || menuOpening || NSApp.modalWindow) return;
    statusItem.visible = YES;
    menuOpening = true; NSUInteger request = ++menuGeneration;
    // Open after the current callback unwinds, in a run-loop block that can
    // service nested menu tracking. Never hold a serial GCD callback open.
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{
        if (request != menuGeneration) return;
        if (menuOpening && !menuVisible && statusItem.button.window) [statusItem.button performClick:nil];
        if (request == menuGeneration) menuOpening = false;
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}
void AsusMenuToggle(void) {
    if (menuVisible || menuOpening) {
        menuOpening = false; ++menuGeneration; [statusItem.menu cancelTracking]; return;
    }
    AsusMenuOpen();
}
void AsusMenuOpenExisting(void) {
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:openMenuNotification object:nil userInfo:nil deliverImmediately:YES];
}
bool AsusMenuFirmwareLauncherAvailable(void) { return firmwareLauncher; }
static bool selectionOnElement(AXUIElementRef element) {
    for (NSString *attribute in @[(__bridge NSString *)kAXSelectedChildrenAttribute, (__bridge NSString *)kAXSelectedRowsAttribute]) {
        CFTypeRef value = NULL;
        if (AXUIElementCopyAttributeValue(element, (__bridge CFStringRef)attribute, &value) == kAXErrorSuccess && value) {
            bool selected = CFGetTypeID(value) == CFArrayGetTypeID() && CFArrayGetCount(value) > 0;
            CFRelease(value); if (selected) return true;
        }
    }
    CFTypeRef selected = NULL;
    bool yes = AXUIElementCopyAttributeValue(element, kAXSelectedAttribute, &selected) == kAXErrorSuccess &&
        selected && CFGetTypeID(selected) == CFBooleanGetTypeID() && CFBooleanGetValue(selected);
    if (selected) CFRelease(selected);
    return yes;
}
pid_t AsusFinderFrontmostPID(void) {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    return [front.bundleIdentifier isEqualToString:@"com.apple.finder"] ? front.processIdentifier : 0;
}
static bool finderEditableRole(CFStringRef role) {
    return CFEqual(role, kAXTextFieldRole) || CFEqual(role, kAXTextAreaRole) || CFEqual(role, kAXComboBoxRole);
}
bool AsusFinderItemsFocused(void) {
    pid_t pid = AsusFinderFrontmostPID(); if (!pid) return false;
    AXUIElementRef system = AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(system, 0.08f);
    CFTypeRef focused = NULL, role = NULL;
    bool items = false, editable = false;
    if (system && AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess &&
        focused && CFGetTypeID(focused) == AXUIElementGetTypeID() &&
        AXUIElementCopyAttributeValue((AXUIElementRef)focused, kAXRoleAttribute, &role) == kAXErrorSuccess && role) {
        editable = finderEditableRole(role);
        if (!editable) {
            AXUIElementRef current = (AXUIElementRef)CFRetain(focused);
            CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.25;
            for (int depth = 0; current && depth < 5 && CFAbsoluteTimeGetCurrent() < deadline; ++depth) {
                if (selectionOnElement(current)) { items = true; CFRelease(current); current = NULL; break; }
                CFTypeRef parent = NULL;
                AXUIElementCopyAttributeValue(current, kAXParentAttribute, &parent);
                CFRelease(current); current = NULL;
                if (parent && CFGetTypeID(parent) == AXUIElementGetTypeID()) current = (AXUIElementRef)parent;
                else if (parent) CFRelease(parent);
            }
            if (current) CFRelease(current);
        }
    }
    if (role) CFRelease(role); if (focused) CFRelease(focused); if (system) CFRelease(system);
    return items;
}
