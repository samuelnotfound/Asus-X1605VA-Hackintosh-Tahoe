#include <cassert>
#include <cstring>
#include <cstdio>
using IOReturn = int;
using UInt32 = unsigned;
constexpr int kIOReturnSuccess = 0, kIOReturnError = -1;
#define iokit_vendor_specific_msg(n) (0xe0000000u | (n))
#include "../Driver/TrackpadControl.hpp"
struct Target {
 bool state = true, rejectRead = false;
 int reads = 0;
 IOReturn message(unsigned selector, void *, void *value) {
  // Direct SetTouchStatus must never be called by the new write path.
  assert(selector==iokit_vendor_specific_msg(101));++reads;
  if(rejectRead)return -2;
  *static_cast<bool *>(value)=state;return 0;
 }
};
struct Endpoint {
 int calls=0; IOReturn status=0; UInt32 reply=0;
 IOReturn evaluateInteger(const char *name,UInt32 *value) {
  assert(!strcmp(name,"TTPD"));++calls;*value=reply;return status;
 }
};
int main() {
 assert(AsusSupportedTrackpadClass("VoodooI2CPrecisionTouchpadHIDEventDriver"));
 assert(AsusSupportedTrackpadClass("VoodooI2CMultitouchHIDEventDriver"));
 assert(!AsusSupportedTrackpadClass("VoodooI2CTouchscreenHIDEventDriver"));
 assert(!AsusSupportedTrackpadClass(nullptr));
 Target t;Endpoint e;bool result=false;
 assert(!AsusApplyTrackpadState(&t,(void*)nullptr,&e,false,false,&result)&&result&&t.reads==1&&!e.calls);
 assert(!AsusApplyTrackpadState(&t,(void*)nullptr,&e,true,true,&result)&&result&&!e.calls);
 assert(!AsusApplyTrackpadState(&t,(void*)nullptr,&e,true,false,&result)&&!result&&e.calls==1);
 assert(t.state); // An ACPI acknowledgment is not driver-state confirmation.
 t.rejectRead=true;int calls=e.calls;
 assert(AsusApplyTrackpadState(&t,(void*)nullptr,&e,true,false,&result)==-2&&e.calls==calls);
 t.rejectRead=false;e.status=-3;result=true;
 assert(AsusApplyTrackpadState(&t,(void*)nullptr,&e,true,false,&result)==-3&&result);
 e.status=0;e.reply=0xff;
 assert(AsusApplyTrackpadState(&t,(void*)nullptr,&e,true,false,&result)==kIOReturnError&&result);
 puts("Trackpad queries, class whitelist, single ACPI toggle request, no direct writes and endpoint errors passed.");
}
