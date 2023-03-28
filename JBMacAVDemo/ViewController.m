//
//  ViewController.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2021/11/1.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "JBCaptureManager.h"
#import "JBVideoDecoder.h"
#import "JBVideoEncoder.h"
#import "JBAudioEncoder.h"
#import "JBAudioQueueCapture.h"
#import "JBFileManager.h"

@interface ViewController () <JBCaptureDelegate, JBVideoDecoderDelegate, JBVideoEncoderDelegate, JBAudioEncoderDelegate, JBAudioQueueCaptureDelegate>
@property (weak) IBOutlet NSView *captureView;
@property (weak) IBOutlet NSButton *startBtn;


@property (nonatomic, strong)JBCaptureManager *captureManager;
@property(nonatomic, strong) JBVideoEncoder *videoEncoder;
@property(nonatomic, strong) JBVideoDecoder *videoDecoder;

@property(nonatomic, strong) JBAudioEncoder *audioEncoder;

@property (weak) IBOutlet NSImageView *decoderImageView;

@property(nonatomic, assign) JBCaptureType captureType;
@property(nonatomic, assign) JBCaptureType avCaptureSessionType; //AVCaptureSession 负责的模块

@property(nonatomic, assign) BOOL isRunning;

@property(nonatomic, assign) NSTimeInterval timeStamp;
@property (nonatomic, strong) NSTimer *timer;
@property (weak) IBOutlet NSTextField *timeLabel;

@property(nonatomic, assign) bool isAudioQueueCapture; //YES： audio queue 捕获音频，  NO：AVCaptureSession 捕获音频

@property (nonatomic, strong) JBConfigData *audioCaptureData;
@property (weak) IBOutlet NSPopUpButton *audioTypeBtn;
@property (weak) IBOutlet NSPopUpButton *selectTypeBtn;

@property(nonatomic, assign) int  encodeIndex;
@property (weak) IBOutlet NSView *decodeBgView;

@end



@implementation ViewController

static NSTimeInterval getCurrentTimestamp() {
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:0]; // 获取当前时间0秒后的时间
    NSTimeInterval time = [date timeIntervalSince1970];// *1000 是精确到毫秒(13位),不乘就是精确到秒(10位)
    return time;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.captureView.wantsLayer = YES;
    self.captureView.layer.backgroundColor = NSColor.blackColor.CGColor;
    
    
    self.decodeBgView.wantsLayer = YES;
    self.decodeBgView.layer.backgroundColor = NSColor.blackColor.CGColor;
    
    self.isRunning = NO;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:NSApplicationWillTerminateNotification object:nil];
    
    [self.audioTypeBtn selectItemAtIndex:1];
    self.captureType =  (JBCaptureType)self.selectTypeBtn.indexOfSelectedItem;
    [self checkAuthorized];
}

- (void)appWillTerminate {
    if (self.isRunning) {
        [self.captureManager stopCapture];
    }
}

- (NSString *)timeFormat:(int)totalSeconds
{
    
    int seconds = totalSeconds % 60;
    int minutes = (totalSeconds / 60) % 60;
    int hours = totalSeconds / 3600;
    
    return [NSString stringWithFormat:@"%02d:%02d:%02d",hours, minutes, seconds];
}

-(void)stopCapture {
    
    [[JBAudioQueueCapture shareInstance] stopAudioCapture];
    
    if(self.captureManager) {
        [self.captureManager stopCapture];
    }
}

- (BOOL)isConatainCaptureVideo {
    return  self.captureType == JBCaptureTypeVideo || self.captureType == JBCaptureTypeAll;
}

- (BOOL)isConatainCaptureAudio {
    return  self.captureType == JBCaptureTypeAudio || self.captureType == JBCaptureTypeAll;
}

- (IBAction)startBtnClick:(id)sender {
    
    self.encodeIndex = 0;
    
    self.isRunning = !self.isRunning;
    
    self.startBtn.title = self.isRunning ? @"停止录制并编码" : @"开始录制并编码";
    
    self.audioTypeBtn.enabled = !self.isRunning;
    self.selectTypeBtn.enabled = !self.isRunning;
    
    if (self.isRunning) {
        [self checkAuthorized];
        //判断是否  进行 音频和视频的采集
        //如果要采集音频， 判断是用 audio queue 采集， 还是AVCaptureSession 采集
        self.isAudioQueueCapture = self.audioTypeBtn.indexOfSelectedItem == 0;
        self.captureType = (JBCaptureType)self.selectTypeBtn.indexOfSelectedItem;
        
        if (!self.isAudioQueueCapture) {
            self.avCaptureSessionType = self.captureType;
        } else {
            //音频不是由 avcapturesession 负责
            if ([self isConatainCaptureVideo]) {
                self.avCaptureSessionType = JBCaptureTypeVideo;
            } else {
                self.avCaptureSessionType = JBCaptureTypeUnknown;
            }
        }
        self.timeStamp = getCurrentTimestamp();
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.f repeats:YES block:^(NSTimer * _Nonnull timer) {
            NSTimeInterval diff = getCurrentTimestamp() - self.timeStamp;
            [self.timeLabel setStringValue:[self timeFormat:(int)diff]];
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        
        if (self.isAudioQueueCapture && [self isConatainCaptureAudio])
        {
            //audio queue 采集音频
            [[JBAudioQueueCapture shareInstance] startAudioCapture];
            [JBAudioQueueCapture shareInstance].delegate = self;
        }
        
        if (self.avCaptureSessionType != JBCaptureTypeUnknown) {
            //avcapture session 采集
            self.captureManager = [[JBCaptureManager alloc] initWithType:self.avCaptureSessionType parenLayerIfVideo:self.captureView.layer];
            self.captureManager.delegate = self;
            [self.captureManager prepare];
            [self.captureManager startCapture];
        }
    } else {
        [self stopCapture];
        [[JBFileManager shareInstance] stopAllFile];
        [_timer invalidate];
        _timer = nil;
        self.audioCaptureData = NULL;
    }
}


#pragma mark - JBCaptureDelegate 音视频采集
- (void)captureOutputAudioData:(unsigned char *)bufferData lenght:(size_t)lenght
{
    //采集后的数据，直接 会扔入 解码器
    if(!self.audioCaptureData) {
        self.audioCaptureData = self.captureManager.audioConfigData;
    }
    [self sendAudioToEncoerAndFile:bufferData buffersize:(UInt32)lenght];
    
}

- (void)captureOutputVideoData:(_Nullable CVImageBufferRef)imgBuffer {
    
    CVPixelBufferRetain(imgBuffer);
    [self.videoEncoder encodeThePixelBuffer:imgBuffer];
    CVPixelBufferRelease(imgBuffer);
}


#pragma mark - audio queue capture delegate  音频采集

- (void)capturedData:(void *)bufferData buffersize:(UInt32)buffersize {
    if(!self.audioCaptureData) {
        self.audioCaptureData = [JBAudioQueueCapture shareInstance].audioConfigData;
    }
    [self sendAudioToEncoerAndFile:bufferData buffersize:buffersize];
}

- (void)sendAudioToEncoerAndFile:(void *)bufferData buffersize:(UInt32)buffersize{
    [[JBFileManager shareInstance] writeAudioPCM:bufferData buffersize:buffersize];

    if (!self.audioEncoder) {
        //需要在audioConfigData 的asbd 确认好了，才创建解码器，不然参数有问题
        self.audioEncoder = [[JBAudioEncoder alloc] initWithData:self.audioCaptureData];
        self.audioEncoder.delegate = self;
        [[JBFileManager shareInstance] prisnFFmpegLogWithASBD:self.audioCaptureData.mASBD preLog:@"原始音频："];
    }
    [self.audioEncoder startEncoder:bufferData buffersize:buffersize];
}


#pragma mark - JBVideoEncoderDelegate   视频编码回调
//Video-H264数据编码完成回调
- (void)videoEncodeCallback:(NSData *)h264Data {
    
    //写入文件
    [[JBFileManager shareInstance] writeVideoH264:h264Data.mutableCopy];
    
    [self.videoDecoder decodeNaluData:h264Data];
    
}
//Video-SPS&PPS数据编码回调
- (void)videoEncodeCallbacksps:(NSData *)sps pps:(NSData *)pps {
    
    //写入文件
    [[JBFileManager shareInstance] writeVideoH264:sps.mutableCopy];
    [[JBFileManager shareInstance] writeVideoH264:pps.mutableCopy];
    
    [self.videoDecoder decodeNaluData:sps];
    [self.videoDecoder decodeNaluData:pps];
    
    
}

//转换图片
- (NSImage *)imageFromSampleBuffer:(CVImageBufferRef) imageBuffer {
    // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象

    // 锁定pixel buffer的基地址
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // 得到pixel buffer的基地址
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // 得到pixel buffer的行字节数
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 得到pixel buffer的宽和高
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

    /**
     * kCGColorSpaceGenericGray  灰度图 0-1
     * CGColorSpaceCreateDeviceRGB  RGB三原色
     * kCGColorSpaceGenericCMYK  CMYK打印色，青色，品红色，黄色和黑色
     * */

    // 创建一个依赖于设备的RGB颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
//    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
//                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    //具体位图支持形式，查看本目录的apple_bit_support.png， 
    //RGB和YUV并不支持24位的，所有需要转换成位图的话，需要进行提前转换32位后才能使用。
    //https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-CJBHBFFE
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGImageAlphaPremultipliedFirst);
    
    if(!context) {
        NSLog(@"context is 无效");
    }
    // 根据这个位图context中的像素数据创建一个Quartz image对象
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // 释放context和颜色空间
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // 用Quartz image创建一个UIImage对象image
    NSImage *image = [[NSImage alloc] initWithCGImage:quartzImage size:NSMakeSize(width, height)];
    // 释放Quartz image对象
    CGImageRelease(quartzImage);
    
    return (image);
}


- (void)showPixelImage:(CVPixelBufferRef)pixelBuffer  {
    
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.decoderImageView setImage:[self imageFromSampleBuffer:pixelBuffer]];
        CVPixelBufferRelease(pixelBuffer);
    });
}


#pragma mark - JBVideoDecoderDelegate 视频解码回调
//解码后的数据
- (void)videoDecoderCallback:(CVPixelBufferRef)pixelBuffer {
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    void *src_buf  = CVPixelBufferGetBaseAddress(pixelBuffer);

    size_t length = bytesPerRow * height;
    unsigned char *newedImgBuff = (unsigned char *)malloc(length);
    memmove(newedImgBuff, src_buf, length);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
   
    [[JBFileManager shareInstance] writeVideoYuv2:newedImgBuff buffersize:(UInt32)length];
    
    //将解码出的视频，展示到 屏幕上
    [self showPixelImage:pixelBuffer];
    
    //回调前retain了，现在必须release
    CVPixelBufferRelease(pixelBuffer);
}


#pragma mark - audio encoder delegate 音频编码回调
- (void)audioEncoderCallback:(NSData *)aacData {
    [[JBFileManager shareInstance] writeAudioAAC:aacData];
}

#pragma mark - auth
- (void)checkAuthorized
{
    if (self.captureType == JBCaptureTypeVideo || JBCaptureTypeAll == self.captureType) {
        if (@available(macOS 10.14, *)) {
            AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            if (authStatus == AVAuthorizationStatusAuthorized) {
                NSLog(@"AVMediaTypeVideo已授权");
            } else if (authStatus == AVAuthorizationStatusDenied || authStatus == AVAuthorizationStatusRestricted) {
                NSLog(@"AVMediaTypeVideo拒绝使用");
            } else if (authStatus == AVAuthorizationStatusNotDetermined) {
                //第一次调用状态是NotDetermined, 去获得授权
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                         completionHandler:^(BOOL granted) {
                    NSLog(@"AVMediaTypeVideo 获取授权成功");
                }];
                return;
            }
        } else {
            //直接使用
            NSLog(@"AVMediaTypeVideo直接使用");
        }
    }
    if (self.captureType == JBCaptureTypeAudio || JBCaptureTypeAll == self.captureType) {
        if (@available(macOS 10.14, *)) {
            AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
            if (authStatus == AVAuthorizationStatusAuthorized) {
                NSLog(@"AVMediaTypeVideo已授权");
            } else if (authStatus == AVAuthorizationStatusDenied || authStatus == AVAuthorizationStatusRestricted) {
                NSLog(@"AVMediaTypeVideo拒绝使用");
            } else if (authStatus == AVAuthorizationStatusNotDetermined) {
                //第一次调用状态是NotDetermined, 去获得授权
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                                         completionHandler:^(BOOL granted) {
                    NSLog(@"AVMediaTypeVideo 获取授权成功");
                }];
                return;
            }
        } else {
            //直接使用
            NSLog(@"AVMediaTypeVideo直接使用");
        }
    }
}

- (void)setIsRunning:(BOOL)isRunning {
    _isRunning = isRunning;
    [JBFileManager shareInstance].isRunning = isRunning;
}

- (JBVideoEncoder *)videoEncoder {
        if (!_videoEncoder) {
            _videoEncoder = [[JBVideoEncoder alloc] initWithData:self.captureManager.videoConfigData];
            _videoEncoder.delegate = self;
        }
    return _videoEncoder;
}

- (JBVideoDecoder *)videoDecoder {
    if (!_videoDecoder) {
            //需要在audioConfigData 的asbd 确认好了，才创建解码器，不然参数有问题
            _videoDecoder = [[JBVideoDecoder alloc] initWithData:self.videoEncoder.configData];
            _videoDecoder.delegate = self;
    }
    return _videoDecoder;
}

@end
