// X1605VA Assistant — microphone input-volume control.
#include "mic-mute.h"
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MAX_CHANNELS 32
static const AudioObjectPropertyAddress defaultInput = {
    kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, 0
};
static OSStatus inputDevice(AudioDeviceID *device) {
    UInt32 bytes = sizeof(*device); *device = kAudioObjectUnknown;
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &defaultInput, 0, NULL, &bytes, device);
}
static AudioObjectPropertyAddress volumeAddress(UInt32 element) {
    return (AudioObjectPropertyAddress){kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput, element};
}
static UInt32 inputChannels(AudioDeviceID device) {
    AudioObjectPropertyAddress p = { kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput, 0 };
    UInt32 bytes = 0;
    if (AudioObjectGetPropertyDataSize(device, &p, 0, NULL, &bytes) || bytes < sizeof(AudioBufferList) || bytes > 65536) return 0;
    void *memory = calloc(1, bytes);
    if (!memory) return 0;
    AudioBufferList *buffers = memory;
    OSStatus rc = AudioObjectGetPropertyData(device, &p, 0, NULL, &bytes, buffers);
    UInt32 channels = 0;
    if (!rc && bytes >= sizeof(AudioBufferList) && buffers->mNumberBuffers <= (bytes - offsetof(AudioBufferList, mBuffers)) / sizeof(AudioBuffer)) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
            if (buffers->mBuffers[i].mNumberChannels > MAX_CHANNELS - channels) { rc = -1; break; }
            channels += buffers->mBuffers[i].mNumberChannels;
        }
    } else rc = -1;
    free(memory);
    return rc ? 0 : channels;
}
static bool elements(AudioDeviceID device, UInt32 *values, UInt32 *count) {
    AudioObjectPropertyAddress p = volumeAddress(0);
    if (AudioObjectHasProperty(device, &p)) { values[0] = 0; *count = 1; return true; }
    UInt32 channels = inputChannels(device);
    if (!channels) return false;
    for (UInt32 i = 0; i < channels; ++i) {
        values[i] = i + 1; p = volumeAddress(values[i]);
        if (!AudioObjectHasProperty(device, &p)) return false;
    }
    *count = channels; return true;
}
static bool readLevels(AudioDeviceID device, const UInt32 *values, UInt32 count, Float32 *levels) {
    for (UInt32 i = 0; i < count; ++i) {
        AudioObjectPropertyAddress p = volumeAddress(values[i]); UInt32 bytes = sizeof(Float32);
        if (AudioObjectGetPropertyData(device, &p, 0, NULL, &bytes, &levels[i]) || bytes != sizeof(Float32) ||
            !isfinite(levels[i]) || levels[i] < 0 || levels[i] > 1) return false;
    }
    return true;
}
static Float32 maximum(const Float32 *levels, UInt32 count) {
    Float32 value = 0; for (UInt32 i = 0; i < count; ++i) if (levels[i] > value) value = levels[i]; return value;
}
typedef struct {
    AudioObjectPropertyAddress address;
    UInt32 initial;
    Boolean writable;
} NativeMute;

static bool readNativeMute(AudioDeviceID device, const AudioObjectPropertyAddress *p, UInt32 *value) {
    UInt32 bytes = sizeof(*value);
    return !AudioObjectGetPropertyData(device, p, 0, NULL, &bytes, value) && bytes == sizeof(*value);
}

static UInt32 collectNativeMutes(AudioDeviceID device, NativeMute *controls) {
    AudioObjectPropertyAddress p = { kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, 0 };
    UInt32 count = 0;
    UInt32 channels = 0;
    do {
        UInt32 value;
        if (AudioObjectHasProperty(device, &p) && readNativeMute(device, &p, &value)) {
            Boolean writable = false;
            if (AudioObjectIsPropertySettable(device, &p, &writable)) writable = false;
            controls[count++] = (NativeMute){ p, value, writable };
            if (p.mElement == 0) return count;
        }
        if (p.mElement == 0) channels = inputChannels(device);
    } while (++p.mElement <= channels);
    return count;
}

int microphone_mute_action(int action, MicrophoneMuteState *state, char *error, size_t errorSize) {
    if (!state || !error || !errorSize) return 1;
    memset(state, 0, sizeof(*state)); error[0] = '\0';
    if (action < -1 || action > 2) { snprintf(error, errorSize, "Invalid microphone action."); return 1; }
    if (inputDevice(&state->device) || state->device == kAudioObjectUnknown) { snprintf(error, errorSize, "No microphone is available."); return 1; }
    UInt32 values[MAX_CHANNELS], count = 0; Float32 old[MAX_CHANNELS], desired[MAX_CHANNELS], observed[MAX_CHANNELS];
    if (!elements(state->device, values, &count) || !readLevels(state->device, values, count, old)) {
        snprintf(error, errorSize, "Cannot read this microphone's Input volume."); return 1;
    }
    Float32 volume = maximum(old, count);
    NativeMute native[MAX_CHANNELS];
    UInt32 muteCount = collectNativeMutes(state->device, native);
    bool nativeMuted = muteCount > 0 &&
        (native[0].address.mElement == 0 || muteCount == inputChannels(state->device));
    for (UInt32 i = 0; i < muteCount; ++i) nativeMuted &= native[i].initial != 0;
    state->muted = volume == 0 || nativeMuted;
    state->volume = volume;
    state->writable = true;
    for (UInt32 i = 0; i < count; ++i) {
        AudioObjectPropertyAddress p = volumeAddress(values[i]); Boolean writable = false;
        if (AudioObjectIsPropertySettable(state->device, &p, &writable) || !writable) state->writable = false;
    }
    if (action >= 0) {
        bool mute = action == 2 ? !state->muted : action == 1;
        if (!state->writable) { snprintf(error, errorSize, "This microphone's Input volume is not writable."); return 1; }
        for (UInt32 i = 0; i < count; ++i) desired[i] = mute ? 0.0f : 1.0f;
        for (UInt32 i = 0; !mute && i < muteCount; ++i) {
            if (native[i].initial && !native[i].writable) {
                snprintf(error, errorSize, "Cannot release the microphone's Core Audio mute.");
                return 1;
            }
        }
        bool failed = false;
        for (UInt32 i = 0; i < count; ++i) {
            AudioObjectPropertyAddress p = volumeAddress(values[i]);
            if (old[i] != desired[i] && AudioObjectSetPropertyData(state->device, &p, 0, NULL, sizeof(Float32), &desired[i])) { failed = true; break; }
        }
        if (!failed) {
            failed = !readLevels(state->device, values, count, observed);
            for (UInt32 i = 0; !failed && i < count; ++i)
                if (fabsf(observed[i] - desired[i]) > 0.025f || (desired[i] == 0 && observed[i] != 0) || (desired[i] > 0 && observed[i] == 0)) failed = true;
        }
        bool nativeFailed = false;
        if (!failed) {
            UInt32 desiredMute = mute ? 1 : 0;
            for (UInt32 i = 0; i < muteCount; ++i) {
                if (!native[i].writable) continue;
                UInt32 actual;
                if (((native[i].initial != 0) != mute &&
                     AudioObjectSetPropertyData(state->device, &native[i].address, 0, NULL, sizeof(desiredMute), &desiredMute)) ||
                    !readNativeMute(state->device, &native[i].address, &actual) || ((actual != 0) != mute)) nativeFailed = true;
            }
        }
        if (failed || (!mute && nativeFailed)) {
            if (nativeFailed) {
                for (UInt32 i = 0; i < muteCount; ++i)
                    if (native[i].writable)
                        AudioObjectSetPropertyData(state->device, &native[i].address, 0, NULL, sizeof(UInt32), &native[i].initial);
            }
            for (UInt32 i = 0; i < count; ++i) {
                AudioObjectPropertyAddress p = volumeAddress(values[i]);
                AudioObjectSetPropertyData(state->device, &p, 0, NULL, sizeof(Float32), &old[i]);
            }
            snprintf(error, errorSize, "Microphone change could not be confirmed; attempted to restore the previous state.");
            return 1;
        }
        AudioDeviceID current;
        if (inputDevice(&current) || current != state->device) {
            snprintf(error, errorSize, "The selected microphone changed during the action.");
            return 1;
        }
        state->volume = maximum(observed, count);
        state->muted = state->volume == 0;
        if (nativeFailed) {
            // A rejected native mute must not turn the gain back up.
            snprintf(error, errorSize, "Input volume is 0%%, but Core Audio mute could not be confirmed.");
            return 1;
        }
    }
    snprintf(state->name, sizeof(state->name), "Microphone");
    return 0;
}
