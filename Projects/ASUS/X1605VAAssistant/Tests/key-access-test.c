#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>
#include <assert.h>
#include <dispatch/dispatch.h>
#include <Carbon/Carbon.h>
static bool finderFrontmost;
static bool trusted, reportedReady, firmware, finderItems, launcher, runShortcuts, fnDown;
static bool tapEnabled = true, tapValid = true;
static bool testTapValid(CFMachPortRef tap){(void)tap;return tapValid;}
static int posted, opened;
static CGKeyCode lastPostedKey;
static CGEventFlags lastPostedFlags;
static int queued;
static void testDispatch(CFRunLoopRef loop,CFTypeRef mode,dispatch_block_t block){(void)loop;assert(CFEqual(mode,kCFRunLoopCommonModes));++queued;if(runShortcuts)block();}
static bool testKeyState(CGEventSourceStateID source,CGKeyCode key){assert(source==kCGEventSourceStateHIDSystemState&&key==kVK_Function);return fnDown;}
static bool testTapEnabled(CFMachPortRef tap){(void)tap;return tapEnabled;}
static void testEnable(CFMachPortRef tap,bool enabled){(void)tap;tapEnabled=enabled;}
static int attempts, reports;
static bool testTrusted(void) {return trusted;}
static CFMachPortRef testTap(CGEventTapLocation l,CGEventTapPlacement p,CGEventTapOptions o,CGEventMask m,CGEventTapCallBack c,void*u) {
 (void)l;(void)p;(void)o;(void)m;(void)c;(void)u;++attempts;return NULL;
}
static void testPost(CGEventTapLocation location,CGEventRef event) {
 assert(location==kCGHIDEventTap);++posted;
 lastPostedKey=(CGKeyCode)CGEventGetIntegerValueField(event,kCGKeyboardEventKeycode);
 lastPostedFlags=CGEventGetFlags(event);
 assert(CGEventGetIntegerValueField(event,kCGEventSourceUserData)==0x583136464e);
}
static void testAsync(dispatch_queue_t queue,dispatch_block_t block){(void)queue;if(runShortcuts)block();}
#define dispatch_async testAsync
#define CGEventPost testPost
#define CFRunLoopPerformBlock testDispatch
#define CGEventSourceKeyState testKeyState
#define CFMachPortIsValid testTapValid
#define CGEventTapIsEnabled testTapEnabled
#define CGEventTapEnable testEnable
#define AXIsProcessTrusted testTrusted
#define CGEventTapCreate testTap
#define main unusedAgentMain
#include "../Agent/X1605VAAssistant.c"
#undef main
int X1605VAAssistantSetup(bool loginAgent){(void)loginAgent;abort();}
void AsusMenuStart(void){abort();}
void AsusMenuMicrophoneUnavailable(void){abort();}
void AsusMenuMicrophoneError(void){abort();}
void AsusMenuMicrophoneKey(bool muted){(void)muted;abort();}
void AsusMenuMute(bool muted,bool writable,float volume){(void)muted;(void)writable;(void)volume;abort();}
bool AsusMenuFirmwareKeyboardAvailable(void){return firmware;}
bool AsusMenuFirmwareKeyboardContinuous(void){return firmware;}
void AsusMenuKeyboardLevel(int level){(void)level;abort();}
void AsusMenuRefreshKeyboard(void){abort();}
void AsusMenuRun(void){abort();}
void AsusMenuOpen(void){++opened;}
void AsusMenuToggle(void){++opened;}
void AsusMenuOpenExisting(void){abort();}
bool AsusFinderItemsFocused(void){return finderItems;}
pid_t AsusFinderFrontmostPID(void){return finderFrontmost?42:0;}
bool AsusMenuFirmwareLauncherAvailable(void){return launcher;}
int AsusMenuDiagnostics(void){abort();}
void AsusMenuSetKeyAccess(bool ready){reportedReady=ready;++reports;}
void AsusMenuSetPermissions(bool ax,bool ready){assert(!ready||ax);AsusMenuSetKeyAccess(ready);}
int microphone_mute_action(int action,MicrophoneMuteState*s,char*e,size_t n){(void)action;(void)s;(void)e;(void)n;abort();}
static bool traceEvent(CGEventType type, CGKeyCode key, CGEventFlags flags, CGEventTimestamp timestamp) {
 CGEventRef event=CGEventCreateKeyboardEvent(NULL,key,type!=kCGEventKeyUp);
 assert(event);
 CGEventSetType(event,type);
 CGEventSetFlags(event,flags);
 CGEventSetTimestamp(event,timestamp);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeyboardType,40);
 bool consumed=tapCb(NULL,type,event,NULL)==NULL;
 CFRelease(event);
 return consumed;
}

int main(void){
 gMenuEnabled=true;
 assert(!updateKeyTap(true)&&!reportedReady&&reports==1&&attempts==0);
 trusted=true;assert(!updateKeyTap(true)&&attempts==1); // Accessibility alone attempts the active tap.
 assert(!updateKeyTap(true)&&attempts==1);
 trusted=false;assert(!updateKeyTap(true));trusted=true;
 assert(!updateKeyTap(true)&&attempts==2);
 // The action boundaries must reject all writes before permission is ready.
 int confirmed=0;AsusMicrophoneSetEnabled(true);
 assert(!AsusKeyboardSet(50,&confirmed)&&!gKeyboardFailed);
 assert(!AsusTrackpadSet(false)&&gConn==0);
 gEnableLED=1;setLED(1);assert(!gLEDFailed&&gConn==0);
 // Invalidated ports must be discarded, including their run-loop source,
 // rather than permanently locking the menu behind a non-null stale pointer.
 gTap=(CFMachPortRef)CFRetain(CFSTR("invalid test tap"));tapValid=false;
 CFRunLoopSourceContext context={0};gTapSource=CFRunLoopSourceCreate(NULL,0,&context);
 CFRunLoopSourceRef oldSource=(CFRunLoopSourceRef)CFRetain(gTapSource);
 CFRunLoopAddSource(CFRunLoopGetMain(),gTapSource,kCFRunLoopCommonModes);
 assert(!updateKeyTap(true)&&!gTap&&!gTapSource&&attempts==3&&!CFRunLoopSourceIsValid(oldSource));
 CFRelease(oldSource);tapValid=true;
 gTap=(CFMachPortRef)(uintptr_t)1;tapEnabled=true;
 CGEventRef event=CGEventCreateKeyboardEvent(NULL,kVK_F9,true);assert(event);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event);
 firmware=true;
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==0);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL&&queued==0);
 CGEventSetFlags(event,kCGEventFlagMaskCommand);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event);
 CGEventSetFlags(event,0);CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F7);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==0);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F17);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==1);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL&&queued==1);
 CGEventSetIntegerValueField(event,kCGKeyboardEventAutorepeat,1);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==1);
 CGEventSetIntegerValueField(event,kCGKeyboardEventAutorepeat,0);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F18);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==2);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL&&queued==2);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F14);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&queued==2);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_ANSI_A);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event);
 runShortcuts=true;
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F13);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==2&&lastPostedKey==kVK_ANSI_3);
 assert(lastPostedFlags==(kCGEventFlagMaskCommand|kCGEventFlagMaskShift));
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==2); // held/repeat protection
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F11);
 // A function flag on an ordinary F11 is not a held physical Fn key.
 CGEventSetFlags(event,kCGEventFlagMaskSecondaryFn);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&posted==2);
 fnDown=true;
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==4&&lastPostedKey==kVK_ANSI_4);
 assert(lastPostedFlags==(kCGEventFlagMaskCommand|kCGEventFlagMaskShift));
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL);
 fnDown=false;
 CGEventSetFlags(event,kCGEventFlagMaskSecondaryFn);assert(tapCb(NULL,kCGEventFlagsChanged,event,NULL)==event);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==6&&lastPostedKey==kVK_ANSI_4);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL);
 CGEventSetFlags(event,0);assert(tapCb(NULL,kCGEventFlagsChanged,event,NULL)==event);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F16);launcher=true;
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&opened==1);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL&&opened==1);
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F12);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&opened==1); // ordinary F12 preserved
 CGEventSetFlags(event,kCGEventFlagMaskSecondaryFn);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&opened==1);
 CGEventSetFlags(event,0);CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_ForwardDelete);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event); // text / Finder rename field
 finderItems=true;finderFrontmost=true;
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==8&&lastPostedKey==kVK_Delete&&lastPostedFlags==kCGEventFlagMaskCommand);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==8);
 finderItems=false;finderFrontmost=false;assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL); // focus changed while held
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_Delete);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event); // Backspace preserved
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F11);CGEventSetFlags(event,kCGEventFlagMaskCommand);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&posted==8);
 CGEventSetFlags(event,0);CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F13);
 CGEventSetIntegerValueField(event,kCGEventSourceUserData,shortcutEventTag);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&posted==8); // no injected-event recursion
 // An ordinary Shift–Command–S stays intact. Only a distinct held Fn can disambiguate it.
 CFRelease(event);
 event=CGEventCreateKeyboardEvent(NULL,kVK_ANSI_S,true);assert(event);
 CGEventSetFlags(event,kCGEventFlagMaskCommand|kCGEventFlagMaskShift);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&posted==8);
 fnDown=true;
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==10&&lastPostedKey==kVK_ANSI_4);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==NULL&&posted==10);
 assert(tapCb(NULL,kCGEventKeyUp,event,NULL)==NULL&&posted==10);
 fnDown=false;
 CGEventSetFlags(event,kCGEventFlagMaskCommand|kCGEventFlagMaskShift|kCGEventFlagMaskAlternate);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&posted==10);
 // Reproduce the six events and gaps captured from the physical Fn+F11 key.
 const CGEventTimestamp t=3577771321814ULL;
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Command,kCGEventFlagMaskCommand,t));
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Shift,captureModifiers,t+175140));
 assert(traceEvent(kCGEventKeyDown,kVK_ANSI_S,captureModifiers,t+858492));
 assert(traceEvent(kCGEventKeyUp,kVK_ANSI_S,captureModifiers,t+2967164));
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Shift,kCGEventFlagMaskCommand,t+5484712));
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Command,0,t+8318050));
 assert(posted==12&&lastPostedKey==kVK_ANSI_4&&lastPostedFlags==captureModifiers);
 // The manually typed chord takes hundreds of milliseconds and is untouched.
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Command,kCGEventFlagMaskCommand,t+1000000000));
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Shift,captureModifiers,t+1230000000));
 assert(!traceEvent(kCGEventKeyDown,kVK_ANSI_S,captureModifiers,t+1600000000));
 assert(!traceEvent(kCGEventKeyUp,kVK_ANSI_S,captureModifiers,t+1680000000));
 assert(posted==12);
 // A fast start with a held S is replayed after the timeout.
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Command,kCGEventFlagMaskCommand,t+2000000000));
 assert(!traceEvent(kCGEventFlagsChanged,kVK_Shift,captureModifiers,t+2000500000));
 assert(traceEvent(kCGEventKeyDown,kVK_ANSI_S,captureModifiers,t+2001000000));
 CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.06,false);
 assert(posted==13&&lastPostedKey==kVK_ANSI_S&&lastPostedFlags==captureModifiers);
 assert(!traceEvent(kCGEventKeyUp,kVK_ANSI_S,captureModifiers,t+2060000000));
 trusted=false;postShortcut(kVK_Delete,kCGEventFlagMaskCommand);assert(posted==13); // revoked before queued action
 CGEventSetIntegerValueField(event,kCGKeyboardEventKeycode,kVK_F19);
 assert(tapCb(NULL,kCGEventKeyDown,event,NULL)==event&&!reportedReady);
 CFRelease(event);
 puts("Hotkey permissions stay nonblocking; ASUS raw/transport events are consumed once while ordinary keys/shortcuts pass; screenshot, Finder Delete and launcher events are posted once with no recursion.");
}
