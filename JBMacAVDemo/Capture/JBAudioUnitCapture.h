//
//  JBAudioUnitCapture.h
//  JBMacAVDemo
//
//  Created by jimbo on 2023/6/26.
//

#import <Foundation/Foundation.h>
#import "JBConfigData.h"

NS_ASSUME_NONNULL_BEGIN


@protocol JBAudioUnitCaptureDelegate <NSObject>
- (void)capturedData:(void *)bufferData buffersize:(UInt32)buffersize;
@end


@interface JBAudioUnitCapture : NSObject
+ (instancetype)shareInstance;
- (void)start;
@property(nonatomic, weak) id<JBAudioUnitCaptureDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
