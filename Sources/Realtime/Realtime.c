#include "Realtime.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Only lock-free atomics and bounded sample loops on the HAL realtime thread.
// No Swift/ARC, locks, allocations, logging, dispatch, filesystem or network IO.
struct ConchRender {
    _Atomic float target, peak;
    _Atomic bool meter, failed;
    _Atomic unsigned long long ticks;
    float current, step;
};
ConchRender *ConchRenderCreate(double rate, float gain) {
    ConchRender *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    atomic_init(&s->target, gain); atomic_init(&s->peak, 0);
    atomic_init(&s->meter, false); atomic_init(&s->failed, false);
    atomic_init(&s->ticks, 0); s->current = gain;
    s->step = 1.0f / (float)(rate * 0.005); // five millisecond full-range ramp
    if (!atomic_is_lock_free(&s->target) || !atomic_is_lock_free(&s->ticks)) { free(s); return NULL; }
    return s;
}
void ConchRenderDestroy(ConchRender *s) { free(s); }
void ConchRenderSetGain(ConchRender *s, float v) { atomic_store_explicit(&s->target, isfinite(v) ? fminf(1, fmaxf(0,v)) : 0, memory_order_relaxed); }
void ConchRenderSetMetering(ConchRender *s, bool v) { atomic_store_explicit(&s->meter,v,memory_order_relaxed); if (!v) atomic_store(&s->peak,0); }
float ConchRenderTakePeak(ConchRender *s) { return atomic_exchange_explicit(&s->peak,0,memory_order_relaxed); }
bool ConchRenderFailed(ConchRender *s) { return atomic_load(&s->failed); }
unsigned long long ConchRenderTicks(ConchRender *s) { return atomic_load_explicit(&s->ticks,memory_order_relaxed); }
static unsigned channels(const AudioBufferList *b) {
    unsigned n=0; for (unsigned i=0;i<b->mNumberBuffers;i++) n+=b->mBuffers[i].mNumberChannels; return n;
}
static float *sample(const AudioBufferList *b, unsigned channel, unsigned frame) {
    for (unsigned i=0;i<b->mNumberBuffers;i++) {
        const AudioBuffer *p=&b->mBuffers[i];
        if (channel < p->mNumberChannels) {
            unsigned index=frame*p->mNumberChannels+channel;
            return p->mData && (index+1)*sizeof(float)<=p->mDataByteSize ? &((float*)p->mData)[index] : NULL;
        }
        channel-=p->mNumberChannels;
    }
    return NULL;
}
OSStatus ConchRenderIO(AudioObjectID d, const AudioTimeStamp *n, const AudioBufferList *in,
 const AudioTimeStamp *it, AudioBufferList *out, const AudioTimeStamp *ot, void *ctx) {
    ConchRender *s=ctx;
    atomic_fetch_add_explicit(&s->ticks,1,memory_order_relaxed);
    for (unsigned b=0;b<out->mNumberBuffers;b++) if(out->mBuffers[b].mData) memset(out->mBuffers[b].mData,0,out->mBuffers[b].mDataByteSize);
    unsigned nc=channels(in);
    if (!nc || nc>2 || nc!=channels(out) || !out->mNumberBuffers || !out->mBuffers[0].mNumberChannels) { atomic_store(&s->failed,true); return noErr; }
    unsigned frames=out->mBuffers[0].mDataByteSize/(sizeof(float)*out->mBuffers[0].mNumberChannels);
    float target=atomic_load_explicit(&s->target,memory_order_relaxed), peak=0;
    bool meter=atomic_load_explicit(&s->meter,memory_order_relaxed);
    for(unsigned f=0;f<frames;f++) {
        float diff=target-s->current;
        s->current+=fminf(s->step,fmaxf(-s->step,diff));
        for(unsigned c=0;c<nc;c++) {
            float *src=sample(in,c,f), *dst=sample(out,c,f);
            if(!src || !dst) { atomic_store(&s->failed,true); continue; }
            float value=isfinite(*src) ? *src*s->current : 0;
            *dst=value;
            if(meter) peak=fmaxf(peak,fabsf(value));
        }
    }
    if(meter) {
        float old=atomic_load_explicit(&s->peak,memory_order_relaxed);
        // Single producer; losing one peak to a simultaneous UI read is harmless.
        atomic_store_explicit(&s->peak,fmaxf(old,peak),memory_order_relaxed);
    }
    return noErr;
}

OSStatus ConchRenderInstall(AudioObjectID device, ConchRender *state, AudioDeviceIOProcID *io) { return AudioDeviceCreateIOProcID(device, ConchRenderIO, state, io); }
