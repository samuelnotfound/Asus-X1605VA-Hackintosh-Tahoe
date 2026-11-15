#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#include <assert.h>

static void snapshot(NSView *view, NSString *path) {
    [view setNeedsDisplay:YES];
    [view layoutSubtreeIfNeeded];
    [view displayIfNeededIgnoringOpacity];
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil; assert([bundle loadAndReturnError:&error]);
        NSPreferencePane *pane = [[bundle.principalClass alloc] initWithBundle:bundle];
        NSView *view = [pane loadMainView]; assert(view.bounds.size.width == 720);
        NSArray *cards = [pane valueForKey:@"profiles"];
        NSSlider *keyboard = [pane valueForKey:@"keyboard"];
        // Fixture status updates do not call didSelect, start polling, request
        // authorization, or issue any firmware writes.
        [pane setValue:@{@"Available":@YES, @"AsusSMC-Version":@"1.4.2"} forKey:@"snapshot"];
        [pane performSelector:@selector(displayStatus)];
        for (NSButton *card in cards) assert(!card.enabled);
        assert(!keyboard.enabled);
        // 1.0.0 exposed API 1 but did not support deferred, on-demand reads.
        [pane setValue:@{@"Available":@YES, @"AsusSMC-Version":@"1.0.0",
            @"X1605VA-ControlAPIVersion":@1, @"FanControlAllowed":@YES,
            @"KeyboardControlAvailable":@YES, @"KeyboardReadingValid":@YES} forKey:@"snapshot"];
        [pane performSelector:@selector(displayStatus)];
        for (NSButton *card in cards) assert(!card.enabled);
        assert(!keyboard.enabled);
        [pane setValue:@{@"Available":@YES, @"AsusSMC-Version":@"1.0.1",
            @"SettingsRefreshAvailable":@YES,
            @"X1605VA-ControlAPIVersion":@1, @"FanControlAllowed":@YES,
            @"FanReadingValid":@YES, @"FanRPM":@2500, @"FanRequestedMode":@0,
            @"ThermalProfileValid":@YES, @"ThermalProfile":@0,
            @"KeyboardControlAvailable":@YES, @"KeyboardReadingValid":@YES, @"KeyboardPercent":@67} forKey:@"snapshot"];
        [pane performSelector:@selector(displayStatus)];
        for (NSButton *card in cards) {
            assert(card.enabled);
            assert((card.state == NSControlStateValueOn) == (card.tag == 0));
        }
        assert(keyboard.enabled && keyboard.integerValue == 67);
        NSString *directory = [NSString stringWithUTF8String:argv[2]];
        // An offscreen window supplies the view's rendering context. It is
        // never ordered front and does not take focus from the user.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:view.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView = view;
        for (NSString *theme in @[@"Light", @"Dark"]) {
            window.appearance = [NSAppearance appearanceNamed:[theme isEqual:@"Dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
            NSApp.appearance = window.appearance;
            snapshot(view, [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Power-%@.png", theme]]);
            NSSegmentedControl *sections = [pane valueForKey:@"sections"];
            sections.selectedSegment = 1; [pane performSelector:@selector(sectionChanged:) withObject:sections];
            snapshot(view, [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Keyboard-%@.png", theme]]);
            sections.selectedSegment = 0; [pane performSelector:@selector(sectionChanged:) withObject:sections];
        }
        puts("PASS: preference pane loads, old-driver controls disabled, profile readback, and keyboard readback.");
    }
}
