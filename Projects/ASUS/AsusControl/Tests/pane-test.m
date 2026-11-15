#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#include <assert.h>
static void snapshot(NSView *view, NSString *path) {
    [view setNeedsDisplay:YES]; [view layoutSubtreeIfNeeded]; [view displayIfNeededIgnoringOpacity];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
}
static void noSliders(NSView *view) {
    assert(![view isKindOfClass:NSSlider.class]);
    for(NSView *child in view.subviews) noSliders(child);
}
static void layout(NSView *view) { for(unsigned i=0;i<5;i++) [view layoutSubtreeIfNeeded]; }
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=3) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error=nil; assert([bundle loadAndReturnError:&error]);
        NSPreferencePane *pane=[[bundle.principalClass alloc] initWithBundle:bundle];
        NSView *view=[pane loadMainView]; assert(view.bounds.size.width==640); noSliders(view);
        NSArray *cards=[pane valueForKey:@"profiles"];
        [pane setValue:@{@"Available":@YES,@"AsusSMC-Version":@"1.4.1"} forKey:@"hardware"];
        [pane setValue:@{@"BatteryManaged":@NO,@"BacklightSleepMode":@0} forKey:@"preferences"];
        [pane performSelector:@selector(displayStatus)];
        for(NSButton *card in cards) assert(!card.enabled);
        assert(![[pane valueForKey:@"batteryCare"] isEnabled]);
        NSDictionary *hardware=@{@"Available":@YES,@"AsusSMC-Version":@"1.1.0",@"ControlAPIVersion":@2,
            @"SettingsRefreshAvailable":@YES,@"DeviceControlAllowed":@YES,@"FanReadingValid":@YES,
            @"FanRPM":@2500,@"FanRequestedMode":@0,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,
            @"BatteryCareAvailable":@YES,@"ChargeLimitRequested":@80,@"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,
            @"TrackpadControlAvailable":@YES,@"TrackpadReadingValid":@YES,@"TrackpadEnabled":@YES,
            @"KeyboardControlAvailable":@YES,@"KeyboardReadingValid":@YES,@"KeyboardPercent":@67};
        [pane setValue:hardware forKey:@"hardware"];
        [pane setValue:@{@"ACPower":@YES,@"PowerSourceKnown":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75,
            @"CPUPercent":@12,@"MemoryPercent":@35,@"MemoryTotal":@17179869184LL,@"MemoryUsed":@6012954214LL,
            @"DiskFree":@150000000000LL,@"DiskTotal":@500000000000LL,@"DiskName":@"Startup disk",@"Uptime":@7200} forKey:@"system"];
        [pane performSelector:@selector(displayStatus)];
        for(NSButton *card in cards) { assert(card.enabled); assert((card.state==NSControlStateValueOn)==(card.tag==0)); }
        assert([[pane valueForKey:@"batteryCare"] isEnabled]);
        assert([[pane valueForKey:@"touchpad"] state]==NSControlStateValueOn);
        assert([[pane valueForKey:@"fnHotkeys"] state]==NSControlStateValueOn);
        NSWindow *window=[[NSWindow alloc] initWithContentRect:view.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView=view;
        NSSegmentedControl *sections=[pane valueForKey:@"sections"];
        NSScrollView *scroll=[pane valueForKey:@"scroll"];
        NSString *directory=[NSString stringWithUTF8String:argv[2]];
        for(NSString *theme in @[@"Light",@"Dark"]) {
            window.appearance=[NSAppearance appearanceNamed:[theme isEqual:@"Dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua]; NSApp.appearance=window.appearance;
            for(NSInteger tab=0;tab<3;tab++) {
                sections.selectedSegment=tab; [pane performSelector:@selector(sectionChanged:) withObject:sections];
                for(NSNumber *width in @[@480,@640,@900]) {
                    [window setContentSize:NSMakeSize(width.doubleValue,640)]; layout(view);
                    assert(fabs(scroll.documentView.bounds.size.width-scroll.contentView.bounds.size.width)<2);
                    assert(scroll.bounds.size.width <= view.bounds.size.width-40);
                    assert(scroll.documentView.bounds.size.height>100);
                    if(width.integerValue==640) snapshot(view,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png",@[@"Power",@"Input",@"Status"][tab],theme]]);
                    if(width.integerValue==480 && [theme isEqual:@"Dark"]) snapshot(view,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-Compact.png",@[@"Power",@"Input",@"Status"][tab]]]);
                }
            }
        }
        // These actions only show/cancel inline confirmation; no firmware request.
        NSSwitch *touchpad=[pane valueForKey:@"touchpad"]; touchpad.state=NSControlStateValueOff;
        [pane performSelector:@selector(trackpadChanged:) withObject:touchpad];
        assert(![[pane valueForKey:@"touchpadConfirm"] isHidden]);
        [pane performSelector:@selector(cancelTrackpad:) withObject:nil];
        assert([[pane valueForKey:@"touchpadConfirm"] isHidden]);
        puts("PASS: pane loading, old-driver gating, state fixtures, no slider, responsive widths, and inline confirmation. No firmware writes.");
    }
}
