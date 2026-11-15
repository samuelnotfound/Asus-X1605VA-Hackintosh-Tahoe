// Copyright (c) 2026 samuelnotfound. MIT License.
#import "X1605VASettingsPane.h"
#import "DeviceClient.h"
#import <QuartzCore/QuartzCore.h>

static NSTextField *label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *view = [NSTextField labelWithString:text];
    view.font = [NSFont systemFontOfSize:size weight:weight];
    return view;
}

// AppKit controls and dynamic system colors, arranged like MyASUS Device
// Settings. Cards represent firmware profiles, not arbitrary RPM targets.
@interface XProfileCard : NSButton
@property(nonatomic, copy) NSString *heading;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, copy) NSString *symbol;
@end

@implementation XProfileCard
- (BOOL)isFlipped { return NO; }
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.bordered = NO;
        [self setButtonType:NSButtonTypeMomentaryChange];
        self.title = @"";
    }
    return self;
}
- (void)drawRect:(NSRect)rect {
    (void)rect;
    BOOL selected = self.state == NSControlStateValueOn;
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:12 yRadius:12];
    [(selected ? [NSColor.controlAccentColor colorWithAlphaComponent:0.10] : NSColor.controlBackgroundColor) setFill];
    [outline fill];
    [(selected ? NSColor.controlAccentColor : NSColor.separatorColor) setStroke];
    outline.lineWidth = selected ? 2 : 1;
    [outline stroke];
    CGFloat opacity = self.enabled ? 1 : 0.4;
    NSImage *image = [[NSImage imageWithSystemSymbolName:self.symbol accessibilityDescription:nil]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:selected ? NSColor.controlAccentColor : NSColor.labelColor]];
    [image drawInRect:NSMakeRect(20, self.bounds.size.height - 53, 28, 28) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:opacity];
    NSDictionary *titleAttributes = @{NSFontAttributeName:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName:[NSColor.labelColor colorWithAlphaComponent:opacity]};
    [self.heading drawAtPoint:NSMakePoint(20, self.bounds.size.height - 83) withAttributes:titleAttributes];
    NSDictionary *detailAttributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName:[NSColor.secondaryLabelColor colorWithAlphaComponent:opacity]};
    [self.detail drawInRect:NSMakeRect(20, 16, self.bounds.size.width - 40, 48) withAttributes:detailAttributes];
    if (selected) {
        NSImage *check = [[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil]
            imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.controlAccentColor]];
        [check drawInRect:NSMakeRect(self.bounds.size.width - 38, self.bounds.size.height - 40, 20, 20) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:opacity];
    }
}
@end

@interface XSettingsBackground : NSView
@end
@implementation XSettingsBackground
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill]; NSRectFill(rect);
}
@end

@interface X1605VASettingsPane () {
    NSSegmentedControl *_sections;
    NSView *_powerPage, *_inputPage;
    NSArray<XProfileCard *> *_profiles;
    NSTextField *_rpm, *_profileStatus, *_keyboardValue, *_keyboardStatus, *_status, *_version;
    NSSlider *_keyboard;
    NSPopUpButton *_fanMode;
    NSTimer *_pollTimer, *_keyboardTimer;
    dispatch_queue_t _worker;
    NSDictionary *_snapshot;
    NSString *_lastError;
    NSString *_lastReadError;
    BOOL _active, _refreshing, _thermalBusy, _keyboardBusy;
    BOOL _settingsRefreshStopped;
    NSInteger _desiredKeyboard;
    NSUInteger _keyboardGeneration;
    NSTimeInterval _lastKeyboardInteraction;
}
@end

@implementation X1605VASettingsPane
- (NSView *)loadMainView {
    if (self.mainView) return self.mainView;
    _worker = dispatch_queue_create("com.samuelnotfound.X1605VASettings.controls", DISPATCH_QUEUE_SERIAL);
    _desiredKeyboard = -1;
    NSView *root = [[XSettingsBackground alloc] initWithFrame:NSMakeRect(0, 0, 720, 530)];
    NSTextField *title = label(@"X1605VA Settings", 24, NSFontWeightBold);
    title.frame = NSMakeRect(28, 473, 500, 34); [root addSubview:title];
    NSTextField *subtitle = label(@"Device Settings", 13, NSFontWeightRegular);
    subtitle.textColor = NSColor.secondaryLabelColor;
    subtitle.frame = NSMakeRect(28, 448, 500, 23); [root addSubview:subtitle];
    _sections = [NSSegmentedControl segmentedControlWithLabels:@[@"Power & Performance", @"Input Device Settings"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(sectionChanged:)];
    _sections.frame = NSMakeRect(28, 401, 664, 30); _sections.selectedSegment = 0;
    [root addSubview:_sections];
    _powerPage = [[NSView alloc] initWithFrame:NSMakeRect(28, 105, 664, 280)];
    _inputPage = [[NSView alloc] initWithFrame:_powerPage.frame];
    _inputPage.hidden = YES; [root addSubview:_powerPage]; [root addSubview:_inputPage];
    NSTextField *fanTitle = label(@"Fan Profile", 19, NSFontWeightSemibold);
    fanTitle.frame = NSMakeRect(0, 246, 440, 28); [_powerPage addSubview:fanTitle];
    NSTextField *fanDescription = label(@"Choose a balance of cooling, noise, and performance.", 13, NSFontWeightRegular);
    fanDescription.textColor = NSColor.secondaryLabelColor;
    fanDescription.frame = NSMakeRect(0, 219, 664, 23); [_powerPage addSubview:fanDescription];
    NSMutableArray *cards = [NSMutableArray array];
    NSArray *names = @[@"Performance", @"Standard", @"Whisper"];
    NSArray *details = @[@"Prioritize cooling for demanding tasks.", @"Balance performance and fan noise for everyday use.", @"Favor quieter operation for lighter tasks."];
    NSArray *symbols = @[@"speedometer", @"fan", @"leaf"];
    NSInteger values[] = {2, 0, 1};
    for (NSInteger index = 0; index < 3; ++index) {
        XProfileCard *card = [[XProfileCard alloc] initWithFrame:NSMakeRect(index * 226, 65, 212, 146)];
        card.heading = names[index]; card.detail = details[index]; card.symbol = symbols[index];
        card.tag = values[index]; card.target = self; card.action = @selector(profileChanged:);
        card.accessibilityLabel = [names[index] stringByAppendingString:@" fan profile"];
        card.enabled = NO; [cards addObject:card]; [_powerPage addSubview:card];
    }
    _profiles = cards;
    _profileStatus = label(@"Reading the active profile…", 12, NSFontWeightRegular);
    _profileStatus.textColor = NSColor.secondaryLabelColor;
    _profileStatus.frame = NSMakeRect(0, 35, 664, 24); [_powerPage addSubview:_profileStatus];
    _fanMode = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 184, 28) pullsDown:NO];
    [_fanMode addItemsWithTitles:@[@"Fan control…", @"Automatic", @"Full Speed"]];
    _fanMode.target = self; _fanMode.action = @selector(fanChanged:); _fanMode.enabled = NO;
    _fanMode.accessibilityLabel = @"Fan control"; [_powerPage addSubview:_fanMode];
    _rpm = label(@"System Fan: Unavailable", 13, NSFontWeightMedium);
    _rpm.frame = NSMakeRect(205, 2, 450, 24); [_powerPage addSubview:_rpm];
    NSTextField *keyboardTitle = label(@"Keyboard Backlight", 19, NSFontWeightSemibold);
    keyboardTitle.frame = NSMakeRect(0, 246, 500, 28); [_inputPage addSubview:keyboardTitle];
    NSTextField *keyboardDescription = label(@"Adjust the illumination of the built-in keyboard.", 13, NSFontWeightRegular);
    keyboardDescription.frame = NSMakeRect(0, 217, 664, 24);
    keyboardDescription.textColor = NSColor.secondaryLabelColor; [_inputPage addSubview:keyboardDescription];
    NSImageView *keyboardIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 149, 30, 30)];
    keyboardIcon.image = [NSImage imageWithSystemSymbolName:@"light.max" accessibilityDescription:@"Keyboard backlight"];
    keyboardIcon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:24 weight:NSFontWeightRegular];
    [_inputPage addSubview:keyboardIcon];
    _keyboard = [NSSlider sliderWithValue:0 minValue:0 maxValue:100 target:self action:@selector(keyboardChanged:)];
    _keyboard.frame = NSMakeRect(45, 150, 530, 28); _keyboard.continuous = YES; _keyboard.enabled = NO;
    _keyboard.accessibilityLabel = @"Keyboard backlight percentage"; [_inputPage addSubview:_keyboard];
    _keyboardValue = label(@"Unavailable", 13, NSFontWeightMedium);
    _keyboardValue.frame = NSMakeRect(584, 151, 80, 24); [_inputPage addSubview:_keyboardValue];
    NSTextField *off = label(@"Off", 11, NSFontWeightRegular); off.frame = NSMakeRect(45, 127, 80, 20);
    off.textColor = NSColor.secondaryLabelColor; [_inputPage addSubview:off];
    NSTextField *maximum = label(@"100%", 11, NSFontWeightRegular); maximum.frame = NSMakeRect(531, 127, 60, 20);
    maximum.textColor = NSColor.secondaryLabelColor; [_inputPage addSubview:maximum];
    _keyboardStatus = label(@"Checking keyboard-backlight support…", 12, NSFontWeightRegular);
    _keyboardStatus.frame = NSMakeRect(0, 77, 664, 40); _keyboardStatus.maximumNumberOfLines = 2;
    _keyboardStatus.textColor = NSColor.secondaryLabelColor; [_inputPage addSubview:_keyboardStatus];
    _status = label(@"Reading device settings…", 12, NSFontWeightRegular);
    _status.frame = NSMakeRect(28, 44, 664, 44); _status.maximumNumberOfLines = 2;
    _status.textColor = NSColor.secondaryLabelColor; [root addSubview:_status];
    _version = label(@"X1605VA Settings " @X1605VA_VERSION, 11, NSFontWeightRegular);
    _version.frame = NSMakeRect(28, 15, 664, 20); _version.textColor = NSColor.tertiaryLabelColor;
    [root addSubview:_version];
    [self setMainView:root]; [self setInitialKeyView:_sections]; [self setFirstKeyView:_sections]; [self setLastKeyView:_keyboard];
    return root;
}
- (void)didSelect {
    _active = YES;
    _settingsRefreshStopped = NO;
    _lastReadError = nil;
    [self refresh];
    __weak typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        (void)timer; [weakSelf refresh];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_pollTimer forMode:NSRunLoopCommonModes];
}
- (void)willUnselect {
    _active = NO; [_pollTimer invalidate]; _pollTimer = nil;
    // Finish a user's pending backlight selection; dismissing the pane does
    // not restore defaults, apply thermal settings, or start a login service.
    [_keyboardTimer invalidate]; _keyboardTimer = nil;
    [self commitKeyboard];
}
- (void)sectionChanged:(id)sender {
    (void)sender; _powerPage.hidden = _sections.selectedSegment != 0;
    _inputPage.hidden = _sections.selectedSegment != 1;
}
- (void)refresh {
    if (_refreshing || !_active) return;
    _refreshing = YES;
    BOOL refreshSettings = !_settingsRefreshStopped;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSDictionary *status = X1605VAReadStatus();
        NSError *readError = nil;
        if (refreshSettings && [status[@"SettingsRefreshAvailable"] boolValue]) {
            X1605VARefreshSettings(&readError);
            status = X1605VAReadStatus();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_refreshing = NO;
            if (!self->_active) return;
            self->_snapshot = status;
            self->_lastReadError = readError.localizedDescription;
            if (readError.code == 6) self->_settingsRefreshStopped = YES;
            [self displayStatus];
        });
    });
}
- (void)displayStatus {
    BOOL available = [_snapshot[@"Available"] boolValue];
    BOOL api = [_snapshot[@"X1605VA-ControlAPIVersion"] integerValue] == 1 &&
        [_snapshot[@"SettingsRefreshAvailable"] boolValue];
    BOOL fanAllowed = available && api && [_snapshot[@"FanControlAllowed"] boolValue] && !_thermalBusy;
    BOOL profileValid = [_snapshot[@"ThermalProfileValid"] boolValue];
    NSInteger profile = [_snapshot[@"ThermalProfile"] integerValue];
    for (XProfileCard *card in _profiles) {
        card.enabled = fanAllowed;
        card.state = profileValid && card.tag == profile ? NSControlStateValueOn : NSControlStateValueOff;
        card.accessibilityValue = card.state == NSControlStateValueOn ? @"Selected" : @"Not selected";
        [card setNeedsDisplay:YES];
    }
    if (!_thermalBusy) _profileStatus.stringValue = profileValid ?
        [NSString stringWithFormat:@"Active profile: %@", X1605VAProfileName(profile)] : @"Active profile: Unavailable";
    _fanMode.enabled = fanAllowed;
    NSNumber *mode = _snapshot[@"FanRequestedMode"];
    [_fanMode selectItemAtIndex:mode ? mode.integerValue + 1 : 0];
    BOOL rpmValid = [_snapshot[@"FanReadingValid"] boolValue];
    NSInteger rpm = [_snapshot[@"FanRPM"] integerValue];
    _rpm.stringValue = !rpmValid ? @"System Fan: Unavailable" : rpm == 0 ? @"System Fan: Stopped · 0 RPM" :
        [NSString stringWithFormat:@"System Fan: %ld RPM", (long)rpm];
    BOOL keyboardAvailable = available && api && [_snapshot[@"KeyboardControlAvailable"] boolValue];
    BOOL keyboardValid = [_snapshot[@"KeyboardReadingValid"] boolValue];
    _keyboard.enabled = keyboardAvailable && keyboardValid;
    if (!_keyboardBusy && _desiredKeyboard < 0 && NSDate.timeIntervalSinceReferenceDate - _lastKeyboardInteraction > 1) {
        if (keyboardValid) {
            _keyboard.integerValue = [_snapshot[@"KeyboardPercent"] integerValue];
            _keyboardValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)_keyboard.integerValue];
        } else _keyboardValue.stringValue = @"Unavailable";
    }
    _keyboardStatus.stringValue = keyboardAvailable ? @"The keyboard key keeps its four steps: Off, Low, Medium, and High." :
        @"The percentage-backlight ACPI interface is unavailable. See the project setup instructions.";
    NSString *driver = _snapshot[@"AsusSMC-Version"] ?: @"Unavailable";
    _version.stringValue = [NSString stringWithFormat:@"X1605VA Settings %s · AsusSMC %@", X1605VA_VERSION, driver];
    if (!_thermalBusy && !_keyboardBusy) {
        if (_lastError.length) _status.stringValue = _lastError;
        else if (_lastReadError.length) _status.stringValue = _lastReadError;
        else if (!available) _status.stringValue = @"AsusSMC is not loaded. Settings remain unavailable.";
        else if (!api) _status.stringValue = @"Install X1605VA AsusSMC " @X1605VA_VERSION @" to enable these settings.";
        else if (![_snapshot[@"FanControlAllowed"] boolValue]) _status.stringValue = @"Fan controls are disabled. See the project setup instructions.";
        else _status.stringValue = @"Administrator approval is required when changing fan settings.";
    }
}
- (void)profileChanged:(XProfileCard *)sender {
    [self authorizedCommand:@"profile" value:[X1605VAProfileName(sender.tag) lowercaseString]];
}
- (void)fanChanged:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem > 0)
        [self authorizedCommand:@"fan" value:sender.indexOfSelectedItem == 1 ? @"auto" : @"full"];
}
static NSString *shellQuote(NSString *value) {
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}
static NSString *appleScriptQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}
- (void)authorizedCommand:(NSString *)command value:(NSString *)value {
    if (_thermalBusy) return;
    _lastError = nil;
    _thermalBusy = YES; [self displayStatus];
    _status.stringValue = @"Waiting for administrator approval and firmware confirmation…";
    NSString *helper = [self.bundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/x1605vactl"];
    NSString *shell = [NSString stringWithFormat:@"%@ %@ %@", shellQuote(helper), shellQuote(command), shellQuote(value)];
    NSString *script = [NSString stringWithFormat:@"do shell script %@ with administrator privileges", appleScriptQuote(shell)];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
        task.arguments = @[@"-e", script];
        NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
        NSError *error = nil;
        BOOL started = [task launchAndReturnError:&error];
        NSData *data = started ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (started) [task waitUntilExit];
        BOOL success = started && task.terminationStatus == 0;
        NSString *detail = started ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : error.localizedDescription;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_thermalBusy = NO;
            self->_lastError = success ? nil : (detail.length ? [detail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"The setting was not changed.");
            [self displayStatus];
            self->_status.stringValue = success ? @"Firmware accepted the setting. Updating status…" :
                (detail.length ? [detail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"The setting was not changed.");
            [self refresh];
        });
    });
}
- (void)keyboardChanged:(NSSlider *)sender {
    _lastError = nil;
    _desiredKeyboard = sender.integerValue; ++_keyboardGeneration;
    _lastKeyboardInteraction = NSDate.timeIntervalSinceReferenceDate;
    _keyboardValue.stringValue = [NSString stringWithFormat:@"%ld%%", (long)_desiredKeyboard];
    [_keyboardTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _keyboardTimer = [NSTimer timerWithTimeInterval:0.25 repeats:NO block:^(NSTimer *timer) {
        (void)timer; [weakSelf commitKeyboard];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_keyboardTimer forMode:NSRunLoopCommonModes];
}
- (void)commitKeyboard {
    if (_keyboardBusy || _desiredKeyboard < 0) return;
    NSInteger percent = _desiredKeyboard; _desiredKeyboard = -1;
    NSUInteger generation = _keyboardGeneration;
    _keyboardBusy = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSError *error = nil;
        BOOL success = X1605VASendCommand(YES, (uint32_t)percent, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_keyboardBusy = NO;
            if (!success) {
                self->_lastError = error.localizedDescription;
                self->_desiredKeyboard = -1;
                self->_status.stringValue = error.localizedDescription;
            } else if (generation == self->_keyboardGeneration) {
                self->_status.stringValue = @"Keyboard backlight updated.";
            }
            if (success && self->_desiredKeyboard >= 0) [self commitKeyboard];
            [self refresh];
        });
    });
}
@end
