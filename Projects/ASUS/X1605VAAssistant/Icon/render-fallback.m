// Rasterize the current vector artwork with the system SDK and Command Line Tools.
#import <Cocoa/Cocoa.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *source = [NSString stringWithUTF8String:argv[1]];
        NSString *destination = [NSString stringWithUTF8String:argv[2]];
        NSImage *artwork = [[NSImage alloc] initWithContentsOfFile:source];
        if (!artwork.valid || ![NSFileManager.defaultManager createDirectoryAtPath:destination
            withIntermediateDirectories:YES attributes:nil error:NULL]) return 1;

        const int sizes[] = {16, 32, 128, 256, 512};
        for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
            int size = sizes[i];
            for (int scale = 1; scale <= 2; ++scale) {
                int pixels = size * scale;
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                    pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4
                    hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                if (!rep) return 1;
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
                [artwork drawInRect:NSMakeRect(0, 0, pixels, pixels) fromRect:NSZeroRect
                    operation:NSCompositingOperationCopy fraction:1];
                [NSGraphicsContext restoreGraphicsState];
                NSString *file = [NSString stringWithFormat:@"icon_%dx%d%@.png", size, size, scale == 2 ? @"@2x" : @""];
                NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                if (![png writeToFile:[destination stringByAppendingPathComponent:file] atomically:YES]) return 1;
            }
        }
    }
    return 0;
}
