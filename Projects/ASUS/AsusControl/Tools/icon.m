// Original vector artwork generated with AppKit. No private asset catalog.
#import <Cocoa/Cocoa.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(1024, 1024)];
        [canvas lockFocus];
        NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(60, 60, 904, 904) xRadius:206 yRadius:206];
        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.15 green:0.47 blue:0.96 alpha:1]
            endingColor:[NSColor colorWithSRGBRed:0.07 green:0.21 blue:0.63 alpha:1]];
        [gradient drawInBezierPath:shape angle:-90];
        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"fan" accessibilityDescription:nil];
        NSImage *white = [[NSImage alloc] initWithSize:NSMakeSize(570, 570)];
        [white lockFocus];
        [symbol drawInRect:NSMakeRect(0, 0, 570, 570)];
        [NSColor.whiteColor setFill]; NSRectFillUsingOperation(NSMakeRect(0, 0, 570, 570), NSCompositingOperationSourceAtop);
        [white unlockFocus];
        [white drawInRect:NSMakeRect(227, 227, 570, 570)];
        [canvas unlockFocus];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:canvas.TIFFRepresentation];
        return [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
