#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

static Float32 levels[2] = {.63f, .63f};
static bool channels, writable = true, ignoreWrites, hasMute = true, channelMute, ignoreNativeWrites;
static int failChannel = -1, writes, nativeWrites;
static UInt32 nativeMute[3];
static OSStatus getData(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32*n,void*out);
static OSStatus setData(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32 n,const void*in);
static OSStatus getSize(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32*n);
static Boolean hasProperty(AudioObjectID d,const AudioObjectPropertyAddress*p);
static OSStatus settable(AudioObjectID d,const AudioObjectPropertyAddress*p,Boolean*out);
#define AudioObjectGetPropertyData getData
#define AudioObjectSetPropertyData setData
#define AudioObjectGetPropertyDataSize getSize
#define AudioObjectHasProperty hasProperty
#define AudioObjectIsPropertySettable settable
#include "../Agent/mic-mute.c"

static Boolean hasProperty(AudioObjectID d,const AudioObjectPropertyAddress*p) {
 (void)d;
 if(p->mSelector==kAudioDevicePropertyMute) return hasMute && (channelMute ? p->mElement>0 && p->mElement<=2 : p->mElement==0);
 return p->mSelector!=kAudioDevicePropertyVolumeScalar || (channels?p->mElement>0:p->mElement==0);
}
static OSStatus settable(AudioObjectID d,const AudioObjectPropertyAddress*p,Boolean*out) { (void)d;(void)p;*out=writable;return noErr; }
static OSStatus getSize(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32*n) { (void)d;(void)p;(void)q;(void)a;*n=sizeof(AudioBufferList);return noErr; }
static OSStatus getData(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32*n,void*out) {
 (void)d;(void)q;(void)a;
 switch(p->mSelector) {
  case kAudioHardwarePropertyDefaultInputDevice:*(AudioDeviceID*)out=69;*n=sizeof(AudioDeviceID);break;
  case kAudioDevicePropertyDeviceUID:*(CFStringRef*)out=CFRetain(CFSTR("test-input"));*n=sizeof(CFStringRef);break;
  case kAudioDevicePropertyVolumeScalar:*(Float32*)out=levels[channels?p->mElement-1:0];*n=sizeof(Float32);break;
  case kAudioDevicePropertyMute:*(UInt32*)out=nativeMute[p->mElement];*n=sizeof(UInt32);break;
  case kAudioDevicePropertyStreamConfiguration: { AudioBufferList*b=out;b->mNumberBuffers=1;b->mBuffers[0].mNumberChannels=2;*n=sizeof(AudioBufferList);break; }
  default: return -1;
 } return noErr;
}
static OSStatus setData(AudioObjectID d,const AudioObjectPropertyAddress*p,UInt32 q,const void*a,UInt32 n,const void*in) {
 (void)d;(void)q;(void)a;(void)n;
 if(p->mSelector==kAudioDevicePropertyMute){++nativeWrites;if(!ignoreNativeWrites)nativeMute[p->mElement]=*(const UInt32*)in;return noErr;}
 assert(p->mSelector==kAudioDevicePropertyVolumeScalar);++writes;
 int i=channels?(int)p->mElement-1:0;
 if(i==failChannel){failChannel=-1;return -1;}
 if(!ignoreWrites)levels[i]=*(const Float32*)in;
 return noErr;
}
int main(void) {
 MicrophoneMuteState s;char error[512];
 assert(!microphone_mute_action(-1,&s,error,sizeof(error))&&!s.muted&&writes==0);
 assert(!microphone_mute_action(1,&s,error,sizeof(error))&&s.muted&&levels[0]==0&&nativeWrites==1&&nativeMute[0]==1);
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&!s.muted&&levels[0]==1&&nativeMute[0]==0);
 levels[0]=.42f;assert(!microphone_mute_action(-1,&s,error,sizeof(error)));levels[0]=0;
 assert(!microphone_mute_action(-1,&s,error,sizeof(error)));
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&levels[0]==1);
 channels=true;levels[0]=.25f;levels[1]=.75f;
 assert(!microphone_mute_action(1,&s,error,sizeof(error))&&levels[0]==0&&levels[1]==0);
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&levels[0]==1&&levels[1]==1);
 levels[0]=.25f;levels[1]=.75f;failChannel=1;assert(microphone_mute_action(1,&s,error,sizeof(error))&&levels[0]==.25f&&levels[1]==.75f);
 ignoreWrites=true;assert(microphone_mute_action(1,&s,error,sizeof(error)));ignoreWrites=false;
 int before=writes;writable=false;assert(microphone_mute_action(1,&s,error,sizeof(error))&&writes==before);writable=true;
 channels=false;levels[0]=.6f;nativeMute[0]=1;
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&!s.muted&&!nativeMute[0]&&levels[0]==1);
 // Native mute readback failure keeps volume at zero; a failed unmute rolls back.
 levels[0]=.6f;ignoreNativeWrites=true;
 assert(microphone_mute_action(1,&s,error,sizeof(error))&&s.muted&&levels[0]==0&&nativeMute[0]==0);
 nativeMute[0]=1;
 assert(microphone_mute_action(0,&s,error,sizeof(error))&&levels[0]==0&&nativeMute[0]==1);
 ignoreNativeWrites=false;
 // No mute property still allows volume-only mute and unmute.
 hasMute=false;nativeMute[0]=0;levels[0]=.5f;before=nativeWrites;
 assert(!microphone_mute_action(1,&s,error,sizeof(error))&&levels[0]==0&&nativeWrites==before);
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&levels[0]==1&&nativeWrites==before);
 // Master gain can coexist with separate native mute switches per channel.
 hasMute=true;channelMute=true;
 assert(!microphone_mute_action(1,&s,error,sizeof(error))&&nativeMute[1]&&nativeMute[2]&&levels[0]==0);
 assert(!microphone_mute_action(0,&s,error,sizeof(error))&&!nativeMute[1]&&!nativeMute[2]&&levels[0]==1);
 assert(microphone_mute_action(7,&s,error,sizeof(error)));

 puts("Combo mute, 100% unmute, per-channel mute, gain-only fallback, and rollback passed.");
}
