//
//  JBCaptureManager.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/20.
//

#import "JBCaptureManager.h"
#import <AVFoundation/AVFoundation.h>
#import "JBFileManager.h"


@interface JBCaptureManager() <AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) dispatch_queue_t aCaptureQueue;
@property(nonatomic, strong) AVCaptureDeviceInput  *videoInputDevice;
@property(nonatomic, strong) AVCaptureDeviceInput  *audioInputDevice;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property(nonatomic, strong) AVCaptureAudioDataOutput *audioOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, assign) JBCaptureType type;
@property(nonatomic, weak) CALayer *parentLayer;

@property(nonatomic, assign) int fps;

@end

/**
 步骤：
 1. 按照类型 配置 audio/video 的input。output。session
 2. 包括配置 fps、分辨率等
 3. 在系统的delegate中回去采集到的原始数据
 4. 回传原始数据
 */

@implementation JBCaptureManager

- (instancetype)initWithType:(JBCaptureType)type parenLayerIfVideo:(CALayer *__nullable)parentLayer {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.type = type;
    self.parentLayer =parentLayer;
    return self;
}

- (void)prepare {
    self.aCaptureQueue = dispatch_queue_create("jimbo capture only", DISPATCH_QUEUE_SERIAL);
    self.session = [[AVCaptureSession alloc] init];
    
    switch (self.type) {
        case JBCaptureTypeAudio:
            [self setupAudioCapture];
            break;
        case JBCaptureTypeVideo:
            [self setupVideoCapture];
            break;
        case JBCaptureTypeAll:
            [self setupAudioCapture];
            [self setupVideoCapture];
            break;
        default:
            break;
    }
}


- (void)startCapture {
    [self.session startRunning];
}

- (void)setupAudioCapture {
    
    NSArray *devices = nil;
    AVCaptureDeviceDiscoverySession *deviceDiscoverySession =  [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInMicrophone] mediaType:AVMediaTypeAudio position:AVCaptureDevicePositionBack];
    devices = deviceDiscoverySession.devices;
    
    AVCaptureDevice *sel;
    for(AVCaptureDevice *de in devices) {
//        if ([de.localizedName isEqualToString:@"BlackHole 2ch"]) {
//        if ([de.localizedName isEqualToString:@"MacBook Pro麦克风"]) {
//        if ([de.localizedName isEqualToString:@"Loopback Audio"]) {
//        if ([de.localizedName isEqualToString:@"SoundPusher Audio"]) {
//        if ([de.localizedName isEqualToString:@"PRISM Cam Audio"]) {
                if ([de.localizedName isEqualToString:@"外置麦克风"]) {

            sel = de;
            break;
        }
    }
    
    for(AVCaptureDevice *de in devices) {
        NSLog(@"all: %@", de.localizedName);
    }
    
    
    NSLog(@"devices:%@", sel);
    AVCaptureDeviceInput *inputDevice = [[AVCaptureDeviceInput alloc] initWithDevice:sel error:nil];
    if (!inputDevice) {
        NSLog(@"audioInputDevice inputDevice 不存在");
        return;
    }
    AudioStreamBasicDescription deviceASBD = *CMAudioFormatDescriptionGetStreamBasicDescription(inputDevice.device.activeFormat.formatDescription);
    NSLog(@"音频采集设备原始输入的音频格式");
    [[JBFileManager shareInstance] printASBD:deviceASBD];
    
    self.audioInputDevice = inputDevice;
    
    if ([self.session canAddInput:inputDevice]) {
        [self.session addInput:inputDevice];
    } else {
        NSLog(@"audioInputDevice add failed");
    }
    NSLog(@"audioInputDevice inputDevice name:%@", inputDevice.device.localizedName);
    //输出
    self.audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    //设置捕捉 队列 和代理
    [self.audioOutput setSampleBufferDelegate:self queue:self.aCaptureQueue];
    
    if ([self.session canAddOutput:self.audioOutput]) {
        [self.session addOutput:self.audioOutput];
        NSLog(@"audioOutput add succeed");
    } else {
        NSLog(@"audioOutput add failed");
    }
    [self setupAudioSettings:deviceASBD];
    [self.session commitConfiguration];
    
//    [[JBFileManager shareInstance] printASBD:self.audioOutput.audioSettings];
}

- (void)setupAudioSettings:(AudioStreamBasicDescription )asbd {
    //必须对输出的音频配置进行 重新设置，不然很大可能是随机的参数输出，会导致不能播放

    int mSampleRate = (asbd.mSampleRate < 48000.0) ? asbd.mSampleRate : 48000.0; // ...so do it here max 48k or less
    int mChannelsPerFrame = (asbd.mChannelsPerFrame > 2) ? 2 : asbd.mChannelsPerFrame; // 2 channels max
    
    NSLog(@"重设 音频 输出属性");
    
    BOOL isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat;
    BOOL isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    BOOL isBigEndian = asbd.mFormatFlags & kAudioFormatFlagIsBigEndian;
    
    // AVCaptureAudioDataOutput will return samples in the device default format unless otherwise specified, this is different than what QTKitCapture did
    // where the Canonical Audio Format was used when no settings were specified. When keys aren't specifically set the device default value is used
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithUnsignedInt:kAudioFormatLinearPCM],                    AVFormatIDKey,
                             [NSNumber numberWithFloat:mSampleRate],                  AVSampleRateKey,
                             [NSNumber numberWithUnsignedInteger:mChannelsPerFrame],  AVNumberOfChannelsKey,
                             [NSNumber numberWithInt:asbd.mBitsPerChannel],                AVLinearPCMBitDepthKey,
                             [NSNumber numberWithBool:isFloat],                                         AVLinearPCMIsFloatKey,
                             [NSNumber numberWithBool:isNonInterleaved],                                AVLinearPCMIsNonInterleaved,
                             [NSNumber numberWithBool:isBigEndian],                                     AVLinearPCMIsBigEndianKey,
                              nil];
    
    self.audioOutput.audioSettings = settings;
}

- (void)setupVideoCapture {
    
    
    
    self.videoConfigData = [[JBConfigData alloc] init];
    self.videoConfigData.type = JBCaptureTypeVideo;

    
    NSArray *devices = nil;
    AVCaptureDeviceDiscoverySession *deviceDiscoverySession =  [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    devices = deviceDiscoverySession.devices;
    for(AVCaptureDevice *de in devices) {
        NSLog(@"video: %@", de.localizedName);
    }
    AVCaptureDeviceInput *inputDevice = [[AVCaptureDeviceInput alloc] initWithDevice:devices[0] error:nil];
    if (!inputDevice) {
        NSLog(@"inputDevice 不存在");
    }
    
    
    if ([self.session canAddInput:inputDevice]) {
        [self.session addInput:inputDevice];
    } else {
        NSLog(@"videoInputDevice add failed");
    }
    self.videoInputDevice = inputDevice;
    
    //输出
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];

     /*
     设置视频帧延迟到底时是否丢弃数据.
     YES: 处理现有帧的调度队列在captureOutput:didOutputSampleBuffer:FromConnection:Delegate方法中被阻止时，对象会立即丢弃捕获的帧。
     NO: 在丢弃新帧之前，允许委托有更多的时间处理旧帧，但这样可能会内存增加.
     */
    [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];//是否丢掉最后的视频帧
    // YUV 420 颜色格式
//    [self.videoOutput setVideoSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];

    //设置捕捉 队列 和代理
    [self.videoOutput setSampleBufferDelegate:self queue:self.aCaptureQueue];
    
    if ([self.session canAddOutput:self.videoOutput]) {
        [self.session addOutput:self.videoOutput];
    } else {
        NSLog(@"videoOutput add failed");
    }
    
    [self.session commitConfiguration];
    [self setupPrestAndFps];
    
    [self setupPreviewLayer];
    
}


- (void)setupPreviewLayer {
    [self.parentLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    self.previewLayer.frame = self.parentLayer.bounds;
    [self.parentLayer addSublayer:self.previewLayer];
    //视频重力
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}


- (void)setupPrestAndFps {
    
    NSArray *types  =  self.videoOutput.availableVideoCVPixelFormatTypes;
    for (NSNumber *cType in types) {
        [[JBFileManager shareInstance] printVideoFormat:[cType integerValue] logPre:@"摄像头支持像素格式:"];
    }
    
    if (!self.videoInputDevice || !self.videoInputDevice.device) {
        NSLog(@"setupPrestAndFps failed");
        return;
    }
    for (AVCaptureDeviceFormat *format in self.videoInputDevice.device.formats) {
        CMVideoDimensions formatDescription = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        NSLog(@"摄像头支持分辨率: %d * %d", formatDescription.width, formatDescription.height);
    }
    if([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        self.session.sessionPreset = AVCaptureSessionPreset640x480;
        self.videoConfigData.width = 640;
        self.videoConfigData.height = 480;
    } else if([self.session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        self.session.sessionPreset = AVCaptureSessionPreset1920x1080;
        self.videoConfigData.width = 1920;
        self.videoConfigData.height = 1080;
    } else if([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        self.session.sessionPreset = AVCaptureSessionPreset1280x720;
        self.videoConfigData.width = 1280;
        self.videoConfigData.height = 720;
    }
    //fps
    for (AVFrameRateRange *range in self.videoInputDevice.device.activeFormat.videoSupportedFrameRateRanges) {
        float ratio = range.minFrameRate/range.maxFrameRate;
        self.videoConfigData.fps = (int)range.maxFrameRate;
        CMTime time = {range.minFrameDuration.value,(CMTimeScale)(range.minFrameDuration.timescale*ratio),range.minFrameDuration.flags,range.minFrameDuration.epoch};
        
        NSError *err;
        if ([self.videoInputDevice.device lockForConfiguration:&err]) {
            [self.videoInputDevice.device setActiveVideoMinFrameDuration:time];
            [self.videoInputDevice.device unlockForConfiguration];
            break;
        }
    }


    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
//                              @(kCVPixelFormatType_32ARGB),        kCVPixelBufferPixelFormatTypeKey, /* 如果需要拿来直接转 image的话，就需要 rgb类型的 */
                              @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),        kCVPixelBufferPixelFormatTypeKey,
                              @(self.videoConfigData.width),                             kCVPixelBufferWidthKey,
                              @(self.videoConfigData.height),                            kCVPixelBufferHeightKey,
                              nil];
    
    [self.videoOutput setVideoSettings:settings];
  
}

#pragma mark - capture delegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    if (output == self.videoOutput) {
        [self captureVideoOutput:sampleBuffer];
    } else if (output == self.audioOutput) {
        [self captureAudioOutput:sampleBuffer];
    }
}
+ (NSString *)getCharFourcc:(FourCharCode)subtype {
    char buffer[5] = {0};
    *(int *)&buffer[0] = CFSwapInt32HostToBig(subtype);
    return [NSString stringWithFormat:@"%s (%i)", buffer, subtype];
}

- (void)writeYUVData:(CVImageBufferRef)dataBuffer {
    if (CVPixelBufferIsPlanar(dataBuffer)) {
        int count = CVPixelBufferGetPlaneCount(dataBuffer);
        for(int i = 0; i< count; i++) {
            void *baseBuffer = CVPixelBufferGetBaseAddressOfPlane(dataBuffer, i);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(dataBuffer, i);
            size_t height = CVPixelBufferGetHeightOfPlane(dataBuffer, i);
            size_t lenght = bytesPerRow * height;
            
            unsigned char *newedImgBuff = (unsigned char *)malloc(lenght);
            memmove(newedImgBuff, baseBuffer, lenght);
            [[JBFileManager shareInstance] writeVideoYuv:newedImgBuff buffersize:(UInt32)lenght];
        }
    } else {
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(dataBuffer);
        size_t height = CVPixelBufferGetHeight(dataBuffer);
        size_t lenght = bytesPerRow * height;
        void *baseBuffer = CVPixelBufferGetBaseAddress(dataBuffer);

        unsigned char *newedImgBuff = (unsigned char *)malloc(lenght);
        memmove(newedImgBuff, baseBuffer, lenght);
        [[JBFileManager shareInstance] writeVideoYuv:newedImgBuff buffersize:(UInt32)lenght];
    }
}
#define MILLI_TIMESCALE 1000
#define MICRO_TIMESCALE (MILLI_TIMESCALE * 1000)
#define NANO_100_TIMESCALE (MICRO_TIMESCALE * 10)
- (void)captureVideoOutput:(CMSampleBufferRef)sampleBuffer {
    static bool isVideoFirstOut = false;
    
    CVImageBufferRef imgBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imgBuffer) {
        NSLog(@"CMSampleBufferGetImageBuffer failed");
    }
    
    CVPixelBufferLockBaseAddress(imgBuffer, 0);
    
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (!isVideoFirstOut || !self.videoConfigData) {
        isVideoFirstOut = true;
        FourCharCode fourcc = CMFormatDescriptionGetMediaSubType(desc);
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(desc);
        NSLog(@"fourcc: %@", [[self class] getCharFourcc:fourcc]);
        [[JBFileManager shareInstance] printFFmpegLogWithYuv:fourcc dimensions:dims isCapture:YES];
    }

    [self writeYUVData:imgBuffer];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureOutputVideoData:)]) {
        [self.delegate captureOutputVideoData:imgBuffer];
    }
    CVPixelBufferUnlockBaseAddress(imgBuffer, 0);
}

- (void)writePCMData:(CMSampleBufferRef)sampleBuffer {
    size_t requiredSize = 0;
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, &requiredSize, NULL, 0, NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, NULL);
    assert(status == noErr);

    AudioBufferList *bList = (AudioBufferList *)malloc(sizeof(AudioBufferList)+requiredSize);
    CMBlockBufferRef blockBuffer = NULL;
    
    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, NULL, bList, requiredSize, NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
    assert(status == noErr);
    
    for(int i = 0; i< bList->mNumberBuffers; i++ ) {
        [[JBFileManager shareInstance] writeAudioPCM:bList->mBuffers->mData buffersize:bList->mBuffers->mDataByteSize];
    }
    
    free(bList);
    if (blockBuffer) {
        CFRelease(blockBuffer);
    }
}

- (void)captureAudioOutput:(CMSampleBufferRef)sampleBuffer {
    static bool isAudioFirstOut = false;

    CFRetain(sampleBuffer);
    if (!isAudioFirstOut || !self.audioConfigData) {
        isAudioFirstOut =  true;
        CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t size;
        AudioStreamBasicDescription mASBD = CMAudioFormatDescriptionGetFormatList(desc, &size)->mASBD;
        NSLog(@"音频采集输出的音频格式");
        [[JBFileManager shareInstance] printASBD:mASBD];

        JBConfigData *audioData = [[JBConfigData alloc] init];
        audioData.type = JBCaptureTypeAudio;
        audioData.mASBD = mASBD;
        self.audioConfigData = audioData;
        /** 比如
         mSampleRate = 44100.000000
         mFormatID = 1819304813
         mFormatFlags = 4       // kAudioFormatFlagIsSignedInteger
         mBytesPerPacket = 6    // mBytesPerFrame * mFramesPerPacket = 6*1
         mFramesPerPacket = 1   // PCM = 1, AAC=1024
         mBytesPerFrame = 6     // mBitsPerChannel / 8 * mChannelsPerFrame = 24/8*3
         mChannelsPerFrame = 2
         mBitsPerChannel = 24   //位深  24/8 == 3字节byte
         mReserved = 0
         */

           /**
            * sampleBuffer 的大小为：4096
            * mBytesPerFrame = 4
            即每次回调 4096字节/4字节(每个样本帧) = 1024 样本帧
            即每次回调采集的时间为：48000/1024 = 46.875毫秒
         * */
    }

//    [self writePCMData:sampleBuffer];
    
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!dataBuffer) {
        NSLog(@"CMSampleBufferGetDataBuffer err");
    }
    size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);
    unsigned char *bufferData = (unsigned char *)malloc(dataLength);
    OSStatus status = CMBlockBufferCopyDataBytes(dataBuffer, 0, dataLength, bufferData);
    printErr(@"CMBlockBufferCopyDataBytes error:", status);
    
    CFRelease(sampleBuffer);
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureOutputAudioData:lenght:)]) {
        [self.delegate captureOutputAudioData:bufferData lenght:dataLength];
    }
    


}

- (void)stopCapture {
    if (self.session && self.session.isRunning) {
        [self.session stopRunning];
    }
    self.audioConfigData = NULL;
    self.videoConfigData = NULL;
}
@end

