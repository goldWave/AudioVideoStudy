//
//  JBAudioQueueCapture.h
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/8.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "JBConfigData.h"


NS_ASSUME_NONNULL_BEGIN


@protocol JBAudioQueueCaptureDelegate <NSObject>
- (void)capturedData:(void *)bufferData buffersize:(UInt32)buffersize;
@end


@interface JBAudioQueueCapture : NSObject
+ (instancetype)shareInstance;
- (void)start;
@property(nonatomic, weak) id<JBAudioQueueCaptureDelegate> delegate;

@property (nonatomic, strong) JBConfigData *audioConfigData;


@end

NS_ASSUME_NONNULL_END
