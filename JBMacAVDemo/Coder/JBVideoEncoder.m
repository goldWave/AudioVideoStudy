//
//  JBVideoEncoder.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import "JBVideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>

@interface JBConfig : NSObject
@property(nonatomic, assign) int width;
@property(nonatomic, assign) int height;
@end

@interface JBVideoEncoder()
@property(nonatomic, strong) dispatch_queue_t callbackQueue;
@property(nonatomic, strong) dispatch_queue_t aEncoderQueue;
@property(nonatomic) VTCompressionSessionRef encodeSession;
@property(nonatomic, assign) int frameID;

@end

/**
 步骤： 
 1. 创建初始化编码器. 包括编码回调参数 及 各种编码器的配置   VTCompressionSessionCreate ->  encodeSession的属性 -> VTCompressionSessionPrepareToEncodeFrames
 2. 原始数据进入，  进行编码  CMSampleBufferRef -> CVImageBufferRef -> VTCompressionSessionEncodeFrame
 3. 第一步的回调函数里面 获取sps pps 及编码后的数据 NALU
 4. 写入文件 & delegate回调回去编码后的数据
 5. 销毁编码器 VTCompressionSessionInvalidate TODO。
 */


@implementation JBVideoEncoder

- (instancetype)initWithData:(JBConfigData *)data {
    self = [super init];
    if (self) {
        self.configData = data;
        self.aEncoderQueue = dispatch_queue_create("encode queue jimbo", DISPATCH_QUEUE_SERIAL);
        self.callbackQueue = dispatch_queue_create("encode callback queue jimbo", DISPATCH_QUEUE_SERIAL);
        [self initVideoToolbox];
    }
    return self;
}

#pragma mark - in data
-(void)encodeThePixelBuffer:(CVImageBufferRef)imageBuffer {
    CVPixelBufferRetain(imageBuffer);
    dispatch_async(_aEncoderQueue, ^{
        //获取一张张图片
//        cvimagebuffer
        //帧时间
        CMTime ptime = CMTimeMake(self.frameID++, 1000);
        VTEncodeInfoFlags flags;
        
        //编码函数
        OSStatus status = VTCompressionSessionEncodeFrame(self.encodeSession,
                                                          imageBuffer/*未编码数据*/,
                                                          ptime/*时间戳*/,
                                                          kCMTimeInvalid/*帧展示时间，如果没有时间信息，就显示invalid*/,
                                                          NULL/*帧属性 这里我们可以用来指定产生I帧*/,
                                                          NULL/*回调， 编码过程的回调*/,
                                                          &flags/*同步、异步*/);
        if (status != noErr) {
            printErr(@"VTCompressionSessionEncodeFrame" , status);
            CVPixelBufferRelease(imageBuffer);
            //            [self stopCapture];
            return;
        }
        
        //        printErr(@"h264: VTCompressionSessionEncodeFrame succedd!");
        
        //编码成功
        //现在去didCompressionOutputH264Callback回调处理
        //NALU -> h264文件 . 数据加上sps、pps 每一个NALU+起始码
        CVPixelBufferRelease(imageBuffer);
    });
}



#pragma mark - init video tollbox
- (void)initVideoToolbox {
    //dispatch_async(self.aEncoderQueue, ^{
    self.frameID = 0;
    
    //此处必须和 创建采集时配置的 摄像头分辨率保持一致
    //创建session
    
    /**
     参数1:allocator NULL 默认
     2:  width 像素为单位， 如果数据非法， 编码会改为合理的值
     3. height
     4: codecType - 编码类型： H264 - kCMVideoCodecType_H264
     5: encoderSpecification - 编码规范 NULL
     6: sourceImageBufferAttributes - 源像素缓冲区 NULL 由video toolbox 默认创建
     7: compressedDataAllocator - 压缩数据分配器 NULL
     8: outputCallback - 编码完成后回调， 可以给NULL
     9: outputCallbackRefCon - 回调的用户参考值 - self, 桥接过去
     10: compressionSessionOut -  传入的session
     */
    OSStatus status = VTCompressionSessionCreate(kCFAllocatorDefault,
                                                 (int32_t)self.configData.width,
                                                 (int32_t)self.configData.height,
                                                 kCMVideoCodecType_H264,
                                                 NULL,
                                                 NULL,
                                                 NULL,
                                                 didCompressionOutputH264Callback,
                                                 (__bridge void *)self,
                                                 &self->_encodeSession);
    printErr(@"VTCompressionSessionCreate:",status);
    
    //配置参数
    //实时编码
    status = VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    printErr(@"kVTCompressionPropertyKey_RealTime: ",status);
    
    //指定编码比特流的配置文件和级别。直播一般使用baseline，可减少由于b帧带来的延时
    /**
     BP(Baseline Profile): 基本画质。支持I/P 帧
     MP(Main profile)：主流画质。提供I/P/B 帧
     */
    status = VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    //        VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    printErr(@"kVTCompressionPropertyKey_ProfileLevel: ",status);
    
    //GOP (太小视频会模糊，太大会造成文件增大)
    int frameInterval = 30;
    status =  VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(frameInterval));
    //TODO: CFNumberRef 是否需要进行释放
    printErr(@"kVTCompressionPropertyKey_MaxKeyFrameInterval: ",status);
    
    //帧率上限
    status =  VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(self.configData.fps));
    printErr(@"kVTCompressionPropertyKey_ExpectedFrameRate: ",status);
    
    //平均码率。有公式可以参考的 ，单位是bps 。VideoToolBox框架只支持ABR模式
    NSInteger  bitRate = self.configData.width * self.configData.height * 3 * 4 * 8;
    status = VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bitRate));
    printErr(@"kVTCompressionPropertyKey_AverageBitRate: ",status);
    
    //码率值
    //码率过大，视频清晰度会很高， 但是视频体积比较大
    NSArray *limit = @[@(bitRate * 1.5/8),@(1)];
    status = VTSessionSetProperty(self.encodeSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
    printErr(@"kVTCompressionPropertyKey_DataRateLimits: ",status);
    
    
    //以上都是必要参数
    
    //准备编码
    status = VTCompressionSessionPrepareToEncodeFrames(self.encodeSession);
    printErr(@"VTCompressionSessionPrepareToEncodeFrames: ",status);
    //});
}

#pragma mark - out data
//编码后的回调 数据
void didCompressionOutputH264Callback(void * CM_NULLABLE outputCallbackRefCon,void * CM_NULLABLE sourceFrameRefCon,
                                      OSStatus status,VTEncodeInfoFlags infoFlags,CM_NULLABLE CMSampleBufferRef sampleBuffer ) {
    
    //    printErr(@"h264 callback: status: %d, infoFlags:%d", (int)status, (int)infoFlags);
    
    if (status != noErr) {
        NSLog(@"didCompressionOutputH264Callback - err");
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressionOutputH264Callback data not readly");
        return;
    }
    
    JBVideoEncoder *encoder = (__bridge  JBVideoEncoder *)outputCallbackRefCon;
    
    //判断是否是关键帧。 sps pps 信息
    //    CFArrayRef a =CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    //    CFDictionaryRef attachSampleRef = CFArrayGetValueAtIndex(a, 0);
    //    bool isKeyFrame = CFDictionaryContainsKey(CFArrayGetValueAtIndex(a, 0), kCMSampleAttachmentKey_NotSync);
    CFArrayRef array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef dic = (CFDictionaryRef)CFArrayGetValueAtIndex(array, 0);
    bool isKeyFrame = !CFDictionaryContainsKey(dic, kCMSampleAttachmentKey_NotSync);
    
    
    //sps pps 数据只需要拿一次就行了
    if (isKeyFrame && !encoder.isGotSpsPps) {
        //获取sps pps
        //拿到源图像的编码信息
        CMFormatDescriptionRef format =  CMSampleBufferGetFormatDescription(sampleBuffer);
        
        //真正获取
        //sps count/sps
        size_t spsSize, spsCount;
        const uint8_t *spsContent;
        OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &spsContent, &spsSize, &spsCount, 0);
        
        size_t ppsSize, ppsCount;
        const uint8_t *ppsContent;
        OSStatus ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &ppsContent, &ppsSize, &ppsCount, 0);
        
        if (spsStatus == noErr && ppsStatus == noErr) {
            // pps sps 获取成功
            NSData *spsData = [NSData dataWithBytes:spsContent length:spsSize];
            NSData *ppsData = [NSData dataWithBytes:ppsContent length:ppsSize];
            if (encoder) {
                [encoder writeFileHeaderWithSpsPps:spsData pps:ppsData];
                encoder.isGotSpsPps = YES;
            }
        }
    }
    
    //sps pps 后的NALU
    //编码后的 H264 NALU 数据 .  CMBlockBufferRef为编码后的数据
    CMBlockBufferRef dataBuffer =  CMSampleBufferGetDataBuffer(sampleBuffer);
    
    //单个数据长度，  整块长度
    size_t length, totalLength;
    char *dataPointer;
    
    //通过单个数据长度地址，和总长度，和数据块首地址，获取数据
    //拿到首块数据
    OSStatus naluStatus =  CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (naluStatus == noErr) {
        //读取数据
        //大端小端模式
        //网络传输用的是大端
        
        size_t bufferOffset = 0;
        //获取NALU前面的4字节不是001的起始位，而是大端模式的帧长度
        static const int AVCHeaderLength = 4;
        
        while(bufferOffset < totalLength - AVCHeaderLength) {
            uint32_t NALUnitLength =  0;
            memcpy(&NALUnitLength, dataPointer+bufferOffset, AVCHeaderLength);
            
            //从大端模式 -》 系统端模式（Mac系统是小端）
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            //获取NSData 类型 流数据（NALU）
            NSData *data = [[NSData alloc] initWithBytes:dataPointer+bufferOffset+AVCHeaderLength length:NALUnitLength];
            
            //写入H264
            [encoder writeFilewithEncodedData:data isKeyFrame:isKeyFrame];
            
            //移动偏移量 读取下一数据
            bufferOffset += AVCHeaderLength + NALUnitLength;
        }
    }
}

static const char bytes[] = "\x00\x00\x00\x01";

//首先将数据写入sps pps
- (void)writeFileHeaderWithSpsPps:(NSData *)sps pps:(NSData *)pps {
    //写入之前（起始位）
    size_t length = sizeof(bytes) - 1; //'\0'
    NSData *bytesHeader = [NSData dataWithBytes:bytes length:length];
    
    //    [self.fileHandle writeData:bytesHeader];
    //    [self.fileHandle writeData:sps];
    //    [self.fileHandle writeData:bytesHeader];
    //    [self.fileHandle writeData:pps];
    NSMutableData *spsData = [NSMutableData dataWithData:bytesHeader];
    [spsData appendData:sps];
    
    NSMutableData *ppsData = [NSMutableData dataWithData:bytesHeader];
    [ppsData appendData:pps];
    
    dispatch_async(self.callbackQueue, ^{
        //回调方法传递sps/pps
        if (self.delegate && [self.delegate respondsToSelector:@selector(videoEncodeCallbacksps:pps:)]) {
            [self.delegate videoEncodeCallbacksps:spsData pps:ppsData];
        }
    });
    

}

- (void)writeFilewithEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    
    //创建起始位
    
    size_t length = sizeof(bytes) - 1;
    NSData *dataHeader = [[NSData alloc] initWithBytes:bytes length:length];
    //写入流数据（NALU）, 要写入间隔符
    NSMutableData *naluData = [NSMutableData dataWithData:dataHeader];
    [naluData appendData:data];
    
    dispatch_async(self.callbackQueue, ^{
        //回调方法传递sps/pps
        if (self.delegate && [self.delegate respondsToSelector:@selector(videoEncodeCallback:)]) {
            [self.delegate videoEncodeCallback:naluData];
        }
    });
}

- (void)dealloc {
    if(self.encodeSession) {
        VTCompressionSessionInvalidate(self.encodeSession);
        CFRelease(self.encodeSession);
        self.encodeSession = NULL;
    }
}


@end
