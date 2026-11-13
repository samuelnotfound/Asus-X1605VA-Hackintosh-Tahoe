#import <Cocoa/Cocoa.h>
#include <assert.h>
#import "../Agent/app-setup.m"
int main(void) { @autoreleasepool {
 NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
 NSString *script=[folder stringByAppendingPathComponent:@"cleanup.command"];
 [@"#!/bin/zsh\nprint native-uninstall-launch-ok\n" writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 __block BOOL completed=NO,success=NO;__block NSString *output=nil;NSError *error=nil;
 assert(startUninstaller(script,^(BOOL ok,NSString *message){success=ok;output=message;completed=YES;},&error));
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(!completed&&deadline.timeIntervalSinceNow>0)CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.03,true);
 assert(completed&&success&&[output containsString:@"native-uninstall-launch-ok"]&&!uninstallerTask);
 assert(!startUninstaller([folder stringByAppendingPathComponent:@"missing.command"],^(BOOL ok,NSString *message){(void)ok;(void)message;abort();},&error)&&error);
 [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
 puts("In-app uninstaller launches directly, returns completion, and reports missing resources without a launchctl job.");
 }return 0;}
