//
//  JBVideoDecoder.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import "JBVideoDecoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import "JBFileManager.h"

@interface JBVideoDecoder()
@property(nonatomic, strong) dispatch_queue_t decodeQueue;

@property(nonatomic, assign) uint32_t spsSize;
@property(nonatomic, assign) uint8_t * sps;

@property(nonatomic, assign) uint32_t ppsSize;
@property(nonatomic, assign) uint8_t * pps;

@property (nonatomic) VTDecompressionSessionRef decodeSession;
@property (nonatomic) CMVideoFormatDescriptionRef decodeDesc;
@property (nonatomic, strong) JBConfigData *configData;
@end

//需要直接拿来进行 位图 显示，所以去rgb类型
const static FourCharCode s_outputFormat = kCVPixelFormatType_32ARGB; //kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

@implementation JBVideoDecoder

- (instancetype)initWithData:(JBConfigData *)data {
    self = [super init];
    if (self) {
        self.configData = data;
        self.decodeQueue = dispatch_queue_create("decode queue jimbo", DISPATCH_QUEUE_SERIAL);
        self.callbackQueue = dispatch_queue_create("decode callback queue jimbo", DISPATCH_QUEUE_SERIAL);
        
        CMVideoDimensions dims = {(int32_t)data.width, (int32_t)data.height};
        [[JBFileManager shareInstance] printFFmpegLogWithYuv:s_outputFormat dimensions:dims isCapture:NO];
    }
    return self;
}

//初始化解码器
- (BOOL)initDecoder {
    if (self.decodeSession) {
        return YES;
    }
    const uint8_t *const parameterSetPointer[2] = {self.sps, self.pps};
    const size_t parameterSetSizes[2] = {self.spsSize, self.ppsSize};
    int naluHeaderLen = 4; //大端模式
    
    /**
     CFAllocatorRef: 默认
     parameterSetCount: 解码参数个数 2: sps pps
     parameterSetPointers: 参数集的指针
     parameterSetSizes: 参数集的大小
     NALUnitHeaderLength: 起始位的长度
     formatDescriptionOut: 解码器描述
     */
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointer, parameterSetSizes, naluHeaderLen, &self->_decodeDesc);
    if (status != noErr) {
        NSLog(@"CMVideoFormatDescriptionCreateFromH264ParameterSets  %d", (int)status);
        return NO;
    }
    
    //解码参数
    /*
     kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12。 苹果的硬解码器只支持NV12。
     
     1. 摄像头输出格式 YUV 420
     2. 宽高
     3. kCVPixelBufferOpenGLCompatibilityKey: 允许OpenGl的上下文能够直接对解码后的图像数据进行绘制，不需要数据总线与CPU之间的数据复制。 简称： 零拷贝通道
     */
    
    
    NSDictionary *destionationPixelBuffer = @{
        (id)kCVPixelBufferPixelFormatTypeKey:@(s_outputFormat),
        (id)kCVPixelBufferWidthKey: @(self.configData.width),
        (id)kCVPixelBufferHeightKey: @(self.configData.height),
        (id)kCVPixelBufferOpenGLCompatibilityKey: @(YES)
    };
    
    
    //回调方法：
    //gray -> OpenGL
    //涉及渲染流程了
    //VTDecompressionOutputCallbackRecord 结构体
    VTDecompressionOutputCallbackRecord callback;
    callback.decompressionOutputCallback = videoDecompressionOutputCallback;
    callback.decompressionOutputRefCon = (__bridge void *)self;
    
    //创建session
    /**
     
     destinationImageBufferAttributes: 描述源像素缓冲区 NULL
     outputCallback: 已经解码后的回调函数
     */
    status = VTDecompressionSessionCreate(kCFAllocatorDefault, self.decodeDesc, NULL, (__bridge CFDictionaryRef)destionationPixelBuffer, &callback, &self->_decodeSession);
    if (status != noErr) {
        NSLog(@"VTDecompressionSessionCreate  %d", (int)status);
        return NO;
    }
    
    
    //设置实时解码
    VTSessionSetProperty(self.decodeSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
    
    //session 现在就创建好了，参数也配置好了
    NSLog(@"%s succeed", __FUNCTION__);
    return YES;
}


//解码后的回调
void videoDecompressionOutputCallback(void * CM_NULLABLE decompressionOutputRefCon, //回调的 self
                                      void * CM_NULLABLE sourceFrameRefCon,         //帧引用，源图像
                                      OSStatus status,
                                      VTDecodeInfoFlags infoFlags,                  //同步异步解码
                                      CM_NULLABLE CVImageBufferRef imageBuffer,     //实际图像缓存
                                      CMTime presentationTimeStamp,                 //出现的时间戳
                                      CMTime presentationDuration)                  //出现的持续时间
{
    //  jimbo error  2022-03-24 22:50:20.331197+0800 JBMacAVDemo[10982:537752] videoDecompressionOutputCallback  -6661
    //  CoreVideo CVReturn.h  kCVReturnInvalidArgument -6661
    //回调方法，设置session的时候配置的方法
    //解码完成后回到的方法
    if (status != noErr) {
        NSLog(@"videoDecompressionOutputCallback  %d", (int)status);
        return;
    }
    
    //sourceFrameRefCon -> CVPixelBufferRef
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon; //这里可以不用先复制，直接取下面的数据就行了？
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    JBVideoDecoder *decoder = (__bridge  JBVideoDecoder *)decompressionOutputRefCon;
    
    //调用回调队列： TODO：
    dispatch_async(decoder.callbackQueue, ^{
        if(decoder.delegate && [decoder.delegate respondsToSelector:@selector(videoDecoderCallback:)]) {
            [decoder.delegate videoDecoderCallback:imageBuffer];
        }
    });  
}

- (CVPixelBufferRef)decode:(uint8_t *)frame withSize:(uint32_t)size {
    
    
    // CVPixelBufferRef -> 解码后的数据、编码签的原始视频诗句
    // CMBlockBufferRef : 编码后的数据
    // 需要将frame  -> CMBlockBufferRef -> CMSampleBufferRef
    // 以为解码函数需要的是CMSampleBufferRef 类型， 解码后的数据 CVPixelBufferRef
    
    CVPixelBufferRef ouputPixelBuffer = NULL;
    CMBlockBufferRef blockBuffer = NULL;
    CMSampleBufferRef sampleBufferRef = NULL;
    
    CMBlockBufferFlags flag = 0;
    
    //创建block buffer
    /**
     memoryBlock: 内容 ， frame
     blockLength: frame的大小
     blockAllocator:  NULL
     customBlockSource: NULL
     offsetToData: 数据偏移
     */
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, frame, size, kCFAllocatorNull, NULL, 0, size, flag, &blockBuffer);
    
    if (status != noErr) {
        NSLog(@"CMBlockBufferCreateWithMemoryBlock  %d", (int)status);
        return ouputPixelBuffer;
    }
    
    //sampleBuffer
    const size_t sampleSizeArray[] = {size};
    status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, self.decodeDesc, 1, 0, NULL, 1, sampleSizeArray, &sampleBufferRef);
    if (!sampleBufferRef) {
        NSLog(@"sampleBufferRef is nil");
        return ouputPixelBuffer;
    }
    if (status != noErr) {
        NSLog(@"CMSampleBufferCreateReady  %d", (int)status);
        CFRelease(sampleBufferRef);
        return ouputPixelBuffer;
    }
    
    //3.解码函数
    //低功耗模式
    VTDecodeFrameFlags flag1 = kVTDecodeFrame_1xRealTimePlayback;
    //异步解码
    VTDecodeInfoFlags flag2 = kVTDecodeInfo_Asynchronous;
    //解码函数
    status = VTDecompressionSessionDecodeFrame(self.decodeSession, sampleBufferRef, flag1, &ouputPixelBuffer, &flag2);
    if (status != noErr) {
        NSLog(@"VTDecompressionSessionDecodeFrame  %d", (int)status);
        
    }
    
    CFRelease(sampleBufferRef);
    CFRelease(blockBuffer);
    return ouputPixelBuffer;
}

- (void)decodeNaluData:(uint8_t *)frame size:(uint32_t)size {
    //数据类型：frame,前面4字节是起始位,没有任何作用 00 00 00 01
    
    
    uint32_t naluSize = size - 4;
    uint8_t *pNaluSize = (uint8_t *)(&naluSize);
    CVPixelBufferRef pixelBuffer = NULL;
    //前面4帧 : 大小端转换, 倒过来
    frame[0] = *(pNaluSize + 3);
    frame[1] = *(pNaluSize + 2);
    frame[2] = *(pNaluSize + 1);
    frame[3] = *(pNaluSize + 0);
    
    
    //第五位转换成十进制.  7:sps   8:pps 5:I frame
    int type  = (frame[4] & 0x1F);
    //第一次获取到关键帧的时候，初始化解码器
    switch (type) {
        case 0x05: //关键帧
            if ([self initDecoder]) {
                pixelBuffer = [self decode:frame withSize:size];
            }
            break;
        case 0x06:
            //增强型， 暂时没有使用
            break;
        case 0x07: //sps
        {
            NSLog(@"----sps got");
            self.spsSize = naluSize;
            _sps = malloc(self.spsSize);
            memcpy(self.sps, &frame[4], self.spsSize);
        }
            break;
        case 0x08: //pps
        {
            NSLog(@"----pps got");
            self.ppsSize = naluSize;
            _pps = malloc(self.ppsSize);
            memcpy(self.pps, &frame[4], self.ppsSize);
        }
            break;
        default:
            // b / p 等帧
            if ([self initDecoder]) {
                pixelBuffer = [self decode:frame withSize:size];
            }
            break;
    }
    
}

- (void)decodeNaluData:(NSData *)frame {
    //判断数据类型是否是 sps/pps（不用解码）
    dispatch_async(self.decodeQueue, ^{
        uint8_t *nalu = (uint8_t *)frame.bytes;
        [self decodeNaluData:nalu size:(uint32_t)frame.length];
    });
}

- (void)dealloc {
    if (self.decodeSession)
    {
        VTDecompressionSessionInvalidate(self.decodeSession);
        CFRelease(self.decodeSession);
        self.decodeSession = NULL;
    }
}

@end
