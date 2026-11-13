#import <Cocoa/Cocoa.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        if (!image.valid || !rep || rep.pixelsWide < 16 || rep.pixelsHigh < 16) return 1;
        NSColorSpace *rgb = NSColorSpace.sRGBColorSpace;
        NSColor *tile = [[rep colorAtX:rep.pixelsWide / 2 y:rep.pixelsHigh / 2] colorUsingColorSpace:rgb];
        NSColor *lamp = [[rep colorAtX:rep.pixelsWide * 27 / 100 y:rep.pixelsHigh * 29 / 100] colorUsingColorSpace:rgb];
        if (!tile || !lamp || tile.alphaComponent < 0.9 || tile.redComponent > 0.32 ||
            tile.greenComponent > 0.32 || tile.blueComponent > 0.32 || lamp.alphaComponent < 0.9 ||
            lamp.redComponent < 0.8 || lamp.greenComponent > 0.65 || lamp.blueComponent > 0.45) {
            fputs("Expected the current dark tile and orange lamp in the icon.\n", stderr);
            return 1;
        }
        puts("Current dark tile and orange lamp verified.");
    }
    return 0;
}
