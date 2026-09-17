#include "Realtime.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    float input[1024], output[1024];
    for(int i=0;i<1024;i++) input[i]=0.8f;
    AudioBufferList in={.mNumberBuffers=1,.mBuffers={{2,sizeof(input),input}}};
    AudioBufferList out={.mNumberBuffers=1,.mBuffers={{2,sizeof(output),output}}};
    ConchRender *s=ConchRenderCreate(48000,0.5); assert(s);
    ConchRenderSetMetering(s,true);
    ConchRenderIO(0,NULL,&in,NULL,&out,NULL,s);
    assert(fabsf(output[1023]-0.4f)<0.00001);
    assert(fabsf(ConchRenderTakePeak(s)-0.4f)<0.00001);
    assert(ConchRenderTakePeak(s)==0);
    ConchRenderSetGain(s,0);
    ConchRenderIO(0,NULL,&in,NULL,&out,NULL,s);
    assert(output[0]>0 && output[1023]==0); // ramp, then exact silence
    ConchRenderSetGain(s,0.5);
    ConchRenderIO(0,NULL,&in,NULL,&out,NULL,s);
    assert(fabsf(output[1023]-0.4f)<0.00001);
    ConchRenderSetMetering(s,false);
    input[0]=NAN;
    ConchRenderIO(0,NULL,&in,NULL,&out,NULL,s);
    assert(output[0]==0 && ConchRenderTakePeak(s)==0);
    assert(!ConchRenderFailed(s) && ConchRenderTicks(s)==4);
    in.mBuffers[0].mDataByteSize=4;
    ConchRenderIO(0,NULL,&in,NULL,&out,NULL,s);
    assert(ConchRenderFailed(s));
    ConchRenderDestroy(s);
    float left[512], right[512];
    struct { UInt32 count; AudioBuffer buffers[2]; } planar = {2, {{1,sizeof(left),left},{1,sizeof(right),right}}};
    in.mBuffers[0].mDataByteSize=sizeof(input); input[0]=0.8f;
    s=ConchRenderCreate(48000,0.5);
    ConchRenderIO(0,NULL,&in,NULL,(AudioBufferList*)&planar,NULL,s);
    assert(fabsf(left[511]-0.4f)<0.00001 && fabsf(right[511]-0.4f)<0.00001);
    assert(!ConchRenderFailed(s)); ConchRenderDestroy(s);
    puts("Realtime: gain, ramp, mute, restore, metering, NaN and short-buffer tests passed");
}
