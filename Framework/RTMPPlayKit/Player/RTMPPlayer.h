//
//  RTMPPlayer.h
//  RTMPPlayerDemo
//
//  Created by hc on 2018/5/31.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RTMPPlayerState) {
    RTMPPlayerPrepare,
    RTMPPlayerStart,
    RTMPPlayerStop,
    RTMPPlayerFail
};

@protocol RTMPPlayerDelegate <NSObject>

- (void)playerStateChanged:(RTMPPlayerState)state error:(int)code;

@end

@interface RTMPPlayer : NSObject
- (id)initWithURL:(NSString*)url;
- (void)play;
- (void)stop;

@property (nonatomic,strong,readonly) UIView* videoView;
@property (nonatomic,assign) CGFloat volume;
@property (nonatomic,weak) id<RTMPPlayerDelegate> delegate;

@end
