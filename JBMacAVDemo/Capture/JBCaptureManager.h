//
//  JBCaptureManager.h
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/20.
//

#import <Foundation/Foundation.h>
#import <cocoa/cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "JBConfigData.h"

NS_ASSUME_NONNULL_BEGIN


typedef struct JBCaptureOutData* JBCaptureOutDataRef;


@protocol JBCaptureDelegate <NSObject>

- (void)captureOutputVideoData:(_Nullable CVImageBufferRef)pixelBuffer;
- (void)captureOutputAudioData:(unsigned char *)bufferData lenght:(size_t)lenght;

@end

@interface JBCaptureManager : NSObject

@property(nonatomic, weak) id<JBCaptureDelegate> delegate;

@property(nonatomic, assign) JBCaptureType type;
@property(nonatomic, weak) CALayer *parentLayer;

//- (instancetype)initWithType:(JBCaptureType)type parenLayerIfVideo:(CALayer * __nullable)parentLayer;
//- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (void)start;
@end

NS_ASSUME_NONNULL_END
