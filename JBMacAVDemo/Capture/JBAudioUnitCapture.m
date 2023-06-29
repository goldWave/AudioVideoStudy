//
//  JBAudioUnitCapture.m
//  JBMacAVDemo
//
//  Created by jimbo on 2023/6/26.
//

#import "JBAudioUnitCapture.h"
#import <AudioUnit/AudioUnit.h>
#import <CoreAudio/CoreAudio.h>
#import "JBFileManager.h"

#define K_INPUT_BUS 1

@interface JBAudioUnitCapture() {
    AudioComponentInstance _audioUnit;
}

@property(nonatomic, assign)  BOOL isRunning;
@end

@implementation JBAudioUnitCapture
+ (instancetype)shareInstance {
    
    static JBAudioUnitCapture *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[JBAudioUnitCapture alloc] init];
 
    });
    return instance;
}

static OSStatus JBAURenderCallback(    void *                            inRefCon,
                                   AudioUnitRenderActionFlags *    ioActionFlags,
                                   const AudioTimeStamp *            inTimeStamp,
                                   UInt32                            inBusNumber,
                                   UInt32                            inNumberFrames,
                                   AudioBufferList * __nullable    ioData) {
    if (ioData) {
        NSLog(@"JBAURenderCallback enter");
        for(int i = 0; i< ioData->mNumberBuffers; i++ ) {
            [[JBFileManager shareInstance] writeAudioPCM:ioData->mBuffers->mData buffersize:ioData->mBuffers->mDataByteSize];
        }
    }
    return 0;
}

- (void)setupData {
    self.audioConfigData = [[JBConfigData alloc] init];
    self.audioConfigData.type = JBCaptureTypeAudio;
    
    /**
     * https://cz-it.gitbooks.io/play-and-record-with-coreaudio/content/audiounit/howto.html
     * 查看type 类型描述 及 其他讲解
     */
    /**
     componentSubType 除了下面的几个，还有其他类型

     CF_ENUM(UInt32) {
         kAudioUnitSubType_HALOutput                = 'ahal',
         kAudioUnitSubType_DefaultOutput            = 'def ',
         kAudioUnitSubType_SystemOutput            = 'sys ',
     };
     */
    
    //单独创建AudioUnit
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    //可以从系统中获取到符合描述条件的组件。这里“inComponent”可以认为是一个链表
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    //在得到Component以后就可以创建我们的AudioUnit了
    /**
     两种方式创建AudioUnit. 获取到的AudioUnit都是同一个对象
     1. 就是我们代码中使用的这种，AudioComponentDescription 去找到 AudioComponent， 然后通过AudioComponent创建
     2. NewAUGraph创建一个AUGraph， 然后AUGraphAddNode传入AUGraph及AudioComponentDescription， 得到AUNode。 通过AUGraphNodeInfo获取到AudioUnit
     */
    OSStatus status = AudioComponentInstanceNew(inputComponent, &_audioUnit);
    printErr(@"AudioComponentInstanceNew error:", status);


    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = 44100;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = 2;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = 2;
    asbd.mChannelsPerFrame = 1;
    asbd.mBitsPerChannel = 16;
    
    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd, sizeof(asbd));
    printErr(@"AudioUnitSetProperty kAudioUnitProperty_StreamFormat error:", status);
    
    //回调
    AURenderCallbackStruct callback;
    callback.inputProc = JBAURenderCallback;
    callback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, K_INPUT_BUS, &callback, sizeof(callback));
    printErr(@"AudioUnitSetProperty kAudioOutputUnitProperty_SetInputCallback error:", status);
    
    UInt32 perferredBufferSize = (20 * asbd.mSampleRate) / 1000; //bytes
    UInt32 size = sizeof(perferredBufferSize);
    
    //啥意思，set 后 get
    status = AudioUnitSetProperty(_audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &perferredBufferSize, size);
    printErr(@"AudioUnitSetProperty kAudioDevicePropertyBufferFrameSize error:", status);
    
    status = AudioUnitGetProperty(_audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &perferredBufferSize, &size);
    printErr(@"AudioUnitGetProperty kAudioDevicePropertyBufferFrameSize error:", status);

    size=sizeof(asbd);
    status = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd, &size);
    printErr(@"AudioUnitGetProperty size error:", status);

    [[JBFileManager shareInstance] printASBD:asbd];
    [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:asbd preLog:@"原始音频："];

    status = AudioUnitInitialize(_audioUnit);
    printErr(@"AudioUnitInitialize error:", status);

}

- (BOOL)startAudioCapture {
    
    if (self.isRunning) {
        NSLog(@"Audio Recorder: Start recorder repeat");
        return NO;
    }
    [self setupData];
    
    OSStatus  status  = AudioOutputUnitStart(_audioUnit);
    printErr(@"AudioOutputUnitStartt error:", status);
//    //启动audio queue , 第二个参数设置为NULL表示立即开始采集数据.
//    OSStatus  status = AudioQueueStart(_mQueue, NULL);
//    if (status != noErr) {
//        NSLog(@"Audio Recorder: Audio Queue Start failed status:%d \n",(int)status);
//        return NO;
//    }else {
//        NSLog(@"Audio Recorder: Audio Queue Start successful");
//        self.isRunning = YES;
//        return YES;
//    }
    return YES;
}

- (void)dealloc {
    [self stopAudioCapture];
    
}

- (void)stopAudioCapture {
    if (!self.isRunning) {
        return;
    }
    self.isRunning = NO;
    
    OSStatus  status  = AudioOutputUnitStop(_audioUnit);
    printErr(@"AudioOutputUnitStartt error:", status);
//    if (_mQueue)
//    {
//        OSStatus status  = AudioQueueStop(_mQueue, true);
//        if(status  == noErr) {
//            for (int i = 0; i < KNumberBuffers ; i++){
//                AudioQueueFreeBuffer(_mQueue, _mBuffers[i]);
//            }
//        } else {
//            NSLog(@"停流出问题了");
//        }
//
//        status = AudioQueueDispose(_mQueue, true);
//        if (status != noErr) {
//            NSLog(@"Audio Recorder: Dispose failed: %d",status);
//            return;
//        }else {
//            _mQueue = NULL;
//            NSLog(@"Audio Recorder: stop AudioQueue successful.");
//        }
//    }
}

- (BOOL)getIsRunning {
    return _isRunning;
}
@end
