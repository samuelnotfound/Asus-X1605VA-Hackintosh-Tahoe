#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <assert.h>
static NSString *fixtureApp, *fixtureHome, *fixtureSource;
static NSMutableArray<NSArray<NSString *> *> *calls;
static NSString *lastProblem;
static NSString *FixtureHome(void) { return fixtureHome; }
static id FixtureMainBundle(id cls, SEL selector) { (void)cls;(void)selector;return [NSBundle bundleWithPath:fixtureSource]; }
@interface FixtureTask : NSObject
@property NSURL *executableURL;
@property NSArray<NSString *> *arguments;
@property id standardOutput;
@property id standardError;
@property int terminationStatus;
@property NSTaskTerminationReason terminationReason;
@property(copy) void (^terminationHandler)(FixtureTask *);
- (BOOL)launchAndReturnError:(NSError **)error;
- (void)waitUntilExit;
@end
@implementation FixtureTask
- (BOOL)launchAndReturnError:(NSError **)error {(void)error;[calls addObject:self.arguments];return YES;}
- (void)waitUntilExit {}
@end
@interface FixtureAlert : NSObject
@property NSString *messageText;
@property NSString *informativeText;
- (NSButton *)addButtonWithTitle:(NSString *)title;
- (NSModalResponse)runModal;
@end
@implementation FixtureAlert
- (NSButton *)addButtonWithTitle:(NSString *)title{(void)title;return nil;}
- (NSModalResponse)runModal{lastProblem=self.informativeText;return NSAlertFirstButtonReturn;}
@end
#define NSAlert FixtureAlert
#define NSHomeDirectory FixtureHome
#define NSTask FixtureTask
#define FN_HELPER_APP_PATH fixtureApp
#define FN_HELPER_PREVIOUS_APP_PATH [fixtureHome stringByAppendingPathComponent:@"Applications/X1605VA Fn Helper.app"]
#import "../Agent/app-setup.m"
static void makeBundle(NSString *path) {
 NSFileManager *fm=NSFileManager.defaultManager;
 [fm createDirectoryAtPath:[path stringByAppendingPathComponent:@"Contents"] withIntermediateDirectories:YES attributes:nil error:NULL];
 [@{@"CFBundleIdentifier":@"com.samuelnotfound.X1605VAAssistant.Agent",@"CFBundleName":@"X1605VA Assistant",@"CFBundleVersion":@"0.9.13",@"CFBundleExecutable":@"X1605VAAssistant"} writeToFile:[path stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
 NSString *binary=[path stringByAppendingPathComponent:@"Contents/MacOS/X1605VAAssistant"];
 [fm createDirectoryAtPath:binary.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
 [fm createFileAtPath:binary contents:[@"#!/bin/sh\nexit 0\n" dataUsingEncoding:NSUTF8StringEncoding] attributes:@{NSFilePosixPermissions:@0755}];
}
int main(void) { @autoreleasepool {
 fixtureHome=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 fixtureApp=[fixtureHome stringByAppendingPathComponent:@"Applications/X1605VA Assistant.app"];
 fixtureSource=[fixtureHome stringByAppendingPathComponent:@"Downloads/X1605VA Assistant.app"];
 makeBundle(fixtureSource);calls=[NSMutableArray new];
 Method method=class_getClassMethod(NSBundle.class,@selector(mainBundle));IMP original=method_getImplementation(method);
 method_setImplementation(method,(IMP)FixtureMainBundle);
 NSString *jobPath=[fixtureHome stringByAppendingPathComponent:@"Library/LaunchAgents/com.samuelnotfound.X1605VAAssistant.Agent.plist"];
 assert(X1605VAAssistantSetup(false)==1&&[lastProblem containsString:@"Move X1605VA Assistant.app to Applications"]);
 assert(X1605VAAssistantSetup(true)==1);
 assert(![NSFileManager.defaultManager fileExistsAtPath:fixtureApp]);
 assert(![NSFileManager.defaultManager fileExistsAtPath:jobPath]&&calls.count==0);

 makeBundle(fixtureApp);fixtureSource=fixtureApp;
 assert(X1605VAAssistantSetup(false)==0&&X1605VAAssistantSetup(false)==0);
 assert(calls.count==2);
 for(NSArray *args in calls) assert([args.firstObject isEqualToString:@"enable"]);
 NSDictionary *job=[NSDictionary dictionaryWithContentsOfFile:jobPath];
 assert([job[@"ProgramArguments"][0] isEqualToString:[fixtureApp stringByAppendingPathComponent:@"Contents/MacOS/X1605VAAssistant"]]);
 assert(X1605VAAssistantSetup(true)==0&&calls.count==2);
 method_setImplementation(method,original);
 [NSFileManager.defaultManager removeItemAtPath:fixtureHome error:NULL];
 puts("Outside launches report the Applications requirement without copying files or registering startup. Installed launches retain automatic login startup.");
 }return 0;}
