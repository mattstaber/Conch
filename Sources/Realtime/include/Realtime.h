#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
typedef struct ConchRender ConchRender;
ConchRender *ConchRenderCreate(double sampleRate, float gain);
void ConchRenderDestroy(ConchRender *state);
void ConchRenderSetGain(ConchRender *state, float gain);
void ConchRenderSetMetering(ConchRender *state, bool enabled);
float ConchRenderTakePeak(ConchRender *state);
bool ConchRenderFailed(ConchRender *state);
unsigned long long ConchRenderTicks(ConchRender *state);
OSStatus ConchRenderIO(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context);

OSStatus ConchRenderInstall(AudioObjectID device, ConchRender *state, AudioDeviceIOProcID *io);
