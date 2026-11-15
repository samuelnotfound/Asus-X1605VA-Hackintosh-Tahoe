#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#include <assert.h>
static void settle(NSView *view) {
    for (unsigned i=0;i<5;i++) {
        [view layoutSubtreeIfNeeded];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
    }
}
static void snapshot(NSView *view, NSString *path) {
    settle(view); [view setNeedsDisplay:YES]; [view displayIfNeededIgnoringOpacity];
    NSBitmapImageRep *image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
}
static unsigned scrollViews(NSView *view) {
    unsigned count=[view isKindOfClass:NSScrollView.class];
    if ([view isKindOfClass:NSScrollView.class]) {
        NSScrollView *scroll=(NSScrollView *)view;
        assert(!scroll.hasHorizontalScroller);
        assert(scroll.frame.size.height>100);
    }
    for (NSView *child in view.subviews) count+=scrollViews(child);
    return count;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc!=3) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error=nil; assert([bundle loadAndReturnError:&error]);
        NSPreferencePane *pane=[[bundle.principalClass alloc] initWithBundle:bundle];
        NSView *view=[pane loadMainView]; assert(view.bounds.size.width==660);
        NSDictionary *hardware=@{@"Available":@YES,@"AsusSMC-Version":@"1.1.0",@"ControlAPIVersion":@2,
            @"SettingsRefreshAvailable":@YES,@"DeviceControlAllowed":@YES,@"FanReadingValid":@YES,
            @"FanRPM":@2600,@"FanRequestedMode":@0,@"ThermalProfileValid":@YES,@"ThermalProfile":@0,
            @"BatteryCareAvailable":@YES,@"ChargeLimitRequested":@80,@"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,
            @"TrackpadControlAvailable":@YES,@"TrackpadReadingValid":@YES,@"TrackpadEnabled":@YES,
            @"KeyboardControlAvailable":@YES,@"KeyboardReadingValid":@YES,@"KeyboardPercent":@67};
        [pane setValue:hardware forKey:@"hardware"];
        [pane setValue:@{@"ACPower":@YES,@"PowerSourceKnown":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75,
            @"CPUPercent":@12,@"MemoryTotal":@17179869184LL,@"MemoryUsed":@6012954214LL,
            @"DiskFree":@150000000000LL,@"DiskTotal":@500000000000LL,@"Uptime":@7200} forKey:@"system"];
        // Never call didSelect or configuration actions: no agent registration,
        // firmware writes, application launches or focus changes in this test.
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,660,900) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        NSView *container=[[NSView alloc] initWithFrame:window.contentView.bounds]; window.contentView=container;
        view.frame=NSMakeRect(0,0,660,640); [container addSubview:view]; settle(view);
        assert(fabs(view.frame.size.height-container.bounds.size.height)<2);
        id ui=[pane valueForKey:@"ui"];
        NSString *directory=[NSString stringWithUTF8String:argv[2]];
        for(NSString *theme in @[@"Light",@"Dark"]) {
            window.appearance=[NSAppearance appearanceNamed:[theme isEqual:@"Dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua]; NSApp.appearance=window.appearance;
            for(NSInteger tab=0;tab<3;tab++) {
                // selectTab takes NSInteger rather than an Objective-C object.
                NSInvocation *invoke=[NSInvocation invocationWithMethodSignature:[ui methodSignatureForSelector:@selector(selectTab:)]];
                invoke.target=ui; invoke.selector=@selector(selectTab:); [invoke setArgument:&tab atIndex:2]; [invoke invoke];
                for(NSNumber *width in @[@480,@660,@900]) {
                    [window setContentSize:NSMakeSize(width.doubleValue,900)];
                    [pane setValue:@{@"FanManaged":@YES,@"ManualProfile":@0,@"BatteryManaged":@YES,@"BatteryCare":@YES,
                        @"SplitProfiles":@NO,@"FollowLowPower":@NO,@"Revision":@"test",@"BacklightSleepMode":@1,@"BacklightTimeout":@60} forKey:@"preferences"];
                    [pane setValue:@{@"Revision":@"test",@"Result":@"applied"} forKey:@"agentState"];
                    [pane performSelector:@selector(displayStatus)]; settle(view);
                    assert(fabs(view.bounds.size.width-width.doubleValue)<2);
                    assert(fabs(view.bounds.size.height-900)<2);
                    assert(scrollViews(view)==1);
                    if(width.integerValue==660 || (width.integerValue==480 && [theme isEqual:@"Dark"]))
                        snapshot(view,[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-%@.png",@[@"Power",@"Input",@"Status"][tab],width,theme]]);
                }
            }
        }
        NSInteger tab=0;
        NSInvocation *invoke=[NSInvocation invocationWithMethodSignature:[ui methodSignatureForSelector:@selector(selectTab:)]];
        invoke.target=ui; invoke.selector=@selector(selectTab:); [invoke setArgument:&tab atIndex:2]; [invoke invoke];
        [window setContentSize:NSMakeSize(480,640)];
        [pane setValue:@{@"FanManaged":@YES,@"ManualProfile":@0,@"ACProfile":@2,@"BatteryProfile":@1,
            @"SplitProfiles":@YES,@"FollowLowPower":@YES,@"Revision":@"new"} forKey:@"preferences"];
        [pane setValue:@{@"Revision":@"old",@"Result":@"applied"} forKey:@"agentState"];
        [pane performSelector:@selector(displayStatus)];
        snapshot(view,[directory stringByAppendingPathComponent:@"Power-Automatic-Compact.png"]);
        [pane setValue:@{@"Revision":@"new",@"Result":@"failed",@"Error":@"Whisper was requested, but the resulting profile was not confirmed."} forKey:@"agentState"];
        [pane performSelector:@selector(displayStatus)];
        snapshot(view,[directory stringByAppendingPathComponent:@"Policy-Error-Compact.png"]);
        [pane setValue:@{@"Available":@YES,@"AsusSMC-Version":@"1.4.1"} forKey:@"hardware"];
        [pane performSelector:@selector(displayStatus)];
        snapshot(view,[directory stringByAppendingPathComponent:@"Unavailable.png"]);
        puts("PASS: native grouped Form, one scroll container, host attachment/resizing, three tabs and capability fixtures. No hardware writes.");
    }
}
