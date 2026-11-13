// AsusMicLED — samuelnotfound (https://github.com/samuelnotfound)
#ifndef ASUS_MIC_MUTE_H
#define ASUS_MIC_MUTE_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct {
    AudioDeviceID device;
    bool muted;
    bool writable;
    float volume;
    char name[256];
} MicrophoneMuteState;

// -1: read only. 0: set 100% and clear native mute. 1: set 0% and native mute. 2: toggle.
int microphone_mute_action(int action, MicrophoneMuteState *state,
    char *error, size_t errorSize);
#endif
