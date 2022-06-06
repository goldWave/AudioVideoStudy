#import "JBFileManager.h"

@interface JBFileManager()
@property (nonatomic) FILE *fp_pcm;
@property (nonatomic) FILE *fp_yuv;
@property (nonatomic) FILE *fp_yuv2;

@property(nonatomic, strong) NSFileHandle *fileHandleVideo;
@property(nonatomic, strong) NSFileHandle *fileHandleAudio;
@property(nonatomic, strong) dispatch_queue_t fileQueue;
@end

@implementation JBFileManager

+ (instancetype)shareInstance {
    
    static JBFileManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[JBFileManager alloc] init];
        instance.fileQueue = dispatch_queue_create("jimbo fileQueue", DISPATCH_QUEUE_SERIAL);
        instance.commandLines = @[].mutableCopy;
    });
    return instance;
}

static NSString *getPcmFilePath() {
    NSString *paths = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *audioFile = [paths stringByAppendingPathComponent:@"pcm_44k.pcm"] ;
    return audioFile;
}
static NSString *getyuvFilePath() {
    NSString *paths = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *file = [paths stringByAppendingPathComponent:@"data.yuv"] ;
    return file;
}
static NSString *getyuv2FilePath() {
    NSString *paths = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *file = [paths stringByAppendingPathComponent:@"data2.yuv"] ;
    return file;
}
static NSString *geth264FilePath() {
    NSString *paths = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *file = [paths stringByAppendingPathComponent:@"video.h264"] ;
    return file;
}

- (void)printAllCommandLines {
    printf("\n\n输出的文件， FFmpeg 命令行解析：\n");
    for (NSString *line in self.commandLines) {
        printf("%s\n", [line UTF8String]);
    }
    
    [self.commandLines removeAllObjects];
}

- (void)stopAllFile {
    dispatch_async(self.fileQueue, ^{
        [self stopAudioPCM];
        [self stopAudioAAC];
        [self stopVideoH264];
        [self stopVideoYuv];
        [self stopVideoYuv2];
        dispatch_after(.1, self.fileQueue, ^{
            [self printAllCommandLines];
        });
    });
    
   
}

#pragma mark - audio

- (void)writeAudioPCM:(CMSampleBufferRef)sampleBuffer {
    CFRetain(sampleBuffer);
    dispatch_async(self.fileQueue, ^{
        
        char *bufferData = NULL;
        size_t buffersize = 0;
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        //4.获取BlockBuffer中音频数据大小以及音频数据地址
        /*OSStatus status = */CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &buffersize, &bufferData);
        [self writeAudioPCM:bufferData buffersize:(UInt32)buffersize];
        
        CFRelease(sampleBuffer);
    });
}

- (void)writeAudioPCM:(void *)bufferData buffersize:(UInt32)buffersize {
    dispatch_async(self.fileQueue, ^{
        if (!self.isRunning) {
            return;
        }
        if (self.fp_pcm == NULL) {
            self.fp_pcm = fopen([getPcmFilePath() UTF8String], "wb++");
        }
        //其实需要考虑多线程bufferData 被释放的问题，demo不考虑
        fwrite((char *)bufferData, 1, buffersize, self.fp_pcm);
    });
}

- (void)stopAudioPCM {
    dispatch_async(self.fileQueue, ^{
        if (!self.fp_pcm) {
            return;
        }
        fclose(self.fp_pcm);
        self.fp_pcm = NULL;
    });
}


- (void)writeAudioAAC:(NSData *)data {
    dispatch_async(self.fileQueue, ^{
        if (!self.isRunning) {
            return;
        }
        if (!self.fileHandleAudio) {
            //创建输出文件
            NSString *paths = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *filePath = [paths stringByAppendingPathComponent:@"audio.aac"] ;
            
            NSString *log = [NSString stringWithFormat:@"编码的AAC文件: ffplay %@", filePath];
            [self.commandLines addObject:log];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            BOOL creatFile = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
            if (!creatFile) {
                NSLog(@"文件创建失败: %@", filePath);
            }
            
            //写入文件
            self.fileHandleAudio = [NSFileHandle fileHandleForWritingAtPath:filePath];
        }
        
        [self.fileHandleAudio seekToEndOfFile];
        [self.fileHandleAudio writeData:data];
        
//        NSLog(@"write aac data length: %zi", data.length);
    });
}

- (void)stopAudioAAC {
    dispatch_async(self.fileQueue, ^{
        if (self.fileHandleAudio)
        {
            [self.fileHandleAudio  closeFile];
            self.fileHandleAudio = nil;
        }
    });
}


#pragma mark - video
- (void)writeVideoYuv:(void *)bufferData buffersize:(UInt32)buffersize {
    dispatch_async(self.fileQueue, ^{
        if (!self.isRunning) {
            return;
        }
        if (self.fp_yuv == NULL) {
            self.fp_yuv = fopen([getyuvFilePath() UTF8String], "wb++");
            
        }
        //其实需要考虑多线程bufferData 被释放的问题，demo不考虑
        fwrite((char *)bufferData, 1, buffersize, self.fp_yuv);
        free(bufferData);
    });
}

- (void)stopVideoYuv {
    dispatch_async(self.fileQueue, ^{
        if (!self.fp_yuv) {
            return;
        }
        fclose(self.fp_yuv);
        self.fp_yuv = NULL;
        NSLog(@"close yuv file ");
    });
}


- (void)writeVideoYuv2:(void *)bufferData buffersize:(UInt32)buffersize {
    dispatch_async(self.fileQueue, ^{
        if (!self.isRunning) {
            return;
        }
        if (self.fp_yuv2 == NULL) {
            self.fp_yuv2 = fopen([getyuv2FilePath() UTF8String], "wb++");
        }
        //其实需要考虑多线程bufferData 被释放的问题，demo不考虑
        fwrite((char *)bufferData, 1, buffersize, self.fp_yuv2);
        free(bufferData);
    });
}

- (void)stopVideoYuv2 {
    dispatch_async(self.fileQueue, ^{
        if (!self.fp_yuv2) {
            return;
        }
        fclose(self.fp_yuv2);
        self.fp_yuv2 = NULL;
        NSLog(@"close yuv file ");
    });
}

- (void)writeVideoH264:(NSData *)data {
    dispatch_async(self.fileQueue, ^{
        if (!self.isRunning) {
            return;
        }
        if (!self.fileHandleVideo) {
            //创建输出文件
            NSString *filePath = geth264FilePath();
            
            NSString *log = [NSString stringWithFormat:@"编码的H264文件: ffplay %@", filePath];
            [self.commandLines addObject:log];
            
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            BOOL creatFile = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
            if (!creatFile) {
                NSLog(@"文件创建失败");
            }
            
            //写入文件
            self.fileHandleVideo = [NSFileHandle fileHandleForWritingAtPath:filePath];
        }
        
        [self.fileHandleVideo seekToEndOfFile];
        [self.fileHandleVideo writeData:data];
    });
}

- (void)stopVideoH264 {
    if (!self.fileHandleVideo)
    {
        return;
    }
    [self.fileHandleVideo  closeFile];
    self.fileHandleVideo = nil;
}

#pragma mark - log

- (void)printASBD:(AudioStreamBasicDescription)ASBD {
    
    [[JBFileManager shareInstance] print_ca_format:ASBD.mFormatFlags bits:ASBD.mBitsPerChannel];
    
    NSMutableString * str = [NSMutableString stringWithString:@"\nASBD: \n"];
    [str appendFormat:@"\tmSampleRate = %.f\n", ASBD.mSampleRate];
    [str appendFormat:@"\tmFormatID = %u\n", (unsigned int)ASBD.mFormatID];
    [str appendFormat:@"\tmFormatFlags = %u\n", (unsigned int)ASBD.mFormatFlags];
    [str appendFormat:@"\tmBytesPerPacket = %u\n", ASBD.mBytesPerPacket];
    [str appendFormat:@"\tmFramesPerPacket = %u\n", ASBD.mFramesPerPacket];
    [str appendFormat:@"\tmBytesPerFrame = %u\n", ASBD.mBytesPerFrame];
    [str appendFormat:@"\tmChannelsPerFrame = %u\n", ASBD.mChannelsPerFrame];
    [str appendFormat:@"\tmBitsPerChannel = %u\n", ASBD.mBitsPerChannel];
    [str appendFormat:@"\tmReserved = %i\n", ASBD.mReserved];
    NSLog(@"%@", str);
}

- (void)print_ca_format:(UInt32)format_flags bits:(UInt32)bits
{
    bool planar = (format_flags & kAudioFormatFlagIsNonInterleaved) != 0;
    NSLog(@"planar:%d bitsPerchannel:%d", planar, bits);
    if (format_flags & kAudioFormatFlagIsFloat)
        NSLog(@"kAudioFormatFlagIsFloat");
    
    if (format_flags & kAudioFormatFlagIsBigEndian)
        NSLog(@"kAudioFormatFlagIsBigEndian");
    
    if (format_flags & kAudioFormatFlagIsSignedInteger)
        NSLog(@"kAudioFormatFlagIsSignedInteger");
    if (format_flags & kAudioFormatFlagIsPacked)
        NSLog(@"kAudioFormatFlagIsPacked");
    if (format_flags & kAudioFormatFlagIsAlignedHigh)
        NSLog(@"kAudioFormatFlagIsAlignedHigh");
    if (format_flags & kAudioFormatFlagIsNonInterleaved)
        NSLog(@"kAudioFormatFlagIsNonInterleaved");
    if (format_flags & kAudioFormatFlagIsNonMixable)
        NSLog(@"kAudioFormatFlagIsNonMixable");
    
    return ;
}

- (void)prisnFFmpegLogWithASBD:(AudioStreamBasicDescription)ASBD preLog:(NSString *)preLog {
    bool planar = (ASBD.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (planar) {
        NSLog(@"not support planar pcm");
        return;
    }
    
    NSString *typeString = @"f";
    if (ASBD.mFormatFlags & kAudioFormatFlagIsSignedInteger) {
        typeString = @"s";
    }
    
    NSString *isBigString = @"le";
    if (ASBD.mFormatFlags & kLinearPCMFormatFlagIsBigEndian) {
        isBigString =  @"be";
    }
    
    NSString *formatString = [NSString stringWithFormat:@"%@%d%@", typeString, ASBD.mBitsPerChannel, isBigString];
    
    NSString *log = [NSString stringWithFormat:@"%@ ffplay -ar %i -ac %d -f %@ %@",preLog, (int)ASBD.mSampleRate, ASBD.mChannelsPerFrame,formatString, getPcmFilePath()];
//    NSLog(@"%@", log);
    [self.commandLines addObject:log];
}

- (NSString *)printVideoFormat:(NSInteger)subtype logPre:(NSString *)logPre
{
    NSString *formatType = @"unknown";
    switch (subtype) {
        case kCVPixelFormatType_422YpCbCr8:
            NSLog(@"%@ kCVPixelFormatType_422YpCbCr8 -> FORMAT::UYVY", logPre);
            break;
        case kCVPixelFormatType_422YpCbCr8_yuvs:
            NSLog(@"%@ kCVPixelFormatType_422YpCbCr8_yuvs -> FORMAT::YUY2", logPre);
            break;
        case kCVPixelFormatType_24RGB:
            NSLog(@"%@ kCVPixelFormatType_24RGB -> FORMAT::XRGB", logPre);
            break;
        case kCVPixelFormatType_32ARGB:
            NSLog(@"%@ kCVPixelFormatType_32ARGB -> FORMAT::ARGB", logPre);
            formatType = @"argb";
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            NSLog(@"%@ kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange -> FORMAT::NV12", logPre);
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            NSLog(@"%@ kCVPixelFormatType_420YpCbCr8BiPlanarFullRange -> FORMAT::NV12", logPre);
            break;
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            NSLog(@"%@ kCVPixelFormatType_420YpCbCr8PlanarFullRange -> FORMAT::420p", logPre);
            break;
        default:
            NSLog(@"%@ FORMAT::DVF_UNKNOWN %ld", logPre, subtype);
            break;
    }
    return formatType;
    /**
     https://ffmpeg.org/doxygen/3.0/ffmpeg__videotoolbox_8c_source.html
          switch (pixel_format) {
          case kCVPixelFormatType_420YpCbCr8Planar: vt->tmp_frame->format = AV_PIX_FMT_YUV420P; break;
          case kCVPixelFormatType_422YpCbCr8:       vt->tmp_frame->format = AV_PIX_FMT_UYVY422; break;
          case kCVPixelFormatType_32BGRA:           vt->tmp_frame->format = AV_PIX_FMT_BGRA; break;
      #ifdef kCFCoreFoundationVersionNumber10_7
          case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: vt->tmp_frame->format = AV_PIX_FMT_NV12; break;
      #endif
          default:
              av_get_codec_tag_string(codec_str, sizeof(codec_str), s->codec_tag);
              av_log(NULL, AV_LOG_ERROR,
                     "%s: Unsupported pixel format: %s\n", codec_str, videotoolbox_pixfmt);
              return AVERROR(ENOSYS);
          }
     */
    
    
    /**
     //https://www.ffmpeg.org/doxygen/3.2/videotoolboxenc_8c_source.html
         if (fmt == AV_PIX_FMT_NV12) {
             *av_pixel_format = range == AVCOL_RANGE_JPEG ?
                                             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange :
                                             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
         } else if (fmt == AV_PIX_FMT_YUV420P) {
             *av_pixel_format = range == AVCOL_RANGE_JPEG ?
                                             kCVPixelFormatType_420YpCbCr8PlanarFullRange :
                                             kCVPixelFormatType_420YpCbCr8Planar;
         } else {
             return AVERROR(EINVAL);
         }
     */
    
    
    /**
     做过iOS硬解码的都知道，创建解码器时，需要指定PixelFormatType。IOS只支持NV12也就是YUV420中的一种，你搜索420，发现有四个，分别如下：

     kCVPixelFormatType_420YpCbCr8Planar

     kCVPixelFormatType_420YpCbCr8PlanarFullRange

     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

     kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

     根据表面意思，可以看出，可以分为两类：planar（平面420p）和 BiPlanar(双平面)。

     还有一个办法区分，CVPixelBufferGetPlaneCount（pixel）获取平面数量，发现kCVPixelFormatType_420YpCbCr8Planar和kCVPixelFormatType_420YpCbCr8PlanarFullRange是三个两面，属于420p，iOS不支持。而kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange和kCVPixelFormatType_420YpCbCr8BiPlanarFullRange是两个平面。这就纠结了，到底用哪一个呢？
     */
}

- (void)printFFmpegLogWithYuv:(FourCharCode)fourcc dimensions:(CMVideoDimensions)dims isCapture:(BOOL)isCapture {
    NSString *formatType = [self printVideoFormat:fourcc logPre:@"采集到的像素格式"];
    
    NSString *filePath = isCapture ? getyuvFilePath() : getyuv2FilePath();
    NSString *logPre = isCapture ? @"采集到的YUV：" : @"解码出的YUV：";
    
    NSString *log = [NSString stringWithFormat:@"%@ ffplay -video_size %dx%d -pixel_format %@ %@", logPre, dims.width, dims.height, formatType, filePath];
    [self.commandLines addObject:log];
}

@end
