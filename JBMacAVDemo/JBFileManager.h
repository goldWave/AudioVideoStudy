//
//  JBFileManager.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface JBFileManager : NSObject

+ (instancetype)shareInstance;

@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NSMutableArray *commandLines;



- (void)stopAllFile;

- (void)writeAudioPCM:(CMSampleBufferRef)sampleBuffer;
- (void)writeAudioPCM:(void *)bufferData buffersize:(UInt32)buffersize;
- (void)writeAudioPCM2:(void *)bufferData buffersize:(UInt32)buffersize;
- (void)stopAudioPCM;
- (void)stopAudioPCM2;

- (void)writeAudioAAC:(NSData *)data;
- (void)stopAudioAAC;

- (void)writeVideoYuv:(void *)bufferData buffersize:(UInt32)buffersize;
- (void)stopVideoYuv;

- (void)writeVideoYuv2:(void *)bufferData buffersize:(UInt32)buffersize;
- (void)stopVideoYuv2;


- (void)writeVideoH264:(NSData *)data;
- (void)stopVideoH264;

//print audio
+ (void)printASBD:(AudioStreamBasicDescription)ASBD;
+ (void)print_ca_format:(UInt32)format_flags bits:(UInt32)bits;
- (void)prisnFFmpegLogWithASBD:(AudioStreamBasicDescription)ASBD preLog:(NSString *)preLog;

//print video
- (NSString *)printVideoFormat:(NSInteger)subtype logPre:(NSString *)logPre;
- (void)printFFmpegLogWithYuv:(FourCharCode)fourcc dimensions:(CMVideoDimensions)dims  isCapture:(BOOL)isCapture;
@end
