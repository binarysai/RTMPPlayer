//
//  VideoDecoder.m
//  PlayTest
//
//  Created by hc on 2018/1/11.
//  Copyright © 2018年 hc. All rights reserved.
//

#import "VideoDecoder.h"
#include <VideoToolbox/VideoToolbox.h>
#import <CoreImage/CoreImage.h>

static void outputCallback(void * decompressionOutputRefCon, void * sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration)
{
    
    VideoDecoder* decoder = (__bridge  VideoDecoder*)decompressionOutputRefCon;
    decoder.newFrameAvailableBlock(imageBuffer);
}

@interface VideoDecoder (){
    VTDecompressionSessionRef _vt_session;
    CMFormatDescriptionRef _formatDescription;
}

@end

@implementation VideoDecoder
- (void)setupWithSPS:(NSData*)sps pps:(NSData*)pps{
    
    CMFormatDescriptionRef formatDescription;
    const uint8_t* const parameterSetPointers[2] = { (const uint8_t*)[sps bytes], (const uint8_t*)[pps bytes] };
    const size_t parameterSetSizes[2] = { [sps length], [pps length] };
    CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL,2,parameterSetPointers,                                                             parameterSetSizes,4,&formatDescription);
    
    if (_formatDescription && CMFormatDescriptionEqual(formatDescription, _formatDescription))
        return;
    
    [self clean];
    
    _formatDescription = formatDescription;
    
    VTDecompressionOutputCallbackRecord outputCallbackRecord;
    outputCallbackRecord.decompressionOutputCallback = outputCallback;
    outputCallbackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
//    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(_formatDescription);
    
    NSDictionary* destinationPixelBufferAttributes = @{
                    (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                    (__bridge NSString*)kCVPixelBufferOpenGLCompatibilityKey : @(YES),
                    
                    (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : [NSDictionary dictionary],
                    };
    
    OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDescription, NULL, (__bridge CFDictionaryRef)destinationPixelBufferAttributes, &outputCallbackRecord, &_vt_session);
    
    if (status != noErr) {

    }
}

- (void)clean{
    if (_vt_session) {
        VTDecompressionSessionWaitForAsynchronousFrames(_vt_session);
        VTDecompressionSessionInvalidate(_vt_session);
        CFRelease(_vt_session);
        _vt_session = NULL;
    }
    
    if (_formatDescription){
        CFRelease(_formatDescription);
        _formatDescription = nil;
    }
}

- (void)decodeFrame:(unsigned char*)buffer bufferLen:(long)len{
    CMBlockBufferRef blockBuffer = NULL;
    CMBlockBufferCreateWithMemoryBlock(NULL, buffer, len, kCFAllocatorNull, NULL, 0, len, FALSE, &blockBuffer);
    
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreate( NULL, blockBuffer, TRUE, 0, 0, _formatDescription, 1, 0, NULL, 0, NULL, &sampleBuffer);
    
    OSStatus status = VTDecompressionSessionDecodeFrame(_vt_session, sampleBuffer,  kVTDecodeFrame_EnableAsynchronousDecompression | kVTDecodeFrame_EnableTemporalProcessing, NULL, 0);
    if (status != noErr) {
        NSLog(@"status = %d",status);
    }
    
    CFRelease(blockBuffer);
    CFRelease(sampleBuffer);
}
@end
