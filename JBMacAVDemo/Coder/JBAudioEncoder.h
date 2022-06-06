//
//  JBAudioEncoder.h
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/21.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "JBConfigData.h"

NS_ASSUME_NONNULL_BEGIN

@protocol JBAudioEncoderDelegate <NSObject>

- (void)audioEncoderCallback:(NSData *)aacData;

@end


@interface JBAudioEncoder : NSObject

- (instancetype)initWithData:(JBConfigData *)data;

//- (void)startEncoder:(CMSampleBufferRef )sampleBuffer;
- (void)startEncoder:(void *)bufferData buffersize:(UInt32)buffersize;

//@property(nonatomic, assign) CMSampleBufferRef sampleBuffer;
@property(nonatomic, weak) id<JBAudioEncoderDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
