//
//  PacketQueue.h
//  RTMPPlayerDemo
//
//  Created by hc on 2018/6/5.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "rtmp.h"

@interface AVPacket : NSObject

- (id)initWithRTMPPacket:(PILI_RTMPPacket*)packet;
- (PILI_RTMPPacket*)rtmpPacket;

@end

@interface PacketQueue : NSObject
- (void)pushPacket:(AVPacket*)packet;
- (AVPacket*)popPacket;

@property (nonatomic,assign) NSInteger maxQueueCount;

@end
