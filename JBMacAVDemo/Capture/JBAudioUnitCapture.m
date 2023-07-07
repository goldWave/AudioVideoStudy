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

#define K_INPUT_BUS 1   // 麦克风
#define K_OUTPUT_BUS 0 //扬声器 speaker

/**
 
 Audio unit 采集必须配合  CoreAudio 才行
 1. 设备切换及获取和设备有关的信息，比如采样率，channel 等，必须通过coreAudio的API
 
 */

@interface JBAudioUnitCapture() {
    @public
    AudioComponentInstance _audioUnit;
    AudioBufferList *_bufList;
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

static AudioObjectPropertyAddress audioObject_makeOutputPropertyAddress(AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain,
        
    };
    return address;
}
static NSString *audioObject_getStringProperty(AudioDeviceID deviceID, AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = audioObject_makeOutputPropertyAddress(selector);
    CFStringRef prop;
    UInt32 size = sizeof(prop);
    OSStatus status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL,  &size, &prop);
    if (status != noErr) {
        return [NSString stringWithFormat:@"not found property, deviceID:%i code: \"%s\" (%d)", deviceID, FourCC2Str(status), status];
    }
    return (__bridge_transfer NSString *)prop;
}


static OSStatus JBAURenderCallback(void *                            inRefCon,
                                   AudioUnitRenderActionFlags *    ioActionFlags,
                                   const AudioTimeStamp *            inTimeStamp,
                                   UInt32                            inBusNumber,
                                   UInt32                            inNumberFrames,
                                   AudioBufferList * __nullable    ioData) {
    
    
    JBAudioUnitCapture * captureCls = (__bridge JBAudioUnitCapture *)inRefCon;
    
    // -10876 kAudioUnitErr_NoConnection
    OSStatus status = AudioUnitRender(captureCls->_audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, captureCls->_bufList);
    printErr(@"AudioUnitRender error:", status);
    for(int i = 0; i< captureCls->_bufList->mNumberBuffers; i++ ) {
        [[JBFileManager shareInstance] writeAudioPCM:captureCls->_bufList->mBuffers->mData buffersize:captureCls->_bufList->mBuffers->mDataByteSize];
    }
    
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
     Mac
     componentSubType 除了下面的几个，还有其他类型
     CF_ENUM(UInt32) {
         kAudioUnitSubType_HALOutput                = 'ahal', //mac 所有的音频设备
         kAudioUnitSubType_DefaultOutput            = 'def ', //HALOutput 里面的 用户选择的默认 音频设备
         kAudioUnitSubType_SystemOutput            = 'sys ', //HALOutput 里面输出系统警告音之类的设备
     };
     
     
     ios：
     kAudioUnitSubType_RemoteIO 获取输入输出
     
     ---
     通用：
     kAudioUnitSubType_VoiceProcessingIO 回音消除，去除啸声
     */
    
    //单独创建AudioUnit
    
    //简洁c 写法
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput
    };
    /*
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
     */
    
    //可以从系统中获取到符合描述条件的组件。这里“inComponent”可以认为是一个链表
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    if (!inputComponent) {
        NSLog(@"AudioComponentFindNext failed");
    }
    //在得到Component以后就可以创建我们的AudioUnit了
    /**
     两种方式创建AudioUnit. 获取到的AudioUnit都是同一个对象
     1. 就是我们代码中使用的这种，AudioComponentDescription 去找到 AudioComponent， 然后通过AudioComponent创建
     2. NewAUGraph创建一个AUGraph， 然后AUGraphAddNode传入AUGraph及AudioComponentDescription， 得到AUNode。 通过AUGraphNodeInfo获取到AudioUnit
     */
    OSStatus status = AudioComponentInstanceNew(inputComponent, &_audioUnit);
    printErr(@"AudioComponentInstanceNew error:", status);
    NSLog(@"11----");
    
    /*
     (type == IO_TYPE_INPUT) ? SCOPE_INPUT : SCOPE_OUTPUT,
    (type == IO_TYPE_INPUT) ? BUS_INPUT : BUS_OUTPUT
     */
    // 允许麦克风输入
    bool enable_input = true;
    status =AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, K_INPUT_BUS, &enable_input, sizeof(enable_input));
    printErr(@"kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Input error:", status);
    
    //禁止麦克风输出，也不能输出
    bool enable_output = false;
    status =AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, K_OUTPUT_BUS, &enable_output, sizeof(enable_output));
    printErr(@"kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Output error:", status);

    AudioStreamBasicDescription asbd1 = {0};
    UInt32  size1=sizeof(asbd1);
    status = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd1, &size1);
    printErr(@"AudioUnitGetProperty size error:", status);
    [[JBFileManager shareInstance] printASBD:asbd1];
    [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:asbd1 preLog:@"原始音频："];
    
    
    
    AudioStreamBasicDescription asbd = {0};
//    asbd.mSampleRate = 44100;
//    asbd.mFormatID = kAudioFormatLinearPCM;
//    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
//    asbd.mBytesPerPacket = 4;
//    asbd.mFramesPerPacket = 1;
//    asbd.mBytesPerFrame = 4;
//    asbd.mChannelsPerFrame = 2;
//    asbd.mBitsPerChannel = 32;
//
//    /**
//     千万千万要注意的一点是：这里是通过element是否是输入还是输出来决定这个I/O单元是用来输入还是输出的，而不是通过scope来决定的
//     */
//    status = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd, sizeof(asbd));
//    printErr(@"AudioUnitSetProperty kAudioUnitProperty_StreamFormat error:", status);
    
    //回调
    AURenderCallbackStruct callback;
    callback.inputProc = JBAURenderCallback;
    callback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, K_INPUT_BUS, &callback, sizeof(callback));
    printErr(@"AudioUnitSetProperty kAudioOutputUnitProperty_SetInputCallback error:", status);
    
    UInt32 perferredBufferSize = (20 * asbd.mSampleRate) / 1000; //bytes
    UInt32 size = sizeof(perferredBufferSize);
    
    
    /**
     https://cz-it.gitbooks.io/play-and-record-with-coreaudio/content/audiounit/images/audio_unit_structure.png
     如图所示，一个AudioUnit由scopes和elements组成。可以认为Scope是AudioUnit的一个组成方面，而Element则也是一个组成方面，
     也就是从两个方面来看待。每个Unit都有一个输入scope和一个输出scope，输入scope用于向Unit中输入数据，
     有了输入自然还有个输出，输出处理的数据。我们可以将他们相信成坐标系上的X/Y坐标，由他们来指定一个具体的对象。
     */
    
    /**
      kAudioUnitScope_Global ：1）作用于整个音频单元，不作用音频流；2）只有一个element0元素
      kAudioUnitScope_Input和kAudioUnitScope_Output：作用在输入输出scope的元素称为bus，总线
      */
    
    status = AudioUnitSetProperty(_audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &perferredBufferSize, size);
    printErr(@"AudioUnitSetProperty kAudioDevicePropertyBufferFrameSize error:", status);
    
    //AudioUnitGetPropertyInfo 用于 检查属性是否可用 ？
    status = AudioUnitGetProperty(_audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &perferredBufferSize, &size);
    printErr(@"AudioUnitGetProperty kAudioDevicePropertyBufferFrameSize error:", status);

    size=sizeof(asbd);
    status = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd, &size);
    printErr(@"AudioUnitGetProperty size error:", status);

    [[JBFileManager shareInstance] printASBD:asbd];
    [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:asbd preLog:@"原始音频："];
    
    AudioDeviceID outputDeviceID = 0;
    size = sizeof(outputDeviceID);
    status = AudioUnitGetProperty(_audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &outputDeviceID, &size);
    printErr(@"kAudioOutputUnitProperty_CurrentDevice error:", status);
    
    NSString *inputDevice = audioObject_getStringProperty(outputDeviceID, kAudioDevicePropertyDeviceNameCFString);
    NSLog(@"current input device name is: %@", inputDevice);
    
    [self createAudioListBuffer:outputDeviceID];
    
    status = AudioUnitInitialize(_audioUnit);
    printErr(@"AudioUnitInitialize error:", status);
    
}

/**
 创建自己的buffer list 来存储 采集到的 音频数据
 */
- (void)createAudioListBuffer:(AudioDeviceID) deviceID {
    
    AudioObjectPropertyAddress address = audioObject_makeOutputPropertyAddress(kAudioDevicePropertyStreamConfiguration);
    UInt32 buffer_size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL,  &buffer_size);
    printErr(@"AudioObjectGetPropertyDataSize kAudioDevicePropertyStreamConfiguration error:", status);
    
    UInt32 frame = 0;
    UInt32 size = sizeof(frame);
    status = AudioUnitGetProperty(_audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frame, &size);
    printErr(@"AudioUnitGetProperty kAudioDevicePropertyBufferFrameSize error:", status);
    
    _bufList = malloc(buffer_size);
    
    status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL, &buffer_size, _bufList);
    printErr(@"AudioObjectGetPropertyData kAudioDevicePropertyStreamConfiguration error:", status);
    
    if(status != noErr) {
        free(_bufList);
        _bufList = NULL;
        return;
    }
    
    for(UInt32 i = 0; i< _bufList->mNumberBuffers; i++) {
        size = _bufList->mBuffers[i].mDataByteSize;
        _bufList->mBuffers[i].mData = malloc(size);
    }
}

- (BOOL)startAudioCapture {
    
    if (self.isRunning) {
        NSLog(@"Audio Recorder: Start recorder repeat");
        return NO;
    }
    [self setupData];
    
    OSStatus  status  = AudioOutputUnitStart(_audioUnit);
    printErr(@"AudioOutputUnitStartt error:", status);
    NSLog(@"---- startAudioCapture ----");
    
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
