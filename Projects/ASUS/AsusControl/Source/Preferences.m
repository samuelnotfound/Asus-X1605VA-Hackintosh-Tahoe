#import "Preferences.h"
#import "Policy.h"
#import "DeviceClient.h"
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <signal.h>

NSURL *AsusSupportDirectory(void) {
    return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"AsusControl" isDirectory:YES];
}
static NSDictionary *readJSON(NSString *name) {
    NSData *data = [NSData dataWithContentsOfURL:[AsusSupportDirectory() URLByAppendingPathComponent:name]];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static BOOL writeJSON(NSString *name, NSDictionary *value, NSError **error) {
    if (![NSFileManager.defaultManager createDirectoryAtURL:AsusSupportDirectory() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];
    NSURL *url = [AsusSupportDirectory() URLByAppendingPathComponent:name];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:error];
}
NSDictionary *AsusReadPreferences(void) {
    NSMutableDictionary *preferences = [AsusDefaultPreferences() mutableCopy];
    NSDictionary *saved = readJSON(@"settings.json");
    [preferences addEntriesFromDictionary:saved];
    if (!saved[@"ManualProfile"] && saved[@"ACProfile"]) preferences[@"ManualProfile"] = saved[@"ACProfile"];
    // Retired switching rules must not override the three direct profile cards.
    [preferences removeObjectsForKeys:@[@"SplitProfiles",@"FollowLowPower",@"ACProfile",@"BatteryProfile",@"AutoPerformanceOnAC",@"BatteryManaged",@"BatteryCare",@"FullChargeUntil"]];
    return preferences;
}
BOOL AsusWritePreferences(NSDictionary *preferences, NSError **error) { return writeJSON(@"settings.json", preferences, error); }
NSDictionary *AsusReadAgentState(void) { return readJSON(@"agent-state.json"); }
BOOL AsusWriteAgentState(NSDictionary *state, NSError **error) { return writeJSON(@"agent-state.json", state, error); }

static BOOL launchctl(NSArray<NSString *> *arguments, BOOL quiet, NSError **error) {
    NSTask *task = [[NSTask alloc] init]; task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;
    NSPipe *output = [NSPipe pipe]; task.standardError = output; task.standardOutput = output;
    if (![task launchAndReturnError:error]) return NO;
    NSData *data = [output.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
    if (task.terminationStatus == 0) return YES;
    if (error && !quiet) *error = [NSError errorWithDomain:@"com.samuelnotfound.AsusControl.Service" code:task.terminationStatus
        userInfo:@{NSLocalizedDescriptionKey:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"The automatic settings service could not start."}];
    return NO;
}
static NSURL *agentPlist(void) {
    return [[NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"LaunchAgents/com.samuelnotfound.AsusControl.Agent.plist"];
}
BOOL AsusRemoveAgent(NSError **error) {
    NSDictionary *state = AsusReadAgentState();
    if ([state[@"Dimmed"] boolValue] && [state[@"RestoreKeyboard"] unsignedIntValue] > 0 && [state[@"RestoreKeyboard"] unsignedIntValue] <= 100)
        AsusControlSendCommand(YES, [state[@"RestoreKeyboard"] unsignedIntValue], NULL);
    NSURL *plist = agentPlist();
    if ([NSFileManager.defaultManager fileExistsAtPath:plist.path] && ![NSFileManager.defaultManager removeItemAtURL:plist error:error]) return NO;
    NSString *service = [NSString stringWithFormat:@"gui/%u/com.samuelnotfound.AsusControl.Agent", getuid()];
    launchctl(@[@"bootout", service], YES, NULL);
    return YES;
}
BOOL AsusConfigureAgent(NSBundle *bundle, NSDictionary *preferences, NSError **error) {
    NSMutableDictionary *saved = [preferences mutableCopy];
    saved[@"SourceBundlePath"] = bundle.bundlePath;
    saved[@"Revision"] = NSUUID.UUID.UUIDString;
    if (!AsusWritePreferences(saved, error)) return NO;
    if (!AsusNeedsAgent(saved)) return AsusRemoveAgent(error);
    NSURL *original = [bundle.bundleURL URLByAppendingPathComponent:@"Contents/Helpers/asuscontrol-agent"];
    NSURL *installed = [AsusSupportDirectory() URLByAppendingPathComponent:@"asuscontrol-agent"];
    NSURL *staged = [AsusSupportDirectory() URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![NSFileManager.defaultManager copyItemAtURL:original toURL:staged error:error]) return NO;
    // Replace a running executable by inode, without modifying its mapped file.
    if (rename(staged.fileSystemRepresentation, installed.fileSystemRepresentation) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        [NSFileManager.defaultManager removeItemAtURL:staged error:NULL]; return NO;
    }
    NSURL *plist = agentPlist();
    if (![NSFileManager.defaultManager createDirectoryAtURL:plist.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSDictionary *job = @{@"Label":@"com.samuelnotfound.AsusControl.Agent", @"ProgramArguments":@[installed.path],
        @"RunAtLoad":@YES, @"KeepAlive":@NO, @"ProcessType":@"Background", @"LimitLoadToSessionType":@"Aqua"};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:job format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToURL:plist options:NSDataWritingAtomic error:error]) return NO;
    NSString *domain = [NSString stringWithFormat:@"gui/%u", getuid()];
    NSString *service = [domain stringByAppendingString:@"/com.samuelnotfound.AsusControl.Agent"];
    if (launchctl(@[@"print", service], YES, NULL)) {
        // Normal changes wake the existing agent. Restart only an outdated
        // binary or a loaded job whose process has exited.
        if ([AsusReadAgentState()[@"Version"] isEqual:@ASUS_CONTROL_VERSION] &&
            launchctl(@[@"kill", @"SIGUSR1", service], YES, NULL)) return YES;
        return launchctl(@[@"kickstart", @"-k", service], NO, error);
    }
    return launchctl(@[@"bootstrap", domain, plist.path], NO, error);
}
