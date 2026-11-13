#import <Cocoa/Cocoa.h>
extern NSDictionary *AsusMicLEDJob(NSString *home);
int main(void) {
    @autoreleasepool {
        NSDictionary *job = AsusMicLEDJob(@"/tmp/User & Name's Folder");
        NSArray *args = job[@"ProgramArguments"];
        if (args.count != 2 || ![args[1] isEqualToString:@"--login-agent"] ||
            ![args[0] isEqualToString:@"/Applications/X1605VA Assistant.app/Contents/MacOS/X1605VAAssistant"] ||
            ![job[@"RunAtLoad"] boolValue] || [job[@"KeepAlive"] boolValue]) return 1;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:job format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
        NSDictionary *decoded = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        if (![decoded isEqualToDictionary:job]) return 1;
        puts("Managed login job and plist round-trip passed without running setup.");
    }
    return 0;
}
