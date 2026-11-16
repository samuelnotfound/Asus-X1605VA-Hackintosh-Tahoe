#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#include <assert.h>
static void settle(NSView *view) { for(unsigned i=0;i<6;i++){[view layoutSubtreeIfNeeded];[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];} }
static void snapshot(NSView *view,NSString *path) {
    settle(view);[view setNeedsDisplay:YES];[view displayIfNeededIgnoringOpacity];
    NSBitmapImageRep *image=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES]);
}
static unsigned scrollViews(NSView *view) {
    unsigned count=[view isKindOfClass:NSScrollView.class];
    if(count)assert(![(NSScrollView *)view hasHorizontalScroller]);
    assert(![view isKindOfClass:NSSegmentedControl.class]);
    for(NSView *child in view.subviews)count+=scrollViews(child);
    return count;
}
static NSArray<NSProgressIndicator *> *spinners(NSView *view) {
    NSMutableArray *result=[NSMutableArray array];
    if([view isKindOfClass:NSProgressIndicator.class]) [result addObject:view];
    for(NSView *child in view.subviews) [result addObjectsFromArray:spinners(child)];
    return result;
}
int main(int argc,const char **argv) {
 @autoreleasepool {
    if(argc!=3)return 2;
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];NSError *error=nil;
    assert([bundle loadAndReturnError:&error]);
    NSPreferencePane *pane=[[bundle.principalClass alloc]initWithBundle:bundle];NSView *view=[pane loadMainView];
    [pane setValue:@{@"AsusSMC-Version":@"1.1.0",@"DeviceControlAllowed":@YES,@"FanReadingValid":@YES,@"FanRPM":@2600,
        @"ThermalProfileValid":@YES,@"ThermalProfile":@0,@"FanRequestedMode":@0,@"BatteryCareAvailable":@YES,
        @"ChargeLimitRequested":@80,@"FnLockAvailable":@YES,@"FnLockHotkeys":@YES,@"KeyboardControlAvailable":@YES,
        @"TrackpadControlAvailable":@YES,@"TrackpadEnabled":@YES} forKey:@"hardware"];
    [pane setValue:@{@"ACPower":@YES,@"PowerSourceKnown":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75} forKey:@"system"];
    [pane setValue:@{@"FanManaged":@YES,@"ManualProfile":@0,@"BatteryManaged":@YES,@"BatteryCare":@YES,@"BacklightSleepMode":@1,
        @"BacklightTimeout":@60,@"Revision":@"fixture"} forKey:@"preferences"];
    [pane setValue:@{@"Revision":@"fixture",@"Result":@"applied"} forKey:@"agentState"];
    [pane performSelector:@selector(displayStatus)];
    // Offscreen only. Never call lifecycle/setting actions or start an agent.
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,660,1000) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSView *container=[[NSView alloc]initWithFrame:window.contentView.bounds];window.contentView=container;
    container.wantsLayer=YES;
    [container addSubview:view];settle(view);assert(fabs(view.bounds.size.height-1000)<2);
    for(NSString *theme in @[@"Light",@"Dark"]) {
        window.appearance=[NSAppearance appearanceNamed:[theme isEqual:@"Dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua];NSApp.appearance=window.appearance;
        container.layer.backgroundColor=([theme isEqual:@"Dark"] ? [NSColor colorWithCalibratedRed:0.13 green:0.16 blue:0.14 alpha:1] : [NSColor colorWithCalibratedRed:0.94 green:0.96 blue:0.95 alpha:1]).CGColor;
        for(NSNumber *width in @[@480,@660,@900]) {
            [window setContentSize:NSMakeSize(width.doubleValue,1000)];settle(view);
            assert(fabs(view.bounds.size.width-width.doubleValue)<2 && scrollViews(view)==1);
            snapshot(container,[[NSString stringWithUTF8String:argv[2]]stringByAppendingPathComponent:[NSString stringWithFormat:@"Pane-%@-%@.png",width,theme]]);
        }
    }
    [pane setValue:@{@"ACPower":@NO,@"PowerSourceKnown":@YES,@"BatteryKnown":@YES,@"BatteryPercent":@75} forKey:@"system"];
    [pane performSelector:@selector(displayStatus)];
    [window setContentSize:NSMakeSize(660,1000)];
    snapshot(container,[[NSString stringWithUTF8String:argv[2]]stringByAppendingPathComponent:@"Pane-Battery-Dark.png"]);
    [window setContentSize:NSMakeSize(660,1600)];
    for(NSString *control in @[@"QuickProfile",@"FullSpeed",@"Touchpad",@"FnHotkeys",@"BacklightTimeout",@"all"]) {
        [pane setValue:@YES forKey:@"busy"];
        [pane setValue:control forKey:@"pendingControl"];
        [pane setValue:@1 forKey:@"pendingValue"];
        [pane performSelector:@selector(displayStatus)];settle(view);
        NSArray *indicators=spinners(view);assert(indicators.count==1);
        NSProgressIndicator *indicator=indicators.firstObject;
        assert(indicator.isIndeterminate && indicator.style==NSProgressIndicatorStyleSpinning);
        assert(fabs(indicator.bounds.size.width-16)<1 && fabs(indicator.bounds.size.height-16)<1);
        if([control isEqual:@"QuickProfile"]) {
            NSRect rect=[indicator convertRect:indicator.bounds toView:view];assert(NSMidX(rect)>440);
        }
        snapshot(container,[[NSString stringWithUTF8String:argv[2]]stringByAppendingPathComponent:[NSString stringWithFormat:@"Pane-Loading-%@.png",control]]);
        [pane setValue:@NO forKey:@"busy"];
        [pane performSelector:@selector(displayStatus)];settle(view);assert(spinners(view).count==0);
    }
    puts("PASS: single native scrolling pane, no tabs, host resizing, light/dark layout and matching 16pt native spinners with completion cleanup. No firmware writes.");
 }
}
