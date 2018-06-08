//
//  ViewController.m
//  Demo
//
//  Created by hc on 2018/6/8.
//  Copyright © 2018年 hc. All rights reserved.
//

#import "ViewController.h"
#import <RTMPPlayKit/RTMPPlayer.h>

@interface ViewController ()

@property (nonatomic,strong) RTMPPlayer* player;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.view.backgroundColor = [UIColor blackColor];
    
    _player = [[RTMPPlayer alloc] initWithURL:@"rtmp://your_url"];
    UIView* view = _player.videoView;
    view.frame = self.view.bounds;
    [self.view addSubview:view];
    [_player play];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
