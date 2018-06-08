//
//  VideoView.h
//  RTMPPlayerDemo
//
//  Created by hc on 2018/6/5.
//  Copyright © 2018年 hc. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface VideoView : UIView

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end
