//
//  VideoDecoder.h
//  PlayTest
//
//  Created by hc on 2018/1/11.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

@interface VideoDecoder : NSObject

- (void)setupWithSPS:(NSData*)sps pps:(NSData*)pps;

- (void)decodeFrame:(unsigned char*)buffer bufferLen:(long)len;

- (void)clean;

@property (nonatomic,copy) void (^newFrameAvailableBlock)(CVPixelBufferRef pixelBuffer);
@end
