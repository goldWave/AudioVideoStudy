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

#define K_INPUT_BUS 1   //麦克风
#define K_OUTPUT_BUS 0 //扬声器 speaker

/**
 
 Audio unit 采集必须配合  CoreAudio 才行
 1. 设备切换及获取和设备有关的信息，比如采样率，channel 等，必须通过coreAudio的API
 
 */

/**
 采集声音是监听 input 端
 比如麦克风
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
- (instancetype)init {
    self = [super init];
    _isRunning = false;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stop) name:JBStopNotification object:nil];
    return  self;
}

static AudioObjectPropertyAddress audioObject_makeInputPropertyAddress(AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeInput,
        kAudioObjectPropertyElementMain,
    };
    return address;
}
static NSString *audioObject_getStringProperty(AudioDeviceID deviceID, AudioObjectPropertySelector selector)
{
    AudioObjectPropertyAddress address = audioObject_makeInputPropertyAddress(selector);
    CFStringRef prop;
    UInt32 size = sizeof(prop);
    OSStatus status = AudioObjectGetPropertyData(deviceID, &address, 0, NULL,  &size, &prop);
    if (status != noErr) {
        return [NSString stringWithFormat:@"not found property, deviceID:%i code: \"%s\" (%d)", deviceID, FourCC2Str(status), status];
    }
    return (__bridge_transfer NSString *)prop;
}

static bool isAudioInputDevice(AudioDeviceID deviceID) {
    
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyStreams,
        kAudioObjectPropertyScopeInput,
        kAudioObjectPropertyElementMain,
    };
    UInt32 inputStreamCount;
    JBAssertNoError(AudioObjectGetPropertyDataSize(deviceID,
                                                   &address,
                                                   0,
                                                   NULL,
                                                   &inputStreamCount),
                    @"AudioObjectGetPropertyDataSize kAudioObjectSystemObject kAudioDevicePropertyStreams kAudioObjectPropertyScopeInput");
    return  inputStreamCount > 0;
}

static AudioDeviceID getMyAudioInputDevice() {
    
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, //kAudioObjectPropertyScopeGlobal 和 input 结构一样的？
        kAudioObjectPropertyElementMain,
    };
    
    UInt32 size;
    JBAssertNoError(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                   &address,
                                   0,
                                   NULL,
                                   &size),
                    @"AudioObjectGetPropertyDataSize kAudioObjectSystemObject kAudioHardwarePropertyDevices");
    
    int count = size/sizeof(AudioDeviceID);
    AudioDeviceID deviceIDs[count];
    JBAssertNoError(AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                               &address,
                                               0,
                                               NULL,
                                               &size,
                                               &deviceIDs),
                    @"AudioObjectGetPropertyData kAudioObjectSystemObject kAudioHardwarePropertyDevices");
    
    NSMutableArray *inputS = @[].mutableCopy;
    NSMutableArray *outputS = @[].mutableCopy;
    AudioDeviceID selectID = 0;
    for(int i = 0; i< count; i++) {
        AudioDeviceID dID = deviceIDs[i];
        NSString *name = audioObject_getStringProperty(dID, kAudioDevicePropertyDeviceNameCFString);
        BOOL isInput = isAudioInputDevice(dID);
        NSString *str =  [NSString stringWithFormat:@"%@ device, id: %i\t name:%@", (isInput ? @"输入" : @"非输入"), dID, name];
        if (isInput) {
            if ([name containsString:@"麦克风"]) {
//            if ([name containsString:@"EDIFIER"]) {
                NSLog(@"选择的输入设备为: %@", name);
                selectID = dID;
            }
            [inputS addObject:str];
        } else {
            [outputS addObject:str];
        }
    }
    printf("%s\n\n", [inputS componentsJoinedByString:@"\n"].UTF8String);
    printf("%s\n\n", [outputS componentsJoinedByString:@"\n"].UTF8String);
    
    return  selectID;
}


static OSStatus JBAURenderCallback(void *                            inRefCon,
                                   AudioUnitRenderActionFlags *    ioActionFlags,
                                   const AudioTimeStamp *            inTimeStamp,
                                   UInt32                            inBusNumber,
                                   UInt32                            inNumberFrames,
                                   AudioBufferList * __nullable    ioData) { //ioData 可以处理耳返，将采集到声音，输出到耳机里面去
    
//    NSLog(@"JBAURenderCallback enter");
    JBAudioUnitCapture * captureCls = (__bridge JBAudioUnitCapture *)inRefCon;
    // 将获取到的 音频数据 渲染塞入 captureCls->_bufList 中
    //回调函数中调用AudioUnitRender，来向上一级unit申请数据（上一级unit的回调函数就会响应
    // 拉模式，向上级拉数据
    JBAssertNoError(AudioUnitRender(captureCls->_audioUnit,
                                    ioActionFlags,
                                    inTimeStamp,
                                    inBusNumber,
                                    inNumberFrames,
                                    captureCls->_bufList),
                    @"AudioUnitRender");
    
    for(int i = 0; i< captureCls->_bufList->mNumberBuffers; i++ ) {
        [[JBFileManager shareInstance] writeAudioPCM:captureCls->_bufList->mBuffers->mData buffersize:captureCls->_bufList->mBuffers->mDataByteSize];
    }
//    ioData = captureCls->_bufList;
    //    for(int i = 0; i< captureCls->_bufList->mNumberBuffers; i++ ) {
    //        [[JBFileManager shareInstance] writeAudioPCM:captureCls->_bufList->mBuffers->mData buffersize:captureCls->_bufList->mBuffers->mDataByteSize];
    //    }
    
    //    if (ioData) {
    //        NSLog(@"JBAURenderCallback enter");
    //        for(int i = 0; i< ioData->mNumberBuffers; i++ ) {
    //            [[JBFileManager shareInstance] writeAudioPCM:ioData->mBuffers->mData buffersize:ioData->mBuffers->mDataByteSize];
    //        }
    //    }
    
    return 0;
}

- (void)setupData {

//    self.audioConfigData = [[JBConfigData alloc] init];
//    self.audioConfigData.type = JBCaptureTypeAudio;
    UInt32  size= 0;
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
    AudioComponentDescription desc = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput//kAudioUnitSubType_HALOutput
    };
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
    JBAssertNoError(AudioComponentInstanceNew(inputComponent, &_audioUnit),
                    @"AudioComponentInstanceNew");
    
    /*
     (type == IO_TYPE_INPUT) ? SCOPE_INPUT : SCOPE_OUTPUT,
     (type == IO_TYPE_INPUT) ? BUS_INPUT : BUS_OUTPUT
     */
    /*
     @constant        kAudioOutputUnitProperty_EnableIO
     @discussion            Scope: { scope output, element 0 = output } { scope input, element 1 = input }
     Value Type: UInt32
     Access: read/write
     Output units default to output-only operation. Host applications may disable
     output or enable input operation using this property, if the output unit
     supports it. 0=disabled, 1=enabled using I/O proc.
     后面不需要单独设置，enable output 和 input，只要这个
     
     */
    // 允许麦克风输入
    UInt32 enable_input = 1;
    JBAssertNoError(AudioUnitSetProperty(_audioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Input,
                                         K_INPUT_BUS,
                                         &enable_input,
                                         sizeof(enable_input)),
                    @"kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Input");
    
    //禁止麦克风输出，也不能输出
    UInt32 enable_output = 0;
    JBAssertNoError(AudioUnitSetProperty(_audioUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Output,
                                         K_OUTPUT_BUS,
                                         &enable_output,
                                         sizeof(enable_output)),
                    @"kAudioOutputUnitProperty_EnableIO kAudioUnitScope_Output");
    
    
    //    AudioStreamBasicDescription asbd1 = {0};
    //    UInt32  size1=sizeof(asbd1);
    //    status = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, K_INPUT_BUS, &asbd1, &size1);
    //    printErr(@"AudioUnitGetProperty size error:", status);
    //    [JBFileManager  printASBD:asbd1];
    //    [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:asbd1 preLog:@"原始音频："];
    
    //必须手动设置输入设备，不然默认的有可能是输出设置，导致流程中断，
    //必须在前面 kAudioOutputUnitProperty_EnableIO 配置完成后设置 这个值才行，不然会出错
    AudioDeviceID selectDeviceID = getMyAudioInputDevice();
    JBAssertNoError(AudioUnitSetProperty(_audioUnit,
                                         kAudioOutputUnitProperty_CurrentDevice, //注释写了搭配kAudioUnitScope_Global
                                         kAudioUnitScope_Global,
                                         0,
                                         &selectDeviceID,
                                         sizeof(AudioDeviceID)),
                    @"AudioUnitSetProperty kAudioOutputUnitProperty_CurrentDevice selectDeviceID");
    
    
    AudioDeviceID outputDeviceID = 0;
    size = sizeof(outputDeviceID);
    JBAssertNoError(AudioUnitGetProperty(_audioUnit,
                                         kAudioOutputUnitProperty_CurrentDevice,
                                         kAudioUnitScope_Global,
                                         0,
                                         &outputDeviceID,
                                         &size),
                    @"kAudioOutputUnitProperty_CurrentDevice");
    
    NSString *inputDevice = audioObject_getStringProperty(outputDeviceID, kAudioDevicePropertyDeviceNameCFString);
    NSLog(@"当前输入设备 id: %d\t name is: %@",outputDeviceID, inputDevice);
    

    //    /**
    //     千万千万要注意的一点是：这里是通过element是否是输入还是输出来决定这个I/O单元是用来输入还是输出的，而不是通过scope来决定的
    //     */
    
    //回调
    AURenderCallbackStruct callback;
    callback.inputProc = JBAURenderCallback;
    callback.inputProcRefCon = (__bridge void *)self;
    //    status = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, K_INPUT_BUS, &callback, sizeof(callback));
    JBAssertNoError(AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(callback)), @"AudioUnitSetProperty kAudioOutputUnitProperty_SetInputCallback");
    

    AudioStreamBasicDescription asbd = {0};
    size=sizeof(asbd);
    JBAssertNoError(AudioUnitGetProperty(_audioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Input, //The context for audio data coming into an audio unit. 进入audio unit 的数据
                                         K_INPUT_BUS,
                                         &asbd,
                                         &size),
                    @"AudioUnitGetProperty kAudioUnitProperty_StreamFormat asbd");
    [JBFileManager  printASBD:asbd];
    
    //取消plannar 输出，不然Audiolist 需要特殊配置
    asbd.mFormatFlags &= ~ kAudioFormatFlagIsNonInterleaved;
    JBAssertNoError(AudioUnitSetProperty(_audioUnit,
                                         kAudioUnitProperty_StreamFormat,
                                         kAudioUnitScope_Output, //离开audio unit的数据
                                         K_INPUT_BUS,
                                         &asbd,
                                         size),
                    @"AudioUnitSetProperty kAudioUnitProperty_StreamFormat asbd")
    [JBFileManager  printASBD:asbd];
    [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:asbd preLog:@"原始音频："];
    
    
    

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
    UInt32 perferredBufferSize = (20 * asbd.mSampleRate) / 1000; //bytes
    size = sizeof(perferredBufferSize);
    JBAssertNoError(AudioUnitSetProperty(_audioUnit,
                                         kAudioDevicePropertyBufferFrameSize,
                                         kAudioUnitScope_Global,
                                         0,
                                         &perferredBufferSize,
                                         size),
                    @"AudioUnitSetProperty kAudioDevicePropertyBufferFrameSize");
    
    //AudioUnitGetPropertyInfo 用于 检查属性是否可用 ？
    JBAssertNoError(AudioUnitGetProperty(_audioUnit,
                                         kAudioDevicePropertyBufferFrameSize,
                                         kAudioUnitScope_Global,
                                         0,
                                         &perferredBufferSize,
                                         &size),
                    @"AudioUnitGetProperty kAudioDevicePropertyBufferFrameSize");
    
    

    
    [self createAudioListBuffer:outputDeviceID];
    
    JBAssertNoError(AudioUnitInitialize(_audioUnit),@"AudioUnitInitialize");
    
}

/**
 创建自己的buffer list 来存储 采集到的 音频数据
 */
- (void)createAudioListBuffer:(AudioDeviceID) deviceID {
    

//
//    UInt32 frame = 0;
//    UInt32 size = sizeof(frame);
//    JBAssertNoError(AudioUnitGetProperty(_audioUnit,
//                                         kAudioDevicePropertyBufferFrameSize,
//                                         kAudioUnitScope_Global,
//                                         0,
//                                         &frame,
//                                         &size),
//                    @"AudioUnitGetProperty kAudioDevicePropertyBufferFrameSize");
    
    UInt32 size = 0;
    AudioObjectPropertyAddress address = audioObject_makeInputPropertyAddress(kAudioDevicePropertyStreamConfiguration);
    UInt32 buffer_size = 0;
    JBAssertNoError(AudioObjectGetPropertyDataSize(deviceID,
                                                   &address,
                                                   0,
                                                   NULL,
                                                   &buffer_size),
                    @"AudioObjectGetPropertyDataSize kAudioDevicePropertyStreamConfiguration");
    
    _bufList = malloc(buffer_size);
    JBAssertNoError(AudioObjectGetPropertyData(deviceID,
                                               &address,
                                               0,
                                               NULL,
                                               &buffer_size,
                                               _bufList),
                    @"AudioObjectGetPropertyData kAudioDevicePropertyStreamConfiguration");
        
    for(UInt32 i = 0; i< _bufList->mNumberBuffers; i++) {
        size = _bufList->mBuffers[i].mDataByteSize;
        _bufList->mBuffers[i].mData = malloc(size);
    }
}

- (BOOL)start {
    
    if (self.isRunning) {
        NSLog(@"Audio Recorder: Start recorder repeat");
        return NO;
    }
    self.isRunning = YES;
    [self setupData];
    
    JBAssertNoError(AudioOutputUnitStart(_audioUnit),@"AudioOutputUnitStartt");
    
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
    [self stop];
    
}

- (void)stop {
    if (!self.isRunning) {
        return;
    }
    self.isRunning = NO;
    
    JBAssertNoError(AudioOutputUnitStop(_audioUnit),@"AudioOutputUnitStartt");
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
