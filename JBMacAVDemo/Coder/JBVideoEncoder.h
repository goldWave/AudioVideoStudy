//
//  JBVideoDecoder.h
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/16.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "JBConfigData.h"

NS_ASSUME_NONNULL_BEGIN

@protocol JBVideoEncoderDelegate <NSObject>

//Video-H264数据编码完成回调
- (void)videoEncodeCallback:(NSData *)h264Data;
//Video-SPS&PPS数据编码回调
- (void)videoEncodeCallbacksps:(NSData *)sps pps:(NSData *)pps;

@end


@interface JBVideoEncoder : NSObject

- (instancetype)initWithData:(JBConfigData *)data;

-(void)encodeThePixelBuffer:(CVImageBufferRef)imageBuffer;

@property(nonatomic, weak) id<JBVideoEncoderDelegate> delegate;

@property(nonatomic, assign) BOOL isGotSpsPps;
@property (nonatomic, strong) JBConfigData *configData;
@end

NS_ASSUME_NONNULL_END
