#import <Cocoa/Cocoa.h>
#include <assert.h>
static int popupCount;
static void testMenuClicked(void);
@interface TestButton : NSButton
@end
@implementation TestButton
- (void)performClick:(id)sender { (void)sender; ++popupCount; testMenuClicked(); }
@end
@interface TestStatusItem : NSObject
@property NSButton *button;
@property NSMenu *menu;
@property(getter=isVisible) BOOL visible;
@end
@implementation TestStatusItem
- (instancetype)init { self=[super init]; if(self){self.button=[[TestButton alloc]initWithFrame:NSMakeRect(0,0,36,24)];self.button.imagePosition=NSImageOnly;self.visible=YES;}return self; }
@end
@interface TestStatusBar : NSObject
+ (instancetype)systemStatusBar;
- (TestStatusItem *)statusItemWithLength:(CGFloat)length;
@end
@implementation TestStatusBar
+ (instancetype)systemStatusBar {static TestStatusBar*b;if(!b)b=[TestStatusBar new];return b;}
- (TestStatusItem *)statusItemWithLength:(CGFloat)length {(void)length;return [TestStatusItem new];}
@end
#define NSStatusItem TestStatusItem
#define NSStatusBar TestStatusBar
#import "../Agent/menu.m"
static bool requestedMic, trackpadAvailable, trackpadWriteFails, acpiAvailable=true;
static int trackpadState=1, trackpadWrites, writes, confirmed, micWrites, keyboardState=57;
void AsusMicrophoneSetEnabled(bool enabled){++micWrites;requestedMic=enabled;AsusMenuMute(!enabled,true,enabled ? 1 : 0);}
void AsusHelperUninstall(void){abort();}
bool AsusTrackpadGet(int *p){if(!trackpadAvailable)return false;*p=trackpadState;return true;}
bool AsusTrackpadAvailable(void){return trackpadAvailable&&acpiAvailable;}
bool AsusTrackpadSet(bool enabled){(void)enabled;++trackpadWrites;return !trackpadWriteFails;}
bool AsusKeyboardGet(int *p){*p=keyboardState;return true;}
bool AsusKeyboardSet(int p,int *q){++writes;confirmed=p;*q=p;keyboardState=p;return true;}
static void testMenuClicked(void){[menuController menuWillOpen:statusItem.menu];}
static void runMode(NSString *mode,double seconds){NSDate*d=[NSDate dateWithTimeIntervalSinceNow:seconds];while(d.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:mode beforeDate:d];}
int main(void){@autoreleasepool{
 [NSApplication sharedApplication];startMenu();AsusMenuSetPermissions(false,false);
 assert(popupCount==0&&!menuOpening&&[accessibilityItem.title containsString:@"Not Granted"]&&!accessibilityHintItem.hidden);
 assert(!microphoneSwitch.enabled&&!menuKeyboardSlider.enabled&&!accessibilityItem.hidden&&!accessibilityHintItem.hidden);
 AccessibilityDragIcon *permissionIcon=(AccessibilityDragIcon *)accessibilityHintItem.view.subviews.firstObject;
 assert([permissionIcon isKindOfClass:AccessibilityDragIcon.class]&&permissionIcon.appURL.isFileURL);
 assert([permissionIcon.appURL isEqual:NSBundle.mainBundle.bundleURL]);
 assert([microphoneSwitch isKindOfClass:NSSwitch.class]&&[menuKeyboardSlider.cell isKindOfClass:NSSliderCell.class]);
 assert([statusItem.menu indexOfItemWithTitle:@"Key Mappings"]<0);
 assert([statusItem.menu indexOfItemWithTitle:@"Input Monitoring: Not Granted…"]<0);
 microphoneSwitch.state=NSControlStateValueOff;[menuController microphoneChanged:microphoneSwitch];assert(micWrites==0);
 NSTextField *heading=headingItem.view.subviews.firstObject;assert([heading.textColor isEqual:NSColor.whiteColor]);
 firmwareKeyboard=2;keyboardControllable=true;lastKeyboard=57;AsusMenuMute(false,true,1);
 AsusMenuSetPermissions(true,true);assert(accessibilityItem.state==NSControlStateValueOn&&monitoringStatusItem.hidden);
 assert(microphoneSwitch.enabled&&menuKeyboardSlider.enabled&&accessibilityItem.hidden&&accessibilityHintItem.hidden);
 // Menu and external audio changes update state and lamp, without transient feedback.
 microphoneSwitch.state=NSControlStateValueOff;[menuController microphoneChanged:microphoneSwitch];assert(micWrites==1&&!requestedMic&&lastMute);
 assert(feedbackKind==FeedbackFn&&!muteLamp.hidden);
 assert([microphoneStatus.stringValue isEqualToString:@"Input volume 0%"]);
 assert([microphoneIcon.contentTintColor isEqual:NSColor.systemRedColor]);
 AsusMenuMute(false,true,1);assert(feedbackKind==FeedbackFn&&muteLamp.hidden);
 assert([microphoneStatus.stringValue isEqualToString:@"Input volume 100%"]);
 AsusMenuMute(false,true,0.42f);assert([microphoneStatus.stringValue isEqualToString:@"Input volume 42%"]);
 AsusMenuMute(true,true,0);AsusMenuMicrophoneKey(true);
 assert(feedbackKind==FeedbackMicrophone&&!feedbackEnabled&&!statusItem.button.image.template);
 runMode(NSEventTrackingRunLoopMode,1.25);assert(feedbackKind==FeedbackFn&&!muteLamp.hidden);
 menuKeyboardSlider.doubleValue=41;[menuController menuBrightnessChanged:menuKeyboardSlider];assert(writes==1&&confirmed==41&&feedbackKind==FeedbackFn);
 menuKeyboardSlider.doubleValue=72;[menuController menuBrightnessChanged:menuKeyboardSlider];assert(sliderCommitTimer.valid&&writes==1);
 AsusMenuSetPermissions(false,false);runMode(NSEventTrackingRunLoopMode,0.12);assert(writes==1&&accessibilityItem.state==NSControlStateValueOff);
 AsusMenuSetPermissions(true,true);menuKeyboardSlider.doubleValue=72;[menuController menuBrightnessChanged:menuKeyboardSlider];assert(writes==2&&confirmed==72&&feedbackKind==FeedbackFn);
 // Only the keyboard notification requests a backlight status icon.
 keyboardState=33;AsusMenuRefreshKeyboard();assert(lastKeyboard==33&&feedbackKind==FeedbackKeyboard&&feedbackLevel==33);
 runMode(NSEventTrackingRunLoopMode,1.25);assert(feedbackKind==FeedbackFn);
 trackpadAvailable=true;pollHardware();assert(trackpadSwitch.enabled);
 trackpadSwitch.state=NSControlStateValueOff;[menuController trackpadChanged:trackpadSwitch];
 assert(trackpadWrites==0&&trackpadConfirmPending&&!trackpadConfirmationItem.hidden&&!keyboardRow.hidden);
 assert([((NSTextField*)trackpadConfirmation.subviews[1]).stringValue containsString:@"Fn+F6"]);
 [menuController cancelTrackpad:nil];assert(!trackpadConfirmPending&&trackpadConfirmationItem.hidden&&!keyboardRow.hidden&&trackpadWrites==0);
 trackpadSwitch.state=NSControlStateValueOff;[menuController trackpadChanged:trackpadSwitch];[menuController confirmTrackpad:nil];
 assert(trackpadWrites==1&&trackpadTarget==0&&trackpadState==1&&!trackpadSwitch.enabled);
 trackpadState=0;pollHardware();assert(trackpadTarget<0&&[trackpadStatus.stringValue isEqualToString:@"Disabled"]&&feedbackKind==FeedbackFn);
 trackpadWriteFails=true;trackpadSwitch.state=NSControlStateValueOn;[menuController trackpadChanged:trackpadSwitch];assert(trackpadWrites==2&&trackpadError&&trackpadState==0);
 trackpadWriteFails=false;trackpadSwitch.state=NSControlStateValueOn;[menuController trackpadChanged:trackpadSwitch];
 trackpadDeadline=CFAbsoluteTimeGetCurrent()-1;pollHardware();assert(trackpadTarget<0&&trackpadError&&trackpadState==0);
 // Unsolicited Fn/AsusSMC state changes remain live in tracking mode.
 menuVisible=true;startHardwarePolling();trackpadState=1;keyboardState=67;
 runMode(NSEventTrackingRunLoopMode,0.30);assert(lastTouchpad==1&&lastKeyboard==67&&trackpadSwitch.state==NSControlStateValueOn);
 assert(feedbackKind==FeedbackTrackpad&&feedbackEnabled);
 menuVisible=false;[hardwarePollTimer invalidate];runMode(NSEventTrackingRunLoopMode,1.25);
 NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,36,24) styleMask:0 backing:NSBackingStoreBuffered defer:NO];window.contentView=statusItem.button;
 AsusMenuOpen();AsusMenuOpen();runMode(NSDefaultRunLoopMode,0.03);assert(popupCount==1&&menuVisible);
 AsusMenuToggle();[menuController menuDidClose:statusItem.menu];assert(!menuVisible);
 AsusMenuOpen();AsusMenuToggle();AsusMenuOpen();runMode(NSDefaultRunLoopMode,0.03);assert(popupCount==2&&menuVisible);
 assert([statusItem.menu indexOfItemWithTitle:@"Quit"]<0 && [statusItem.menu indexOfItemWithTitle:@"Uninstall…"]<0);
 assert(optionsItem.hidden);
 [optionsButton performClick:nil];
 assert(menuVisible&&!optionsItem.hidden);
 assert([((NSTextField *)optionsItem.view.subviews[0]).stringValue hasPrefix:@"Version "]);
 assert(((NSButton *)optionsItem.view.subviews[2]).action==@selector(uninstall:));
 [optionsButton performClick:nil];assert(menuVisible&&optionsItem.hidden);
 [hideButton performClick:nil];assert(menuVisible&&hideConfirmPending&&!hideConfirmationItem.hidden&&!hideButton.enabled);
 [menuController cancelHide:nil];assert(menuVisible&&!hideConfirmPending&&hideConfirmationItem.hidden&&hideButton.enabled);
 [hideButton performClick:nil];[menuController confirmHide:nil];
 assert(!statusItem.visible&&keyAccessReady);
 [menuController menuDidClose:statusItem.menu];
 // The running app handles Finder reopen without replacing the helper.
 [menuController applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
 runMode(NSDefaultRunLoopMode,0.03);assert(statusItem.visible&&popupCount==3&&menuVisible);
 [menuController menuDidClose:statusItem.menu];
 // Source-only releases qualify without any attached binary.
 NSString *sha=@"0123456789abcdef0123456789abcdef01234567";
 NSArray *releases=@[
  @{@"tag_name":@"x1605va-assistant-v0.9.11",@"draft":@NO,@"target_commitish":sha,@"assets":@[]},
  @{@"tag_name":@"x1605va-assistant-v0.9.9",@"draft":@NO,@"target_commitish":sha},
  @{@"tag_name":@"x1605va-assistant-v1.0.0",@"draft":@NO,@"target_commitish":@"main"},
  @{@"tag_name":@"x1605va-assistant-v2.0.0",@"draft":@YES,@"target_commitish":sha},
  @{@"tag_name":@"other-project-v3.0.0",@"draft":@NO,@"target_commitish":sha},
  @{@"tag_name":@"x1605va-assistant-v4.0.0",@"draft":[NSNull null],@"target_commitish":sha}
 ];
 assert([newerReleaseVersion(releases,@"0.9.10") isEqualToString:@"0.9.11"]);
 assert(!newerReleaseVersion(releases,@"0.9.11")&&!newerReleaseVersion(@{},@"0.9.10"));
 // The brightest backlight symbol is a full-opacity white, non-template image.
 NSImage *bright=feedbackImage(FeedbackKeyboard,true,100);assert(!bright.template);
 NSBitmapImageRep *pixels=[NSBitmapImageRep imageRepWithData:bright.TIFFRepresentation];BOOL white=NO;
 for(NSInteger y=0;y<pixels.pixelsHigh;y++)for(NSInteger x=0;x<pixels.pixelsWide;x++){
  NSColor *c=[[pixels colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
  if(c.alphaComponent>0.95){assert(c.redComponent>0.95&&c.greenComponent>0.95&&c.blueComponent>0.95);white=YES;}
 }
 assert(white);
 [sliderCommitTimer invalidate];[feedbackTimer invalidate];[trackpadConfirmTimer invalidate];
 puts("Native controls, individual permission status, inline confirmations, keyboard-only feedback and full-white backlight passed.");
}return 0;}
