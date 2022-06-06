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


@implementation JBAudioQueueCapture
+ (instancetype)shareInstance {
    
    static JBAudioQueueCapture *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[JBAudioQueueCapture alloc] init];
 
    });
    return instance;
}


- (void)setupData {
    self.audioConfigData = [[JBConfigData alloc] init];
    self.audioConfigData.type = JBCaptureTypeAudio;
    [self configureAudioCaptureWithDurationSec:0.05];
}

- (BOOL)startAudioCapture {
    
    if (self.isRunning) {
        NSLog(@"Audio Recorder: Start recorder repeat");
        return NO;
    }
    [self setupData];
    
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
     inPacketDescs: 音频数据中一组packet描述.如果是VBR格式数据,如果录制文件需要将此值传递给AudioFileWritePackets函数
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
    
    //设置获取到的音频格式 ASBD
    UInt32 size = sizeof(_mDataFormat);
    status = AudioQueueGetProperty(_mQueue, kAudioQueueProperty_StreamDescription,  &_mDataFormat, &size);
    if (status != noErr) {
        NSLog(@"get audio ASBD errored. %d", (int)status);
        return;
    }
    //计算Audio Queue 每个buffer 的大小
    int frames = (int)ceil(durationSec * _mDataFormat.mSampleRate); //采集时间内的 小样本数量
    //durationSec 的 buffer 大小
    UInt32 bufferByteSize = frames * _mDataFormat.mBytesPerFrame * _mDataFormat.mChannelsPerFrame;
    
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
    
    dataFormat.mSampleRate = 48000; //硬件获取
    dataFormat.mChannelsPerFrame = 2;//channel 数量 硬件获取
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mBytesPerPacket = dataFormat.mBytesPerFrame = (dataFormat.mBitsPerChannel >> 3) * dataFormat.mChannelsPerFrame;
    dataFormat.mFramesPerPacket = 1;
    
    _mDataFormat = dataFormat;
    self.audioConfigData.mASBD = _mDataFormat;
    NSLog(@"音频采集输出的音频格式");
    [[JBFileManager shareInstance] printASBD:_mDataFormat];
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
