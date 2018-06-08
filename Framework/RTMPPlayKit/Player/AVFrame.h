//
//  AVFrame.h
//  RTMPPlayerDemo
//
//  Created by hc on 2018/6/6.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AVFrame : NSObject
@property (nonatomic,strong) NSData* data;
@property (nonatomic,assign) uint32_t timestamp;
@end
