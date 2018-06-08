//
//  RTMPPlayer.m
//  RTMPPlayerDemo
//
//  Created by hc on 2018/5/31.
//  Copyright © 2018年 hc. All rights reserved.
//

#import "RTMPPlayer.h"
#import "RTMPClient.h"
#import <endian.h>
#import "VideoDecoder.h"
#import "AACDecoder.h"
#import "AudioBufferPlayer.h"
#import "PacketQueue.h"
#import "VideoView.h"
#import "AVFrame.h"

struct audio_specific_config_s {
    union {
#if (__BYTE_ORDER == __LITTLE_ENDIAN)
        struct {
            unsigned int
            extension_flag : 1,
            dependson_corecoder : 1,
            frame_length_flag : 1,
            channel_config : 4,
            frequency_index : 4,
            object_type : 5;
        };
        struct {
            unsigned char h0, h1;
        };
#elif (__BYTE_ORDER == __BIG_ENDIAN)
        struct {
            unsigned int
            object_type : 5,
            frequency_index : 4,
            channel_config : 4,
            frame_length_flag : 1,
            dependson_corecoder : 1,
            extension_flag : 1;
        };
        struct {
            unsigned char h1, h0;
        };
#endif
    };
};

static const unsigned int frequency_table[16] = {
    [0] = 96000,
    [1] = 88200,
    [2] = 64000,
    [3] = 48000,
    [4] = 44100,
    [5] = 32000,
    [6] = 24000,
    [7] = 22050,
    [8] = 16000,
    [9] = 12000,
    [10] = 11025,
    [11] = 8000,
    [12] = 7350,
    [13] = 0,
    [14] = 0,
    [15] = 0, /* explicit specified ? */
};

int audio_specific_config_parse(const unsigned char *buffer,
                                int *frequency, int *channel){
    const unsigned char *p = buffer;
    struct audio_specific_config_s config;
    if (!p || !(p + 1))
        return -1;

    config.h0 = *(p + 1);
    config.h1 = *(p + 0);

    *frequency = frequency_table[config.frequency_index];
    *channel = config.channel_config;
 
    return 0;
}

@interface RTMPPlayer ()<RTMPClientDelegate>{
    VideoView* _videoView;
}

@property (nonatomic,strong) RTMPClient* client;
@property (nonatomic,strong) AudioBufferPlayer* audioBufferPlayer;

@property (nonatomic,copy) NSString* url;
@property (nonatomic,strong) VideoDecoder* videoDecoder;
@property (nonatomic,strong) AACDecoder* audioDecoder;

@property (nonatomic,assign) BOOL running;
@property (nonatomic,strong) PacketQueue* videoQueue;
@property (nonatomic,strong) PacketQueue* audioQueue;

@property (nonatomic,strong) NSMutableArray<AVFrame*>* pcmFrames;

@property (nonatomic,strong) dispatch_group_t playerGroup;

@property (nonatomic,assign) int64_t audioTimestamp;

@property (nonatomic,assign) uint32_t maxCacheFrameCount;

@property (nonatomic,assign) BOOL audioPlayerStarted;
@end

@implementation RTMPPlayer

- (id)initWithURL:(NSString*)url{
    if (self = [super init]){
        _url = url;
        _volume = 1.0;
        //cache buffer duration, 24 * 1024 / 44100 = 0.55 seconds
        _maxCacheFrameCount = 24;
    }
    
    return self;
}

- (void)pushFrame:(AVFrame*)frame{
    @synchronized (_pcmFrames){
        if (_audioPlayerStarted){
            [_pcmFrames addObject:frame];
            
            //drop frame if reach max
            if (_pcmFrames.count > _maxCacheFrameCount){
                [_pcmFrames removeObjectAtIndex:0];
            }
        }
    }
}

- (AVFrame*)popFrame{
    AVFrame* frame = nil;
    @synchronized (_pcmFrames){
//      NSLog(@"left frame = %ld",_pcmFrames.count);
        if (_pcmFrames.count){
            frame = _pcmFrames.firstObject;
            [_pcmFrames removeObjectAtIndex:0];
        }
    }
    
    return frame;
}

- (void)dealloc{

}

#pragma mark Play

- (void)play{
    if (_running)
        return;
    
    _client = [[RTMPClient alloc] initWithURL:_url];
    _client.delegate = self;
    __weak typeof(self) weakSelf = self;
    _client.infoReceiveBlock = ^(PILI_RTMPPacket *packet) {
        //ignore the info packet
        PILI_RTMPPacket_Free(packet);
        free(packet);
    };
    
    _client.audioReceiveBlock = ^(PILI_RTMPPacket *packet) {
        [weakSelf.audioQueue pushPacket:[[AVPacket alloc] initWithRTMPPacket:packet]];
    };
    
    _client.videoReceiveBlock = ^(PILI_RTMPPacket *packet) {
        [weakSelf.videoQueue pushPacket:[[AVPacket alloc] initWithRTMPPacket:packet]];
    };
    
    _running = YES;
    _audioPlayerStarted = NO;
    
    _pcmFrames = [NSMutableArray arrayWithCapacity:64];
    _videoQueue = [PacketQueue new];
    _audioQueue = [PacketQueue new];
    
    _playerGroup = dispatch_group_create();
    
    [self startAudioThread];
    [self startVideoThread];
    
    [_client start];
}

- (void)stop{
    if (!_running)
        return;
    
    _running = NO;
    dispatch_group_wait(_playerGroup, DISPATCH_TIME_FOREVER);
    
    if (_client){
        __weak typeof(self) weakSelf = self;
        [_client stop:^{
            [weakSelf clean];
        }];
    }
}

- (void)clean{
    _client = nil;
    _playerGroup = nil;
    _audioQueue = nil;
    _videoQueue = nil;
    _audioDecoder = nil;
    _pcmFrames = nil;
    
    if (_audioBufferPlayer){
        [_audioBufferPlayer stop];
        _audioBufferPlayer = nil;
    }
}

- (void)setVolume:(CGFloat)volume{
    _volume = volume;
    if (_audioBufferPlayer){
        _audioBufferPlayer.gain = volume;
    }
}

#pragma mark Video & Audio Thread
- (void)startVideoThread{
    dispatch_group_async(_playerGroup,dispatch_get_global_queue(0, 0), ^{
        uint32_t timestamp = 0;
        int32_t decodeInterval = 0;
        int32_t duration = 0;

        AVPacket* packet = nil;
        
        while (_running) {
            if (packet == nil){
                packet = [_videoQueue popPacket];
            }
            
            if (packet == nil)
                continue;
            
            //AVC sequence header
            unsigned char* p = (unsigned char*)packet.rtmpPacket->m_body;
            if (*p == 0x17 && *(p+1) == 0x00){
                [self processVideoPacket:packet];
                packet = nil;
                continue;
            }
            
            if (timestamp != 0){
                duration = (int32_t)(packet.rtmpPacket->m_nTimeStamp - timestamp) - decodeInterval;
            }
            
            timestamp = packet.rtmpPacket->m_nTimeStamp;
            
            int64_t delta = (int64_t)timestamp - _audioTimestamp;
            if (delta < 50) {
//                NSLog(@"A-V = %lld",delta);
                NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                
                NSLog(@"video = %u",timestamp);
                [self processVideoPacket:packet];
                packet = nil;
                decodeInterval = 1000.0 * ([NSDate timeIntervalSinceReferenceDate] - now);
                
                //play video faster
                if (delta < -50){
                    continue;
                }
                
                if (duration > 0){
                    duration = MIN(duration, 50);
                    usleep(duration*1000);
                }
            }else{
                usleep(5*1000);
            }
        }
        
        NSLog(@"video thread exit");
    });
}

- (void)startAudioThread{
    dispatch_group_async(_playerGroup,dispatch_get_global_queue(0, 0), ^{
        while (_running) {
            AVPacket* packet = [_audioQueue popPacket];
            if (packet){
                [self processAudioPacket:packet];
            }
        }
        
        NSLog(@"audio thread exit");
    });
}

- (void)processAudioPacket:(AVPacket*)avpacket{
    //audio specific config
    PILI_RTMPPacket* packet = [avpacket rtmpPacket];
    if (packet->m_nBodySize == 4){
        int samplerate;
        int channel;
        audio_specific_config_parse((unsigned char*)packet->m_body +2,&samplerate,&channel);
        
        if (_audioDecoder == nil){
            _audioDecoder = [[AACDecoder alloc] initAACDecoderWithSampleRate:samplerate channels:channel];
        }
        
        if (_audioBufferPlayer == nil){
            _audioBufferPlayer = [[AudioBufferPlayer alloc] initWithSampleRate:samplerate channels:channel bitsPerChannel:16 packetsPerBuffer:1024];

            __weak typeof(self) weakSelf = self;
            _audioBufferPlayer.block = ^(AudioQueueBufferRef buffer, AudioStreamBasicDescription audioFormat) {
                weakSelf.audioPlayerStarted = YES;
                AVFrame* frame = [weakSelf popFrame];
                if (frame){
                    weakSelf.audioTimestamp = frame.timestamp;
                    memcpy(buffer->mAudioData, frame.data.bytes, frame.data.length);
                }else{
                    memset(buffer->mAudioData,0,buffer->mAudioDataBytesCapacity);
                    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
                }
            };

            _audioBufferPlayer.gain = _volume;
            [_audioBufferPlayer start];
        }
    }else{
        NSData* data = [_audioDecoder decodeWithAACBuf:packet->m_body+2 aacLen:packet->m_nBodySize-2];
        
        if (data){
            AVFrame* frame = [AVFrame new];
            frame.data = data;
            frame.timestamp = packet->m_nTimeStamp;
            [self pushFrame:frame];
        }
    }
}

- (void)processVideoPacket:(AVPacket*)avpacket{
    PILI_RTMPPacket* packet = [avpacket rtmpPacket];
    unsigned char* p = (unsigned char*)packet->m_body;
    //AVC Sequence header
    if (*p == 0x17 && *(p+1) == 0x00){
        if (_videoDecoder == nil){
            _videoDecoder = [VideoDecoder new];
            
            __weak typeof(self) weakSelf = self;
            _videoDecoder.newFrameAvailableBlock = ^(CVPixelBufferRef pixelBuffer) {
                [weakSelf display:pixelBuffer];
            };
        }
        
        long sps_size = p[11] << 8 | p[12];
        NSData* sps = [NSData dataWithBytes:p+13 length:sps_size];
        
        p = p + 13 + sps_size;
        long pps_size = p[1] << 8 | p[2];
        NSData* pps = [NSData dataWithBytes:p+3 length:pps_size];
        
        [_videoDecoder setupWithSPS:sps pps:pps];
    }
    //AVC nalu
    else{
        //skip 5 bytes
        [_videoDecoder decodeFrame:p+5 bufferLen:packet->m_nBodySize-5];
    }
}

#pragma mark View
- (void)display:(CVPixelBufferRef)pixelBuffer{
    if (_videoView){
        [_videoView displayPixelBuffer:pixelBuffer];
    }
}

- (UIView*)videoView{
    if (_videoView == nil){
        _videoView = [[VideoView alloc] init];
    }
    
    return _videoView;
}

#pragma mark Client Delegate
//Error code, see librtmp error.h
- (void)clientStateChanged:(RTMPClientState)state error:(int)code{
    if (state == RTMPClientStart){
        [_delegate playerStateChanged:RTMPPlayerStart error:code];
    }else if (state == RTMPClientStop){
        [_delegate playerStateChanged:RTMPPlayerStop error:code];
    }else if (state == RTMPClientError){
        [_delegate playerStateChanged:RTMPPlayerFail error:code];
    }else{
        //TODO: more state
    }
}

@end
