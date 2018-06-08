//
//  PacketQueue.m
//  RTMPPlayerDemo
//
//  Created by hc on 2018/6/5.
//  Copyright © 2018年 hc. All rights reserved.
//

#import "PacketQueue.h"
@interface AVPacket (){
    PILI_RTMPPacket* _packet;
}

@end

@implementation AVPacket
- (id)initWithRTMPPacket:(PILI_RTMPPacket*)packet{
    if (self = [super init]){
        _packet = packet;
    }
    
    return self;
}

- (PILI_RTMPPacket*)rtmpPacket{
    return _packet;
}

- (void)dealloc{
    if (_packet){
        PILI_RTMPPacket_Free(_packet);
        free(_packet);
    }
}
@end

@interface PacketQueue ()

@property (nonatomic,strong) NSCondition* condition;
@property (nonatomic,strong) NSMutableArray<AVPacket*>* queue;

@end

@implementation PacketQueue
- (id)init{
    if (self = [super init]){
        _condition = [NSCondition new];
        _queue = [NSMutableArray arrayWithCapacity:8];
        _maxQueueCount = 400;
    }
    
    return self;
}

- (void)pushPacket:(AVPacket*)packet{
    [_condition lock];
    [_queue addObject:packet];
    
    if (_queue.count > _maxQueueCount){
        [_queue removeObjectAtIndex:0];
    }

    if (_queue.count == 1){
        [_condition signal];
    }

    [_condition unlock];
}

- (AVPacket*)popPacket{
    AVPacket* packet = nil;
    [_condition lock];
    
    if (_queue.count == 0) {
        [_condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    }
    
    if (_queue.count > 0){
        packet = _queue.firstObject;
        [_queue removeObjectAtIndex:0];
    }
    
    [_condition unlock];
    
    return packet;
}
@end
