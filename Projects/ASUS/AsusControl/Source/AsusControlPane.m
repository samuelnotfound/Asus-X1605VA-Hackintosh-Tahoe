// Copyright (c) 2026 samuelnotfound. MIT License.
#import "AsusControlPane.h"
#import "DeviceClient.h"
#import "Policy.h"
#import "Preferences.h"
#import "SystemStatus.h"
#import <QuartzCore/QuartzCore.h>

static NSTextField *label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *view = [NSTextField labelWithString:text];
    view.font = [NSFont systemFontOfSize:size weight:weight];
    return view;
}

// AppKit controls and dynamic system colors, arranged like MyASUS Device
// Settings. Cards represent firmware profiles, not arbitrary RPM targets.
@interface AsusProfileCard : NSButton
@property(nonatomic, copy) NSString *heading;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic, copy) NSString *symbol;
@end

@implementation AsusProfileCard
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

@interface AsusSettingsBackground : NSView
@end
@implementation AsusSettingsBackground
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill]; NSRectFill(rect);
}
@end


@interface AsusFlowRow : NSStackView
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *verticalWidths;
@end
@implementation AsusFlowRow
- (void)layout {
    BOOL compact = self.bounds.size.width < 530;
    NSUserInterfaceLayoutOrientation orientation = compact ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    if (self.orientation != orientation) {
        [NSLayoutConstraint deactivateConstraints:self.verticalWidths ?: @[]];
        self.orientation = orientation;
        self.alignment = compact ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
        if (compact) {
            NSMutableArray *widths = [NSMutableArray array];
            for (NSView *view in self.arrangedSubviews)
                [widths addObject:[view.widthAnchor constraintEqualToAnchor:self.widthAnchor]];
            self.verticalWidths = widths;
            [NSLayoutConstraint activateConstraints:widths];
        }
        [self invalidateIntrinsicContentSize];
    }
    [super layout];
}
@end
@interface AsusDocumentView : NSView
@end
@implementation AsusDocumentView
- (BOOL)isFlipped { return YES; }
@end

static NSStackView *vertical(void) {
    NSStackView *view = [[NSStackView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.orientation = NSUserInterfaceLayoutOrientationVertical;
    view.alignment = NSLayoutAttributeLeading;
    view.spacing = 12;
    view.detachesHiddenViews = YES;
    return view;
}
static void addWide(NSStackView *stack, NSView *child) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:child];
    [child.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}
static NSTextField *paragraph(NSString *text) {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.font = [NSFont systemFontOfSize:12];
    field.textColor = NSColor.secondaryLabelColor;
    [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}
static NSStackView *row(NSString *title, NSView *control) {
    NSStackView *view = [[NSStackView alloc] init];
    view.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    view.alignment = NSLayoutAttributeCenterY;
    view.spacing = 12;
    NSTextField *caption = [NSTextField wrappingLabelWithString:title];
    caption.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    [caption setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [caption setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view addArrangedSubview:caption]; [view addArrangedSubview:control];
    return view;
}
static NSBox *section(NSString *title, NSString *detail, NSArray<NSView *> *controls) {
    NSBox *box = [[NSBox alloc] init];
    box.boxType = NSBoxCustom; box.borderWidth = 1; box.cornerRadius = 12;
    box.borderColor = NSColor.separatorColor; box.fillColor = NSColor.controlBackgroundColor;
    box.contentViewMargins = NSMakeSize(0, 0);
    NSStackView *content = vertical();
    addWide(content, label(title, 17, NSFontWeightSemibold));
    if (detail.length) addWide(content, paragraph(detail));
    for (NSView *view in controls) addWide(content, view);
    [box.contentView addSubview:content];
    box.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [box.contentView.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
        [box.contentView.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [box.contentView.topAnchor constraintEqualToAnchor:box.topAnchor],
        [box.contentView.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor constant:18],
        [content.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor constant:-18],
        [content.topAnchor constraintEqualToAnchor:box.contentView.topAnchor constant:18],
        [content.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor constant:-18]]];
    return box;
}
static NSPopUpButton *popup(NSArray<NSString *> *titles, id target, SEL action, NSInteger tag) {
    NSPopUpButton *control = [[NSPopUpButton alloc] init];
    [control addItemsWithTitles:titles]; control.target = target; control.action = action; control.tag = tag;
    return control;
}

@interface AsusControlPane () {
    NSSegmentedControl *_sections;
    NSScrollView *_scroll;
    NSArray<NSStackView *> *_pages;
    NSArray<AsusProfileCard *> *_profiles;
    NSSwitch *_batteryCare, *_fullCharge, *_split, *_followLowPower, *_touchpad;
    NSButton *_fnHotkeys, *_fnNormal;
    NSArray<NSButton *> *_idleModes;
    NSPopUpButton *_fanMode, *_acProfile, *_batteryProfile, *_timeout;
    NSTextField *_rpm, *_profileStatus, *_batteryStatus, *_fullChargeStatus, *_fnStatus, *_trackpadStatus, *_status, *_version;
    NSStackView *_touchpadConfirm;
    NSMutableDictionary<NSString *, NSTextField *> *_metricValues;
    NSMutableDictionary<NSString *, NSTextField *> *_metricDetails;
    dispatch_queue_t _worker;
    NSTimer *_pollTimer;
    AsusSystemStatus *_monitor;
    NSDictionary *_hardware, *_system, *_preferences, *_agentState;
    BOOL _active, _refreshing, _busy, _refreshStopped;
    NSString *_lastError, *_note;
}
@end

@implementation AsusControlPane
- (NSSwitch *)newSwitch:(NSInteger)tag action:(SEL)action {
    NSSwitch *control = [[NSSwitch alloc] init];
    control.tag = tag; control.target = self; control.action = action;
    return control;
}
- (NSView *)loadMainView {
    if (self.mainView) return self.mainView;
    _worker = dispatch_queue_create("com.samuelnotfound.AsusControl.controls", DISPATCH_QUEUE_SERIAL);
    _monitor = [[AsusSystemStatus alloc] init];
    _preferences = AsusReadPreferences();
    NSView *root = [[AsusSettingsBackground alloc] initWithFrame:NSMakeRect(0, 0, 640, 640)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    root.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rootResized:) name:NSViewFrameDidChangeNotification object:root];
    NSStackView *layout = vertical(); layout.spacing = 14;
    [root addSubview:layout];
    [NSLayoutConstraint activateConstraints:@[
        [layout.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24],
        [layout.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-24],
        [layout.topAnchor constraintEqualToAnchor:root.topAnchor constant:22],
        [layout.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16]]];
    addWide(layout, label(@"ASUS Control", 24, NSFontWeightBold));
    addWide(layout, paragraph(@"Device Settings"));
    _sections = [NSSegmentedControl segmentedControlWithLabels:@[@"Power & Performance", @"Input Devices", @"System Status"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(sectionChanged:)];
    _sections.selectedSegment = 0;
    addWide(layout, _sections);
    _scroll = [[NSScrollView alloc] init];
    _scroll.drawsBackground = NO; _scroll.hasVerticalScroller = YES; _scroll.hasHorizontalScroller = NO;
    _scroll.autohidesScrollers = YES; _scroll.borderType = NSNoBorder;
    [_scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [_scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    addWide(layout, _scroll);
    AsusDocumentView *document = [[AsusDocumentView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.documentView = document;
    NSStackView *pages = vertical();
    [document addSubview:pages];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:_scroll.contentView.widthAnchor],
        [pages.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [pages.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-4],
        [pages.topAnchor constraintEqualToAnchor:document.topAnchor constant:4],
        [pages.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-18]]];
    NSStackView *power = [self makePowerPage], *input = [self makeInputPage], *status = [self makeStatusPage];
    _pages = @[power, input, status]; input.hidden = YES; status.hidden = YES;
    for (NSView *page in _pages) addWide(pages, page);
    _status = paragraph(@"Reading device settings…"); _status.maximumNumberOfLines = 3; addWide(layout, _status);
    _version = label(@"ASUS Control " @ASUS_CONTROL_VERSION, 11, NSFontWeightRegular);
    _version.textColor = NSColor.tertiaryLabelColor; addWide(layout, _version);
    [self setMainView:root];
    [self setInitialKeyView:_sections]; [self setFirstKeyView:_sections]; [self setLastKeyView:_timeout];
    [self rootResized:nil]; [self displayStatus];
    return root;
}
- (NSStackView *)makePowerPage {
    NSStackView *page = vertical(); page.spacing = 18;
    AsusFlowRow *cards = [[AsusFlowRow alloc] init];
    cards.orientation = NSUserInterfaceLayoutOrientationHorizontal; cards.alignment = NSLayoutAttributeCenterY;
    cards.distribution = NSStackViewDistributionFillEqually; cards.spacing = 12;
    NSMutableArray *profiles = [NSMutableArray array];
    NSArray *names = @[@"Performance", @"Standard", @"Whisper"];
    NSArray *details = @[@"Prioritize cooling for demanding tasks.", @"Balance performance and fan noise for everyday use.", @"Favor quieter operation for lighter tasks."];
    NSArray *icons = @[@"speedometer", @"fan", @"leaf"];
    NSInteger tags[] = {2, 0, 1};
    for (NSInteger i = 0; i < 3; ++i) {
        AsusProfileCard *card = [[AsusProfileCard alloc] initWithFrame:NSMakeRect(0, 0, 180, 154)];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.heading = names[i]; card.detail = details[i]; card.symbol = icons[i]; card.tag = tags[i];
        card.target = self; card.action = @selector(profileChanged:);
        card.accessibilityLabel = [names[i] stringByAppendingString:@" fan profile"];
        [card.heightAnchor constraintEqualToConstant:154].active = YES;
        [cards addArrangedSubview:card]; [profiles addObject:card];
    }
    _profiles = profiles;
    _profileStatus = paragraph(@"Active profile: Unavailable");
    _rpm = label(@"System Fan: Unavailable", 13, NSFontWeightMedium);
    _fanMode = popup(@[@"Fan control…", @"Automatic", @"Full Speed"], self, @selector(fanChanged:), 0);
    NSStackView *fanRow = row(@"Fan control", _fanMode);
    _split = [self newSwitch:3 action:@selector(preferenceChanged:)];
    _acProfile = popup(@[@"Standard", @"Whisper", @"Performance", @"Full Speed"], self, @selector(preferenceChanged:), 4);
    _batteryProfile = popup(@[@"Standard", @"Whisper"], self, @selector(preferenceChanged:), 5);
    _followLowPower = [self newSwitch:6 action:@selector(preferenceChanged:)];
    NSBox *fan = section(@"Fan Profile", @"Choose a balance of cooling, noise, and performance.",
        @[cards, _profileStatus, _rpm, fanRow,
          row(@"Separate AC and battery profiles", _split), row(@"On AC power", _acProfile), row(@"On battery", _batteryProfile),
          row(@"Power Mode Synchronization", _followLowPower),
          paragraph(@"Synchronization uses Whisper while macOS Low Power Mode is enabled. Performance requires AC power and more than 40% battery on the current hardware profile.")]);
    addWide(page, fan);
    _batteryCare = [self newSwitch:1 action:@selector(preferenceChanged:)];
    _fullCharge = [self newSwitch:2 action:@selector(preferenceChanged:)];
    _batteryStatus = paragraph(@"Charging limit: Unavailable");
    _fullChargeStatus = paragraph(@"Temporary full charging is off.");
    addWide(page, section(@"Battery Care Mode", @"Limit charging to 80% when keeping the laptop plugged in.",
        @[row(@"Battery Care Mode", _batteryCare), _batteryStatus,
          row(@"Instant Full-Charge Mode", _fullCharge), _fullChargeStatus,
          paragraph(@"Full-Charge Mode allows 100% for 24 hours, then requests the 80% limit again. Timed settings continue in the user-session background agent.")]));
    return page;
}
- (NSStackView *)makeInputPage {
    NSStackView *page = vertical(); page.spacing = 18;
    _touchpad = [self newSwitch:0 action:@selector(trackpadChanged:)];
    _trackpadStatus = paragraph(@"Touchpad state: Unavailable");
    _touchpadConfirm = vertical(); _touchpadConfirm.hidden = YES;
    addWide(_touchpadConfirm, paragraph(@"Disable the touchpad? Press Fn + F6 to turn it back on."));
    NSStackView *buttons = [[NSStackView alloc] init]; buttons.spacing = 10;
    [buttons addArrangedSubview:[NSButton buttonWithTitle:@"Disable" target:self action:@selector(confirmTrackpad:)]];
    [buttons addArrangedSubview:[NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelTrackpad:)]];
    [_touchpadConfirm addArrangedSubview:buttons];
    addWide(page, section(@"Touchpad", @"Lock or unlock the built-in touchpad input.",
        @[row(@"Touchpad enabled", _touchpad), _trackpadStatus, _touchpadConfirm]));
    _fnHotkeys = [NSButton radioButtonWithTitle:@"Use hotkeys" target:self action:@selector(preferenceChanged:)]; _fnHotkeys.tag = 7;
    _fnNormal = [NSButton radioButtonWithTitle:@"Use F1–F12" target:self action:@selector(preferenceChanged:)]; _fnNormal.tag = 8;
    _fnStatus = paragraph(@"Current function-key mode: Unavailable");
    addWide(page, section(@"Function Key", @"Choose what pressing the top-row keys does without holding Fn.",
        @[_fnHotkeys, paragraph(@"Use the symbols printed on the keys. Hold Fn for F1–F12."),
          _fnNormal, paragraph(@"Send F1–F12 to macOS and apps. Hold Fn for the printed hotkeys."), _fnStatus]));
    NSMutableArray *modes = [NSMutableArray array];
    NSArray *titles = @[@"Do nothing", @"On battery and AC power", @"On battery power only"];
    for (NSInteger i = 0; i < 3; ++i) {
        NSButton *button = [NSButton radioButtonWithTitle:titles[i] target:self action:@selector(preferenceChanged:)];
        button.tag = 20 + i; [modes addObject:button];
    }
    _idleModes = modes;
    _timeout = popup(@[@"30 seconds", @"1 minute", @"3 minutes", @"5 minutes", @"10 minutes", @"15 minutes"], self, @selector(preferenceChanged:), 9);
    NSMutableArray *controls = [modes mutableCopy];
    [controls addObject:row(@"Turn off after", _timeout)];
    [controls addObject:paragraph(@"The agent remembers the current keyboard-light level, turns it off after inactivity, and restores it when input resumes. Physical backlight cycling keeps its existing four steps.")];
    addWide(page, section(@"Keyboard Backlight Sleep Mode", @"Automatically turn off the keyboard backlight after a period of inactivity.", controls));
    return page;
}
- (NSBox *)metric:(NSString *)key title:(NSString *)title button:(NSString *)button action:(SEL)action {
    NSTextField *value = label(@"Unavailable", 28, NSFontWeightSemibold);
    NSTextField *detail = paragraph(@"");
    _metricValues[key] = value; _metricDetails[key] = detail;
    NSMutableArray *views = [NSMutableArray arrayWithObjects:value, detail, nil];
    if (button) [views addObject:[NSButton buttonWithTitle:button target:self action:action]];
    NSBox *card = section(title, nil, views);
    [card.heightAnchor constraintGreaterThanOrEqualToConstant:158].active = YES;
    return card;
}
- (NSStackView *)makeStatusPage {
    NSStackView *page = vertical(); page.spacing = 16;
    _metricValues = [NSMutableDictionary dictionary]; _metricDetails = [NSMutableDictionary dictionary];
    NSArray *pairs = @[
        @[[self metric:@"CPU" title:@"CPU Load" button:@"Activity Monitor" action:@selector(openActivityMonitor:)],
          [self metric:@"Memory" title:@"Memory" button:nil action:NULL]],
        @[[self metric:@"Battery" title:@"Battery" button:@"Battery Care" action:@selector(showPower:)],
          [self metric:@"Disk" title:@"Storage" button:@"Storage Settings" action:@selector(openStorage:)]],
        @[[self metric:@"Fan" title:@"Fan" button:@"Fan Profile" action:@selector(showPower:)],
          [self metric:@"Uptime" title:@"Uptime" button:nil action:NULL]]];
    for (NSArray *pair in pairs) {
        AsusFlowRow *line = [[AsusFlowRow alloc] init];
        line.orientation = NSUserInterfaceLayoutOrientationHorizontal; line.alignment = NSLayoutAttributeCenterY;
        line.distribution = NSStackViewDistributionFillEqually; line.spacing = 12;
        for (NSView *view in pair) [line addArrangedSubview:view];
        addWide(page, line);
    }
    return page;
}
- (void)rootResized:(NSNotification *)notification {
    (void)notification;
    BOOL compact = self.mainView.bounds.size.width < 630;
    NSArray *titles = compact ? @[@"Power", @"Input", @"Status"] : @[@"Power & Performance", @"Input Devices", @"System Status"];
    for (NSInteger i = 0; i < 3; ++i) [_sections setLabel:titles[i] forSegment:i];
}
- (void)didSelect {
    _active = YES; _refreshStopped = NO; _lastError = nil;
    [self refresh];
    __weak typeof(self) weakSelf = self;
    _pollTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { (void)timer; [weakSelf refresh]; }];
    [[NSRunLoop mainRunLoop] addTimer:_pollTimer forMode:NSRunLoopCommonModes];
}
- (void)willUnselect { _active = NO; [_pollTimer invalidate]; _pollTimer = nil; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_pollTimer invalidate]; }
- (void)sectionChanged:(id)sender {
    (void)sender;
    for (NSInteger i = 0; i < 3; ++i) _pages[i].hidden = i != _sections.selectedSegment;
    [_scroll.contentView scrollToPoint:NSZeroPoint]; [_scroll reflectScrolledClipView:_scroll.contentView];
    [self.mainView layoutSubtreeIfNeeded];
}
- (void)refresh {
    if (!_active || _refreshing || _busy) return;
    _refreshing = YES; BOOL query = !_refreshStopped;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSDictionary *hardware = AsusControlReadStatus();
        NSError *error = nil;
        if (query && [hardware[@"SettingsRefreshAvailable"] boolValue]) {
            AsusControlRefreshSettings(&error); hardware = AsusControlReadStatus();
        }
        NSDictionary *system = [self->_monitor sample], *preferences = AsusReadPreferences(), *agent = AsusReadAgentState();
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_refreshing = NO;
            if (!self->_active) return;
            self->_hardware = hardware; self->_system = system; self->_preferences = preferences; self->_agentState = agent;
            if (error.code == 6) { self->_refreshStopped = YES; self->_lastError = error.localizedDescription; }
            [self displayStatus];
        });
    });
}
- (void)displayStatus {
    NSInteger api = [_hardware[@"ControlAPIVersion"] integerValue];
    if (!api) api = [_hardware[@"X1605VA-ControlAPIVersion"] integerValue];
    BOOL legacy = api >= 1 && api <= 2 && [_hardware[@"SettingsRefreshAvailable"] boolValue];
    BOOL devices = legacy && [_hardware[@"DeviceControlAllowed"] boolValue] && !_busy;
    BOOL fans = legacy && ([_hardware[@"FanControlAllowed"] boolValue] || [_hardware[@"DeviceControlAllowed"] boolValue]) && !_busy;
    NSMutableDictionary *rules = [_system mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in @[@"PerformanceOnBattery", @"PerformanceMinimumBattery", @"FullSpeedOnBattery"])
        if (_hardware[key]) rules[key] = _hardware[key];
    BOOL performance = [rules[@"PowerSourceKnown"] boolValue] &&
        AsusEffectiveProfile(@{@"ACProfile":@2, @"BatteryProfile":@2}, rules) == 2;
    BOOL syncing = [_preferences[@"FollowLowPower"] boolValue] && [_system[@"LowPowerMode"] boolValue];
    for (AsusProfileCard *card in _profiles) {
        card.enabled = fans && !syncing && (card.tag != 2 || performance);
        card.state = [_hardware[@"ThermalProfileValid"] boolValue] && card.tag == [_hardware[@"ThermalProfile"] integerValue] ? NSControlStateValueOn : NSControlStateValueOff;
        card.accessibilityValue = card.state == NSControlStateValueOn ? @"Selected" : @"Not selected";
        [card setNeedsDisplay:YES];
    }
    _profileStatus.stringValue = syncing ? @"Whisper is selected while macOS Low Power Mode is enabled." :
        [_hardware[@"ThermalProfileValid"] boolValue] ? [@"Active profile: " stringByAppendingString:AsusControlProfileName([_hardware[@"ThermalProfile"] integerValue])] : @"Active profile: Unavailable";
    _rpm.stringValue = [_hardware[@"FanReadingValid"] boolValue] ?
        [NSString stringWithFormat:@"System Fan: %ld RPM", (long)[_hardware[@"FanRPM"] integerValue]] : @"System Fan: Unavailable";
    _fanMode.enabled = fans && !syncing;
    [_fanMode selectItemAtIndex:_hardware[@"FanRequestedMode"] ? [_hardware[@"FanRequestedMode"] integerValue] + 1 : 0];
    [_fanMode itemAtIndex:2].enabled = [_system[@"ACPower"] boolValue] || [_hardware[@"FullSpeedOnBattery"] boolValue];
    _split.enabled = devices; _split.state = [_preferences[@"SplitProfiles"] boolValue];
    _acProfile.enabled = devices && _split.state == NSControlStateValueOn;
    _batteryProfile.enabled = _acProfile.enabled;
    [_acProfile selectItemAtIndex:MAX(0, MIN(3, [_preferences[@"ACProfile"] integerValue]))];
    [_batteryProfile selectItemAtIndex:MAX(0, MIN(1, [_preferences[@"BatteryProfile"] integerValue]))];
    _followLowPower.enabled = devices; _followLowPower.state = [_preferences[@"FollowLowPower"] boolValue];
    BOOL battery = devices && [_hardware[@"BatteryCareAvailable"] boolValue];
    _batteryCare.enabled = battery;
    BOOL care = [_preferences[@"BatteryManaged"] boolValue] ? [_preferences[@"BatteryCare"] boolValue] :
        [_hardware[@"ChargeLimitRequested"] integerValue] == 80 || [_hardware[@"BatteryConservativeMode"] boolValue];
    _batteryCare.state = care;
    NSTimeInterval until = [_preferences[@"FullChargeUntil"] doubleValue];
    BOOL temporary = care && until > NSDate.date.timeIntervalSince1970;
    _fullCharge.enabled = battery && care; _fullCharge.state = temporary;
    _batteryStatus.stringValue = _hardware[@"ChargeLimitRequested"] ? [NSString stringWithFormat:@"Driver-requested charging limit: %@%%", _hardware[@"ChargeLimitRequested"]] :
        _hardware[@"BatteryConservativeMode"] ? [NSString stringWithFormat:@"Driver-requested charging limit: %@%%", [_hardware[@"BatteryConservativeMode"] boolValue] ? @80 : @100] : @"Charging limit: Unavailable";
    _fullChargeStatus.stringValue = temporary ? [@"Battery Care resumes " stringByAppendingString:[NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:until] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]] : @"Temporary full charging is off.";
    _touchpad.enabled = devices && [_hardware[@"TrackpadControlAvailable"] boolValue];
    _touchpad.state = [_hardware[@"TrackpadEnabled"] boolValue];
    _trackpadStatus.stringValue = [_hardware[@"TrackpadReadingValid"] boolValue] ?
        ([_hardware[@"TrackpadEnabled"] boolValue] ? @"Enabled" : @"Disabled · press Fn + F6 to enable") : @"Touchpad state: Unavailable";
    BOOL fn = devices && [_hardware[@"FnLockAvailable"] boolValue];
    _fnHotkeys.enabled = fn; _fnNormal.enabled = fn;
    BOOL hotkeys = [_preferences[@"FnManaged"] boolValue] ? [_preferences[@"FnHotkeys"] boolValue] : [_hardware[@"FnLockHotkeys"] boolValue];
    _fnHotkeys.state = hotkeys; _fnNormal.state = !hotkeys;
    _fnStatus.stringValue = [_hardware[@"FnLockAvailable"] boolValue] ?
        ([_hardware[@"FnLockHotkeys"] boolValue] ? @"Current mode: Hotkeys" : @"Current mode: F1–F12") : @"Current function-key mode: Unavailable";
    NSInteger idle = [_preferences[@"BacklightSleepMode"] integerValue];
    BOOL keyboard = devices && [_hardware[@"KeyboardControlAvailable"] boolValue];
    for (NSButton *button in _idleModes) { button.enabled = keyboard; button.state = button.tag - 20 == idle; }
    _timeout.enabled = keyboard && idle != 0;
    NSArray *times = @[@30, @60, @180, @300, @600, @900];
    NSUInteger index = [times indexOfObject:_preferences[@"BacklightTimeout"] ?: @60];
    [_timeout selectItemAtIndex:index == NSNotFound ? 1 : (NSInteger)index];
    [self updateMetrics];
    _version.stringValue = [NSString stringWithFormat:@"ASUS Control %s · AsusSMC %@", ASUS_CONTROL_VERSION, _hardware[@"AsusSMC-Version"] ?: @"Unavailable"];
    if (_busy) _status.stringValue = @"Applying the requested setting…";
    else if (_lastError.length) _status.stringValue = _lastError;
    else if (AsusNeedsAgent(_preferences) && [_agentState[@"Error"] length]) _status.stringValue = _agentState[@"Error"];
    else if (_note.length) _status.stringValue = _note;
    else if (!legacy && _sections.selectedSegment != 2) _status.stringValue = @"Hardware controls need the matching AsusSMC driver. System status works independently.";
    else if (!devices && _sections.selectedSegment != 2) _status.stringValue = @"Additional device controls require the matching hardware profile and settings opt-in. See Setup.";
    else _status.stringValue = AsusNeedsAgent(_preferences) ? @"Automatic settings continue in the background at login." : @"Automatic settings start only when you enable a feature that needs them.";
}
- (void)updateMetrics {
    _metricValues[@"CPU"].stringValue = _system[@"CPUPercent"] ? [NSString stringWithFormat:@"%.0f%%", [_system[@"CPUPercent"] doubleValue]] : @"Reading…";
    _metricDetails[@"CPU"].stringValue = @"Current processor utilization";
    _metricValues[@"Memory"].stringValue = _system[@"MemoryPercent"] ? [NSString stringWithFormat:@"%.0f%%", [_system[@"MemoryPercent"] doubleValue]] : @"Unavailable";
    _metricDetails[@"Memory"].stringValue = _system[@"MemoryTotal"] ? [NSString stringWithFormat:@"%@ of %@ in use",
        [NSByteCountFormatter stringFromByteCount:[_system[@"MemoryUsed"] longLongValue] countStyle:NSByteCountFormatterCountStyleMemory],
        [NSByteCountFormatter stringFromByteCount:[_system[@"MemoryTotal"] longLongValue] countStyle:NSByteCountFormatterCountStyleMemory]] : @"";
    _metricValues[@"Battery"].stringValue = [_system[@"BatteryKnown"] boolValue] ? [NSString stringWithFormat:@"%.0f%%", [_system[@"BatteryPercent"] doubleValue]] : @"Unavailable";
    _metricDetails[@"Battery"].stringValue = [_system[@"PowerSourceKnown"] boolValue] ? ([_system[@"ACPower"] boolValue] ? @"AC power" : @"On battery") : @"Power source unavailable";
    if ([_system[@"BatteryHealth"] length]) _metricDetails[@"Battery"].stringValue = [_metricDetails[@"Battery"].stringValue stringByAppendingFormat:@" · %@", _system[@"BatteryHealth"]];
    _metricValues[@"Disk"].stringValue = _system[@"DiskFree"] ? [NSByteCountFormatter stringFromByteCount:[_system[@"DiskFree"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile] : @"Unavailable";
    _metricDetails[@"Disk"].stringValue = _system[@"DiskTotal"] ? [NSString stringWithFormat:@"Available of %@ · %@", [NSByteCountFormatter stringFromByteCount:[_system[@"DiskTotal"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile], _system[@"DiskName"] ?: @"Startup disk"] : @"";
    _metricValues[@"Fan"].stringValue = [_hardware[@"FanReadingValid"] boolValue] ? [NSString stringWithFormat:@"%@ RPM", _hardware[@"FanRPM"]] : @"Unavailable";
    _metricDetails[@"Fan"].stringValue = [_hardware[@"ThermalProfileValid"] boolValue] ? AsusControlProfileName([_hardware[@"ThermalProfile"] integerValue]) : @"Profile unavailable";
    NSInteger seconds = [_system[@"Uptime"] integerValue];
    _metricValues[@"Uptime"].stringValue = [NSString stringWithFormat:@"%ldh %ldm", (long)(seconds / 3600), (long)((seconds / 60) % 60)];
    _metricDetails[@"Uptime"].stringValue = @"Time since this macOS boot";
}
- (void)savePreferences:(NSDictionary *)preferences {
    if (_busy) return;
    _busy = YES; _lastError = nil; _note = nil; [self displayStatus];
    NSDictionary *before = _preferences;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSError *error = nil;
        BOOL success = AsusConfigureAgent(self.bundle, preferences, &error);
        if (!success) AsusWritePreferences(before, NULL);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_busy = NO;
            if (success) { self->_preferences = preferences; self->_note = @"Saved. Waiting for the configured setting to be applied."; }
            else self->_lastError = error.localizedDescription ?: @"The automatic settings service could not start.";
            [self displayStatus]; [self refresh];
        });
    });
}
- (void)preferenceChanged:(NSControl *)sender {
    if (_busy) return;
    NSMutableDictionary *preferences = [_preferences mutableCopy];
    switch (sender.tag) {
        case 1: preferences[@"BatteryManaged"] = @YES; preferences[@"BatteryCare"] = @(_batteryCare.state == NSControlStateValueOn); preferences[@"FullChargeUntil"] = @0; break;
        case 2: preferences[@"BatteryManaged"] = @YES; preferences[@"BatteryCare"] = @YES; preferences[@"FullChargeUntil"] = @(_fullCharge.state == NSControlStateValueOn ? NSDate.date.timeIntervalSince1970 + 86400 : 0); break;
        case 3: preferences[@"SplitProfiles"] = @(_split.state == NSControlStateValueOn); break;
        case 4: preferences[@"ACProfile"] = @(_acProfile.indexOfSelectedItem); break;
        case 5: preferences[@"BatteryProfile"] = @(_batteryProfile.indexOfSelectedItem); break;
        case 6: preferences[@"FollowLowPower"] = @(_followLowPower.state == NSControlStateValueOn); break;
        case 7: preferences[@"FnManaged"] = @YES; preferences[@"FnHotkeys"] = @YES; break;
        case 8: preferences[@"FnManaged"] = @YES; preferences[@"FnHotkeys"] = @NO; break;
        case 9: preferences[@"BacklightTimeout"] = @[@30, @60, @180, @300, @600, @900][_timeout.indexOfSelectedItem]; break;
        default:
            if (sender.tag >= 20 && sender.tag <= 22) preferences[@"BacklightSleepMode"] = @(sender.tag - 20);
            else return;
    }
    [self savePreferences:preferences];
}
- (void)profileChanged:(AsusProfileCard *)sender {
    if ([_preferences[@"SplitProfiles"] boolValue] || [_preferences[@"FollowLowPower"] boolValue]) {
        NSMutableDictionary *preferences = [_preferences mutableCopy];
        preferences[[_system[@"ACPower"] boolValue] ? @"ACProfile" : @"BatteryProfile"] = @(sender.tag);
        [self savePreferences:preferences];
    } else if ([_hardware[@"DeviceControlAllowed"] boolValue]) [self deviceCommand:(uint32_t)(7 + sender.tag)];
    else [self authorizedCommand:@"profile" value:[AsusControlProfileName(sender.tag) lowercaseString]];
}
- (void)fanChanged:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem < 1) return;
    if ([_hardware[@"DeviceControlAllowed"] boolValue]) [self deviceCommand:sender.indexOfSelectedItem == 1 ? 11 : 10];
    else [self authorizedCommand:@"fan" value:sender.indexOfSelectedItem == 1 ? @"auto" : @"full"];
}
- (void)trackpadChanged:(NSSwitch *)sender {
    if (sender.state == NSControlStateValueOff) {
        sender.state = NSControlStateValueOn; _touchpadConfirm.hidden = NO;
    } else [self deviceCommand:5];
}
- (void)confirmTrackpad:(id)sender { (void)sender; _touchpadConfirm.hidden = YES; [self deviceCommand:6]; }
- (void)cancelTrackpad:(id)sender { (void)sender; _touchpadConfirm.hidden = YES; [self displayStatus]; }
- (void)deviceCommand:(uint32_t)command {
    if (_busy) return;
    _busy = YES; _lastError = nil; _note = nil; [self displayStatus];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSError *error = nil;
        BOOL success = AsusControlSendDeviceCommand(command, &error);
        if (success) AsusControlRefreshSettings(NULL);
        NSDictionary *hardware = AsusControlReadStatus();
        if (success && (command == 5 || command == 6)) {
            // ACPI Notify is asynchronous; confirm from the touchpad driver.
            for (unsigned i = 0; i < 3 && (![hardware[@"TrackpadReadingValid"] boolValue] || [hardware[@"TrackpadEnabled"] boolValue] != (command == 5)); ++i) {
                AsusControlRefreshSettings(NULL); hardware = AsusControlReadStatus();
            }
            if (![hardware[@"TrackpadReadingValid"] boolValue] || [hardware[@"TrackpadEnabled"] boolValue] != (command == 5)) {
                success = NO;
                error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl" code:7 userInfo:@{NSLocalizedDescriptionKey:@"The touchpad change was not confirmed. Fn + F6 can turn it back on."}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_busy = NO; self->_hardware = hardware;
            self->_lastError = success ? nil : error.localizedDescription;
            self->_note = success ? @"Firmware accepted the setting." : nil;
            [self displayStatus]; [self refresh];
        });
    });
}
static NSString *shellQuote(NSString *value) {
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}
static NSString *appleScriptQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [NSString stringWithFormat:@"\"%@\"", [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
}
- (void)authorizedCommand:(NSString *)command value:(NSString *)value {
    if (_busy) return;
    _busy = YES; _lastError = nil; _note = nil; [self displayStatus];
    NSString *helper = [self.bundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/asusctl"];
    NSString *shell = [NSString stringWithFormat:@"%@ %@ %@", shellQuote(helper), shellQuote(command), shellQuote(value)];
    NSString *script = [NSString stringWithFormat:@"do shell script %@ with administrator privileges", appleScriptQuote(shell)];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSTask *task = [[NSTask alloc] init]; task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"]; task.arguments = @[@"-e", script];
        NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
        NSError *error = nil; BOOL started = [task launchAndReturnError:&error];
        NSData *data = started ? [pipe.fileHandleForReading readDataToEndOfFile] : nil;
        if (started) [task waitUntilExit];
        BOOL success = started && task.terminationStatus == 0;
        NSString *detail = started ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : error.localizedDescription;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf; if (!self) return;
            self->_busy = NO; self->_lastError = success ? nil : detail;
            self->_note = success ? @"Firmware accepted the setting." : nil;
            [self displayStatus]; [self refresh];
        });
    });
}
- (void)openActivityMonitor:(id)sender {
    (void)sender;
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.ActivityMonitor"];
    if (url) [NSWorkspace.sharedWorkspace openURL:url];
}
- (void)openStorage:(id)sender { (void)sender; [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.settings.Storage"]]; }
- (void)showPower:(id)sender { (void)sender; _sections.selectedSegment = 0; [self sectionChanged:nil]; [self displayStatus]; }
@end
