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

@protocol JBVideoDecoderDelegate <NSObject>

- (void)videoDecoderCallback:(CVPixelBufferRef _Nullable)imageBuffer;

@end


@interface JBVideoDecoder : NSObject

- (instancetype)initWithData:(JBConfigData *)data;

- (void)decodeNaluData:(NSData *)frame;

@property(nonatomic, weak) id<JBVideoDecoderDelegate> delegate;
@property(nonatomic, strong) dispatch_queue_t callbackQueue;
@end

NS_ASSUME_NONNULL_END
