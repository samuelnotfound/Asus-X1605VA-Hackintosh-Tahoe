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
    [container addSubview:view];settle(view);assert(fabs(view.bounds.size.height-1000)<2);
    for(NSString *theme in @[@"Light",@"Dark"]) {
        window.appearance=[NSAppearance appearanceNamed:[theme isEqual:@"Dark"]?NSAppearanceNameDarkAqua:NSAppearanceNameAqua];NSApp.appearance=window.appearance;
        for(NSNumber *width in @[@480,@660,@900]) {
            [window setContentSize:NSMakeSize(width.doubleValue,1000)];settle(view);
            assert(fabs(view.bounds.size.width-width.doubleValue)<2 && scrollViews(view)==1);
            snapshot(view,[[NSString stringWithUTF8String:argv[2]]stringByAppendingPathComponent:[NSString stringWithFormat:@"Pane-%@-%@.png",width,theme]]);
        }
    }
    puts("PASS: single native scrolling pane, no tabs, host resizing and light/dark card layout. No firmware writes.");
 }
}
