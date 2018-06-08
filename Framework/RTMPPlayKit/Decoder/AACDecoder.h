
#import <Foundation/Foundation.h>

@interface AACDecoder : NSObject


- (instancetype)initAACDecoderWithSampleRate:(int)sample_rate channels:(int)channel;

- (NSData *)decodeWithAACBuf:(void *)srcdata aacLen:(int)srclen;


@end
