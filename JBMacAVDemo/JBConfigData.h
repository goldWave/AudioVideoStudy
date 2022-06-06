//
//  JBVideoEncoder.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import <Foundation/Foundation.h>

#define printErr(logStr, status) \
    if (status != noErr) {\
        NSLog(@"%@ 出现错误: %d", logStr, (int)status);\
    }


typedef NS_ENUM(int, JBCaptureType) {
    JBCaptureTypeAll = 0,
    JBCaptureTypeAudio,
    JBCaptureTypeVideo,
    JBCaptureTypeUnknown
};

struct AudioStreamBasicDescription;


@interface JBConfigData : NSObject

@property (nonatomic, assign) JBCaptureType type;

//视频
@property (nonatomic, assign) NSInteger width;//可选，系统支持的分辨率，采集分辨率的宽
@property (nonatomic, assign) NSInteger height;//可选，系统支持的分辨率，采集分辨率的高
@property (nonatomic, assign) NSInteger videoBitrate;//自由设置
@property (nonatomic, assign) NSInteger fps;//自由设置 30

//音频

///**码率*/
//@property (nonatomic, assign) NSInteger audioBitrate;//96000）
///**声道*/
//@property (nonatomic, assign) NSInteger channelCount;//（2）
///**采样率*/
//@property (nonatomic, assign) NSInteger sampleRate;//(默认44100)
///**采样点量化*/
//@property (nonatomic, assign) NSInteger sampleSize;//(16)


@property (nonatomic) struct AudioStreamBasicDescription  mASBD;

//+ (instancetype)defaultConifgWithType:(JBCaptureType)type;
@end
