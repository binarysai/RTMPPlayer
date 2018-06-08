//
//  RTMPClient.m
//  RTMPPlayerDemo
//
//  Created by hc on 2018/5/30.
//  Copyright © 2018年 hc. All rights reserved.
//

#import "RTMPClient.h"
#import "rtmp.h"


@interface RTMPClient (){
    PILI_RTMP *_rtmp;
}

@property (nonatomic, assign) NSInteger retryCount;

@property (nonatomic, strong) dispatch_queue_t rtmpReceiveQueue;
@property (nonatomic, assign) RTMPError error;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, copy) NSString* url;
@property (nonatomic, assign) RTMPClientState state;
@property (nonatomic,copy) void (^handler)(void);

- (void)setCallbackError:(RTMPError*)error;

@end

void RTMPErrorCallback(RTMPError *error, void *userData) {
    RTMPClient *client = (__bridge RTMPClient *)userData;
    [client setCallbackError:error];    
}


@implementation RTMPClient
- (id)initWithURL:(NSString*)url{
    if (self = [super init]){
        _url = url;
        _reconnectCount = 3;
        _reconnectInterval = 3;
    }

    return self;
}

- (void)dealloc{
    RTMPError_Free(&_error);
}

- (void)setCallbackError:(RTMPError*)error{
    RTMPError_Free(&_error);
    
    if (error->message){
        RTMPError_Alloc(&_error, strlen(error->message) + 1);
        strcpy(_error.message, error->message);
    }
    
    _error.code = error->code;
}

- (BOOL)isRunning{
    return _running;
}

- (void)start{
    dispatch_async(self.rtmpReceiveQueue, ^{
        if (_running) return;
        
        _running = YES;        
        _state = RTMPClientPrepare;
        _retryCount = 0;
        [self RTMP264_Connect:(char*)[_url UTF8String]];
    });
}

- (void)stop:(void (^)(void))handler{
    dispatch_async(self.rtmpReceiveQueue, ^{
        if (!_running) {
            if (handler){
                handler();
            }
            
            return;
        }
        
        _handler = handler;
        _state = RTMPClientStop;
        _running = NO;
        
        if (_rtmp != NULL) {
            PILI_RTMP_Close(_rtmp, &_error);
            PILI_RTMP_Free(_rtmp);
            _rtmp = NULL;
        }
    });
}

- (NSInteger)RTMP264_Connect:(char *)push_url {
    if (_state == RTMPClientStop){
        if (_handler){
            _handler();
        }
        
        [_delegate clientStateChanged:RTMPClientStop error:_error.code];
        return -1;
    }
    
    _rtmp = PILI_RTMP_Alloc();
    PILI_RTMP_Init(_rtmp);
    
    if (PILI_RTMP_SetupURL(_rtmp, push_url, &_error) == FALSE) {
        //log(LOG_ERR, "RTMP_SetupURL() failed!");
        goto Failed;
    }
    
    _rtmp->m_errorCallback = RTMPErrorCallback;
    _rtmp->m_connCallback = NULL;
    _rtmp->m_userData = (__bridge void *)self;
    _rtmp->m_msgCounter = 1;
    
    if (PILI_RTMP_Connect(_rtmp, NULL, &_error) == FALSE) {
        goto Failed;
    }
    
    if (PILI_RTMP_ConnectStream(_rtmp, 0, &_error) == FALSE) {
        goto Failed;
    }
    
    [self rtmpReceive];
    
    return 0;
    
Failed:
    PILI_RTMP_Close(_rtmp, &_error);
    PILI_RTMP_Free(_rtmp);
    _rtmp = NULL;
    _state = RTMPClientError;
    
    if (_retryCount < _reconnectCount){
        NSLog(@"connect error,reconnect");
        _retryCount++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_reconnectInterval * NSEC_PER_SEC)), self.rtmpReceiveQueue, ^{
            [self RTMP264_Connect:(char*)[_url UTF8String]];
        });
    }else{
        [_delegate clientStateChanged:RTMPClientError error:_error.code];
        _running = NO;
    }
    
    return -1;
}

- (void)rtmpReceive{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (_running) {
            PILI_RTMPPacket* packet = malloc(sizeof(PILI_RTMPPacket));
            memset(packet, 0, sizeof(PILI_RTMPPacket));
            
            dispatch_sync(self.rtmpReceiveQueue, ^{
                if (_rtmp != NULL){
                    if (PILI_RTMP_ReadPacket(_rtmp, packet)){
                        if (RTMPPacket_IsReady(packet)){
                            PILI_RTMP_ClientPacket(_rtmp,packet);
                        }
                    }else{
                        _state = RTMPClientError;
                    }
                }
            });
            
            if (_state == RTMPClientStop || _state == RTMPClientError){
                PILI_RTMPPacket_Free(packet);
                free(packet);
                break;
            }
            
            if (!RTMPPacket_IsReady(packet)){
                PILI_RTMPPacket_Free(packet);
                free(packet);
                continue;
            }
            
            if (_state != RTMPClientStart){
                _state = RTMPClientStart;
                [_delegate clientStateChanged:RTMPClientStart error:0];
            }
            
            if (packet->m_packetType == RTMP_PACKET_TYPE_INFO){
                _infoReceiveBlock(packet);
            }else if (packet->m_packetType == RTMP_PACKET_TYPE_AUDIO){
                _audioReceiveBlock(packet);
            }else if (packet->m_packetType == RTMP_PACKET_TYPE_VIDEO){
                _videoReceiveBlock(packet);
            }
        }
        
        dispatch_sync(self.rtmpReceiveQueue, ^{
            if (_rtmp){
                PILI_RTMP_Close(_rtmp, &_error);
                PILI_RTMP_Free(_rtmp);
                _rtmp = NULL;
            }
        });
        
        if (_state == RTMPClientError){
            if (_retryCount < _reconnectCount){
                _retryCount++;
                NSLog(@"receive error,reconnect");
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_reconnectInterval * NSEC_PER_SEC)), self.rtmpReceiveQueue, ^{
                        [self RTMP264_Connect:(char*)[_url UTF8String]];
                });
                
                return;
            }else{
                [_delegate clientStateChanged:RTMPClientError error:_error.code];
            }
        }
        
        _running = NO;
        
        if (_state == RTMPClientStop){
            if (_handler){
                _handler();
            }
            
            [_delegate clientStateChanged:RTMPClientStop error:0];
        }
    });
}



- (dispatch_queue_t)rtmpReceiveQueue{
    if(!_rtmpReceiveQueue){
        _rtmpReceiveQueue = dispatch_queue_create("RtmpReceiveQueue", NULL);
    }
    
    return _rtmpReceiveQueue;
}

@end
