//
//  JBAudioQueueCapture.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/8.
//

#import "JBAudioQueueCapture.h"
#import <AVFoundation/AVFoundation.h>
#import "JBFileManager.h"

const static int KNumberBuffers = 3;
@interface JBAudioQueueCapture()  {
    AudioStreamBasicDescription _mDataFormat;
    AudioQueueRef _mQueue;
    AudioQueueBufferRef _mBuffers[KNumberBuffers];
}
@property(nonatomic, assign)  BOOL isRunning;
@end

/**
 如果不是写入 pcm 数据的话，
 需要 写入 metadata 信息， 这个信息在 这里 可以被称为magic cookie.
 
 首先获取到  queue 里面默认保存的 这个格式音频的 magic cookie。 比如 .acf 或者 .aac 的 metadata信息
 然后 使用 AudioFile 获取 C的 File 将这段 char * 写到硬盘中去。
 
 
 void CopyEncoderCookieToFile(AudioQueueRef queue, AudioFileID fileHandle) {
   UInt32 propertyValueSize = 0;
   CheckError(AudioQueueGetPropertySize(queue,
                                        kAudioQueueProperty_MagicCookie,
                                        &propertyValueSize), "Getting the size of the value of the Audio Queue property kAudioConverterCompressionMagicCookie");
   if (propertyValueSize > 0) {
     UInt8 *magicCookie = (UInt8 *)malloc(propertyValueSize);
     CheckError(AudioQueueGetProperty(queue,
                                      kAudioQueueProperty_MagicCookie,
                                      (void *)magicCookie,
                                      &propertyValueSize), "Getting the value of the Audio Queue property kAudioQueueProperty_MagicCookie");
     
     CheckError(AudioFileSetProperty(fileHandle,
                                     kAudioFilePropertyMagicCookieData,
                                     propertyValueSize,
                                     magicCookie
                                     ), "Setting the AudioFile property kAudioFilePropertyMagicCookieData");
     free(magicCookie);
   }
 }
 */


@implementation JBAudioQueueCapture

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

// 获取默认输出设备的 标准采样率
void GetDefaultInputDeviceSampleRate(Float64 *normalSampleRate) {
    AudioObjectPropertyAddress propertyAddress;
    
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0; // master element
    
    AudioDeviceID deviceID = 0;
    UInt32 propertySize = sizeof(AudioDeviceID);
    
    OSStatus status =  AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                  &propertyAddress,
                                                  0,
                                                  NULL,
                                                  &propertySize,
                                                  &deviceID);
    
    NSLog(@"input device id: %i", deviceID);
    
    NSString *inputDevice = audioObject_getStringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString);
    NSLog(@"input device: %@", inputDevice);
    
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate;
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement = 0;
    
    UInt32 size = sizeof(Float64);
    status =  AudioObjectGetPropertyData(deviceID,
                                         &propertyAddress,
                                         0,
                                         NULL,
                                         &size,
                                         normalSampleRate);
}

+ (instancetype)shareInstance {
    
    static JBAudioQueueCapture *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[JBAudioQueueCapture alloc] init];
 
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    _isRunning = false;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stop) name:JBStopNotification object:nil];
    return  self;
}

- (BOOL)startAudioCapture {
    
    if (self.isRunning) {
        NSLog(@"Audio Recorder: Start recorder repeat");
        return NO;
    }
    [self configureAudioCaptureWithDurationSec:0.05];
    
    //启动audio queue , 第二个参数设置为NULL表示立即开始采集数据.
    OSStatus  status = AudioQueueStart(_mQueue, NULL);
    if (status != noErr) {
        NSLog(@"Audio Recorder: Audio Queue Start failed status:%d \n",(int)status);
        return NO;
    }else {
        NSLog(@"Audio Recorder: Audio Queue Start successful");
        self.isRunning = YES;
        return YES;
    }
}

// 开始音频后的回调
/**
 所以使用三个缓冲区，多一个进行备用。
 当缓冲区被填满后，它就会被交给我们的回调函数。当我们的回调函数处理缓冲区的内容时，同时对麦克风音频进行采样。这意味着Core Audio需要将这些新样本保存到新的缓冲区中。MyAQInputCallback换句话说，当我们的函数正在处理已经移交的缓冲区内容时，我们至少需要多一个缓冲区供Core Audio写入数据。
 */
static void captureAudioDataCallback(void *__nullable  inUserData,
                                     AudioQueueRef  inAQ,
                                     AudioQueueBufferRef  inBuffer,
                                     const AudioTimeStamp * inStartTime,
                                     UInt32 inNUmerPacketDescriptions,
                                     const AudioStreamPacketDescription * __nullable inPacketDescs) {
    /**
     inUserData: 自定义的数据,开发者可以传入一些我们需要的数据供回调函数使用.注意:一般情况下我们需要将当前的OC类实例传入,因为回调函数是纯C语言,不能调用OC类中的属性与方法,所以传入OC实例以与本类中属性方法交互.
     inAQ: 调用回调函数的音频队列
     inBuffer: 装有音频数据的audio queue buffer.
     inStartTime: 当前音频数据的时间戳.主要用于同步.
     inNumberPacketDescriptions: 数据包描述参数.如果你正在录制VBR格式,音频队列会提供此参数的值.如果录制文件需要将其传递给AudioFileWritePackets函数.CBR格式不使用此参数.
     inPacketDescs: 音频数据中一组packet描述.如果是VBR格式数据,如果录制文件需要将此值传递给AudioFileWritePackets函数， 见本方法最后注释
     */
    
    
    JBAudioQueueCapture *capture = (__bridge JBAudioQueueCapture *)inUserData;
    if (capture.delegate) {
        void *bufferData = inBuffer->mAudioData;
        UInt32 buffersize = inBuffer->mAudioDataByteSize;

        //将最后的采集数据拷贝出去后，进行下一步的写入文件  和 进行编码
        void *tmpBuffer = malloc(buffersize);
        memcpy(tmpBuffer, bufferData, buffersize);
        [capture.delegate capturedData:tmpBuffer buffersize:buffersize];
    }
        
    if ([capture getIsRunning]) {
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
    /**
     AudioFileWritePackets 写入实例
     if (inNumberPacketDescriptions > 0) {
        AudioFileWritePackets(recorder->recordFile,
                                         FALSE,
                                         inBuffer->mAudioDataByteSize,
                                         inPacketDescs,
                                         recorder->recordPacket,
                                         &inNumberPacketDescriptions,
                                         inBuffer->mAudioData);
     */
}

//记录 非 PCM，可变比特率的格式如：ACF等，怎么计算单位时间内的所需要开辟的内存大小
int computeRecordBufferSize(const AudioStreamBasicDescription *format, AudioQueueRef queue, float seconds) {
  assert(seconds > 0);
  assert(format->mSampleRate > 0);
  
  int totalNumberOfSamples = seconds * format->mSampleRate;
  int totalNumberOfFrames = (int)ceil(totalNumberOfSamples);
  
  if (format->mBytesPerFrame > 0) {
      //固定比特率的包
    return totalNumberOfFrames * format->mBytesPerFrame;
  }
    
//    可变比特率的格式如：ACF等，计算单位时间内的所需要开辟的内存大小
  UInt32 maxPacketSize = 0;
  
  if (format->mBytesPerPacket > 0) {
    maxPacketSize = format->mBytesPerPacket;
  } else {
    UInt32 propertySize = sizeof(maxPacketSize);
    AudioQueueGetProperty(queue,
                                     kAudioQueueProperty_MaximumOutputPacketSize,
                                     &maxPacketSize,
                                     &propertySize);
  }
  
  int totalNumberOfPackets = 0;
  int numberOfFramesPerPacket = 1;
  
  if (format->mFramesPerPacket > 0) {
    numberOfFramesPerPacket = format->mFramesPerPacket;
  }
  
  totalNumberOfPackets = totalNumberOfFrames / numberOfFramesPerPacket;
    
  // We have number of packets and packet size. Hence we can now get the number of bytes needed.
  return totalNumberOfPackets * maxPacketSize;
}

- (void)configureAudioCaptureWithDurationSec:(float)durationSec
{
    [self setOutputASBD];
    //创建 queue
    OSStatus status = AudioQueueNewInput(&_mDataFormat,
                                         captureAudioDataCallback,
                                         (__bridge void *)(self),
                                         NULL,
                                         kCFRunLoopCommonModes,
                                         0,
                                         &_mQueue);
    if (status != noErr) {
        NSLog(@"crate queue errored. %d", (int)status);
        return;
    }
    
    //设置获取到的音频格式 ASBD, 如果前面 asbd 没有设置完的话，这里会进一步使用 queue 里面的 设置值进行填充？
    UInt32 size = sizeof(_mDataFormat);
    status = AudioQueueGetProperty(_mQueue, kAudioQueueProperty_StreamDescription,  &_mDataFormat, &size);
    if (status != noErr) {
        NSLog(@"get audio ASBD errored. %d", (int)status);
        return;
    }
    
//    //计算Audio Queue 每个buffer 的大小
//    int frames = (int)ceil(durationSec * _mDataFormat.mSampleRate); //采集时间内的 小样本数量
//    //durationSec 的 buffer 大小
//    UInt32 bufferByteSize = frames * _mDataFormat.mBytesPerFrame * _mDataFormat.mChannelsPerFrame;
    
    //durationSec 的 buffer 大小
    UInt32 bufferByteSize = computeRecordBufferSize(&_mDataFormat, _mQueue, durationSec);
    
    //内存分配，入队
    for (int i = 0; i != KNumberBuffers; i++ ){
        status = AudioQueueAllocateBuffer(_mQueue, bufferByteSize, &_mBuffers[i]);
        if (status != noErr) {
            NSLog(@"Audio Recorder: buffer is . %d", (int)status);
        }
        
        status = AudioQueueEnqueueBuffer(_mQueue, _mBuffers[i], 0, NULL);
        if (status != noErr) {
            NSLog(@"Audio Recorder: Enqueue buffer status:%d",(int)status);
        }
    }
    
}
//初始化 ASBD
- (void)setOutputASBD {
    AudioStreamBasicDescription dataFormat = {0};
    
    Float64 sampleRata = 44100;
    GetDefaultInputDeviceSampleRate(&sampleRata);
    
    dataFormat.mSampleRate = sampleRata; //硬件获取
    dataFormat.mChannelsPerFrame = 2;//channel 数量 硬件获取
    dataFormat.mFormatID = kAudioFormatLinearPCM; //可以设置其他封装格式，比如kAudioFormatMPEG4AAC aac格式，但是写文件的时候就可以不用 FILE 句柄来写， 可以 使用 AudioFile 来写，kAudioQueueProperty_MagicCookie 获取meta data，再写入
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mBytesPerPacket = dataFormat.mBytesPerFrame = (dataFormat.mBitsPerChannel >> 3) * dataFormat.mChannelsPerFrame;
    dataFormat.mFramesPerPacket = 1;
    
    _mDataFormat = dataFormat;
    [JBConfigData shareInstance].captureASBD = _mDataFormat;
    NSLog(@"音频采集输出的音频格式");
    [JBFileManager  printASBD:_mDataFormat];
}

- (void)dealloc {
    [self stopAudioCapture];
    
}

- (void)stopAudioCapture {
    if (!self.isRunning) {
        return;
    }
    self.isRunning = NO;
    
    if (_mQueue)
    {
        OSStatus status  = AudioQueueStop(_mQueue, true);
        if(status  == noErr) {
            for (int i = 0; i < KNumberBuffers ; i++){
                // AudioQueueDispose 会自动调用这个函数
                AudioQueueFreeBuffer(_mQueue, _mBuffers[i]);
            }
        } else {
            NSLog(@"停流出问题了");
        }
        
        status = AudioQueueDispose(_mQueue, true);
        if (status != noErr) {
            NSLog(@"Audio Recorder: Dispose failed: %d",status);
            return;
        }else {
            _mQueue = NULL;
            NSLog(@"Audio Recorder: stop AudioQueue successful.");
        }
    }
}

- (BOOL)getIsRunning {
    return _isRunning;
}

@end
