//
//  RTMPClient.h
//  RTMPPlayerDemo
//
//  Created by hc on 2018/5/30.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "rtmp.h"


typedef NS_ENUM(NSInteger, RTMPClientState) {
    RTMPClientPrepare,
    RTMPClientStart,
    RTMPClientStop,
    RTMPClientReconnect,
    RTMPClientError
};

@protocol RTMPClientDelegate <NSObject>

- (void)clientStateChanged:(RTMPClientState)state error:(int)code;

@end



@interface RTMPClient : NSObject

- (id)initWithURL:(NSString*)url;

- (void)start;
- (void)stop:(void (^)(void))handler;
- (BOOL)isRunning;

@property (nonatomic, assign) NSInteger reconnectCount;
@property (nonatomic, assign) NSInteger reconnectInterval;

@property (nonatomic,copy) void (^infoReceiveBlock)(PILI_RTMPPacket* packet);
@property (nonatomic,copy) void (^audioReceiveBlock)(PILI_RTMPPacket* packet);
@property (nonatomic,copy) void (^videoReceiveBlock)(PILI_RTMPPacket* packet);

@property (nonatomic,weak) id<RTMPClientDelegate> delegate;

@end
