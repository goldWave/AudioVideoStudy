//
//  JBVideoEncoder.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <assert.h>

#if TARGET_RT_BIG_ENDIAN
#   define FourCC2Str(fourcc) (const char[]){*((char*)&fourcc), *(((char*)&fourcc)+1), *(((char*)&fourcc)+2), *(((char*)&fourcc)+3),0}
#else
#   define FourCC2Str(fourcc) (const char[]){*(((char*)&fourcc)+3), *(((char*)&fourcc)+2), *(((char*)&fourcc)+1), *(((char*)&fourcc)+0),0}
#endif

#define printErr(logStr, status) \
    if (status != noErr) {\
        NSLog(@"%@ 出现错误: %d(%s)", logStr, (int)status, FourCC2Str(status));\
    }

#define JBAssertNoError(inError, inMessage)                                                \
{                                                                            \
SInt32 __Err = (inError);                                                \
if(__Err != 0)                                                            \
{                                                                        \
NSLog(@"==== 出现错误: %@ code: %d(%s)", inMessage, __Err, FourCC2Str(__Err));\
assert(__Err == 0); \
}\
}

//#define printErr(logStr, status) \
//        NSLog(@"%@ : %d", logStr, (int)status);

extern  NSString * _Nonnull const JBStopNotification;


typedef NS_ENUM(int, JBCaptureType) {
    JBCaptureTypeAll = 0,
    JBCaptureTypeAudio,
    JBCaptureTypeVideo,
    JBCaptureTypeUnknown
};

typedef NS_ENUM(int, JBAudioCapture) {
    JBAudioCaptureAVFoundation = 0,
    JBAudioCaptureAudioQueue,
    JBAudioCaptureAudioUnit,
    JBAudioCaptureNone
};

struct AudioStreamBasicDescription;


struct JBVideoData
{
    NSInteger width;//可选，系统支持的分辨率，采集分辨率的宽
    NSInteger height;//可选，系统支持的分辨率，采集分辨率的高
    NSInteger videoBitrate;//自由设置
    NSInteger fps;//自由设置 30
};
//typedef struct JBVideoData  JBVideoData;


@interface JBConfigData : NSObject

+ (instancetype _Nonnull )shareInstance;

@property (nonatomic, assign) struct AudioStreamBasicDescription  captureASBD;
@property (nonatomic, assign) struct AudioStreamBasicDescription  encodeASBD;

@property (nonatomic, assign) struct JBVideoData captureVideo;

//@property (nonatomic, assign) JBCaptureType type;
//
////视频
//@property (nonatomic, assign) NSInteger width;//可选，系统支持的分辨率，采集分辨率的宽
//@property (nonatomic, assign) NSInteger height;//可选，系统支持的分辨率，采集分辨率的高
//@property (nonatomic, assign) NSInteger videoBitrate;//自由设置
//@property (nonatomic, assign) NSInteger fps;//自由设置 30
//
////音频
//
/////**码率*/
////@property (nonatomic, assign) NSInteger audioBitrate;//96000）
/////**声道*/
////@property (nonatomic, assign) NSInteger channelCount;//（2）
/////**采样率*/
////@property (nonatomic, assign) NSInteger sampleRate;//(默认44100)
/////**采样点量化*/
////@property (nonatomic, assign) NSInteger sampleSize;//(16)
//
//
//@property (nonatomic) struct AudioStreamBasicDescription  mASBD;

//+ (instancetype)defaultConifgWithType:(JBCaptureType)type;
@end
