#import <Cocoa/Cocoa.h>
#include <stdbool.h>
#include <unistd.h>

#ifndef FN_HELPER_APP_PATH
#define FN_HELPER_APP_PATH @"/Applications/X1605VA Assistant.app"
#endif

#ifndef FN_HELPER_PREVIOUS_APP_PATH
#define FN_HELPER_PREVIOUS_APP_PATH @"/Applications/X1605VA Fn Helper.app"
#endif

static NSString *const AgentLabel = @"com.samuelnotfound.X1605VAAssistant.Agent";
static NSString *const LegacyAgentLabel = @"com.samuelnotfound.AsusMicLED.Agent";
static BOOL matchingApp(NSString *path) {
    NSString *identifier = [NSBundle bundleWithPath:path].bundleIdentifier;
    return [identifier isEqualToString:AgentLabel] || [identifier isEqualToString:LegacyAgentLabel];
}

NSDictionary *AsusMicLEDJob(NSString *home) {
    NSString *app = FN_HELPER_APP_PATH;
    NSString *log = [home stringByAppendingPathComponent:@"Library/Logs/X1605VA Assistant.log"];
    return @{@"Label": AgentLabel,
             @"ProgramArguments": @[[app stringByAppendingPathComponent:@"Contents/MacOS/X1605VAAssistant"], @"--login-agent"],
             @"RunAtLoad": @YES, @"KeepAlive": @NO, @"ProcessType": @"Interactive",
             @"StandardOutPath": log, @"StandardErrorPath": log};
}

static BOOL runTool(NSString *executable, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return NO;
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

static BOOL launchctl(NSArray<NSString *> *arguments) { return runTool(@"/bin/launchctl", arguments); }

static int setupError(NSString *problem, bool loginAgent) {
    if (loginAgent) {
        fprintf(stderr, "X1605VA Assistant: %s\n", problem.UTF8String);
    } else {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"X1605VA Assistant could not start";
        alert.informativeText = problem;
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    }
    return 1;
}

int X1605VAAssistantSetup(bool loginAgent) {
    @autoreleasepool {
        NSString *source = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
        NSString *installed = FN_HELPER_APP_PATH;
        if (![source isEqualToString:installed.stringByStandardizingPath])
            return setupError(@"Move X1605VA Assistant.app to Applications, then open that copy.", loginAgent);
        if (getuid() == 0)
            return setupError(@"Open X1605VA Assistant as your normal macOS user, without sudo.", loginAgent);
        if (loginAgent) return 0;

        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *home = NSHomeDirectory();
        NSString *agents = [home stringByAppendingPathComponent:@"Library/LaunchAgents"];
        NSString *plist = [agents stringByAppendingPathComponent:[AgentLabel stringByAppendingString:@".plist"]];
        NSString *service = [NSString stringWithFormat:@"gui/%u/%@", getuid(), AgentLabel];
        NSError *error = nil;
        for (NSString *dir in @[agents,
                 [home stringByAppendingPathComponent:@"Library/Caches"],
                 [home stringByAppendingPathComponent:@"Library/Logs"]]) {
            if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error])
                return setupError(error.localizedDescription, false);
        }
        NSData *job = [NSPropertyListSerialization dataWithPropertyList:AsusMicLEDJob(home)
                            format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!job || ![job writeToFile:plist options:NSDataWritingAtomic error:&error])
            return setupError(error.localizedDescription, false);
        // Enable the per-user job for future logins. Keep this launch running.
        if (!launchctl(@[@"enable", service]))
            return setupError(@"Could not enable automatic login startup.", false);

        NSString *legacyPlist = [agents stringByAppendingPathComponent:[LegacyAgentLabel stringByAppendingString:@".plist"]];
        NSDictionary *legacyJob = [NSDictionary dictionaryWithContentsOfFile:legacyPlist];
        if ([legacyJob[@"Label"] isEqualToString:LegacyAgentLabel]) {
            [fm removeItemAtPath:legacyPlist error:NULL];
            NSString *legacyService = [NSString stringWithFormat:@"gui/%u/%@", getuid(), LegacyAgentLabel];
            if (launchctl(@[@"print", legacyService])) launchctl(@[@"bootout", legacyService]);
        }
        for (NSString *legacy in @[FN_HELPER_PREVIOUS_APP_PATH,
                [home stringByAppendingPathComponent:@"Library/Application Support/X1605VA Fn Helper/X1605VA Fn Helper.app"],
                [home stringByAppendingPathComponent:@"Library/Application Support/X1605VA Companion/X1605VA Companion.app"],
                [home stringByAppendingPathComponent:@"Applications/AsusMicLED.app"],
                [home stringByAppendingPathComponent:@"Library/Application Support/AsusMicLED/AsusMicLED.app"],
                [home stringByAppendingPathComponent:@"Library/Application Support/ASUS Companion/ASUS Companion.app"]]) {
            if ([fm fileExistsAtPath:legacy] &&
                ![fm destinationOfSymbolicLinkAtPath:legacy error:NULL] &&
                matchingApp(legacy))
                [fm removeItemAtPath:legacy error:NULL];
        }
        return 0;
    }
}

// Keep the app alive until the copied cleanup process finishes. The script
// removes the login file first and stops any loaded job only after cleanup.
static NSTask *uninstallerTask;
static BOOL startUninstaller(NSString *source, void (^completion)(BOOL, NSString *), NSError **failure) {
    if (uninstallerTask) return NO;
    NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"X1605VA-Assistant-Uninstall-%@.command", NSUUID.UUID.UUIDString]];
    if (!source || ![NSFileManager.defaultManager copyItemAtPath:source toPath:copy error:failure]) return NO;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"]; task.arguments = @[copy, @"--self-delete"];
    NSPipe *output = [NSPipe pipe]; task.standardOutput = output; task.standardError = output;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [output.fileHandleForReading readDataToEndOfFile];
        NSString *message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        BOOL ok = finished.terminationReason == NSTaskTerminationReasonExit && finished.terminationStatus == 0;
        [NSFileManager.defaultManager removeItemAtPath:copy error:NULL];
        CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ uninstallerTask = nil; completion(ok, message); });
        CFRunLoopWakeUp(CFRunLoopGetMain());
    };
    uninstallerTask = task;
    if ([task launchAndReturnError:failure]) return YES;
    uninstallerTask = nil; [NSFileManager.defaultManager removeItemAtPath:copy error:NULL]; return NO;
}
void AsusHelperUninstall(void) {
    if (uninstallerTask) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Uninstall X1605VA Assistant?";
    alert.informativeText = @"Fn+F9 will stop muting and unmuting the microphone. The orange F9 light may still turn on even when the microphone is on.";
    [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Uninstall"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] != NSAlertSecondButtonReturn) return;
    NSError *error = nil;
    NSString *source = [NSBundle.mainBundle pathForResource:@"Uninstall" ofType:@"command"];
    BOOL launched = startUninstaller(source, ^(BOOL ok, NSString *message) {
        if (ok) {
            if ([message containsString:@"PERMISSION_RESET_WARNING"]) {
                NSAlert *notice = [NSAlert new]; notice.messageText = @"X1605VA Assistant was uninstalled";
                notice.informativeText = @"macOS could not clear every permission entry. In Privacy & Security, remove any remaining X1605VA Assistant entries from Accessibility and Input Monitoring using the − button.";
                [notice runModal];
            }
            [NSApp terminate:nil]; return;
        }
        NSAlert *failure = [NSAlert new]; failure.messageText = @"Uninstall could not finish";
        failure.informativeText = message.length ? message : @"macOS did not allow the app to remove its installed files."; [failure runModal];
    }, &error);
    if (!launched) {
        NSAlert *failure = [NSAlert new]; failure.messageText = @"Uninstall could not start";
        failure.informativeText = error.localizedDescription ?: @"The app’s uninstall resource is missing."; [failure runModal];
    }
}
