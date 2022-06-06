//
//  JBAudioEncoder.m
//  JBMacAVDemo
//
//  Created by 任金波 on 2022/3/21.
//

#import "JBAudioEncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


typedef struct JBConverterInfo {
    UInt32 channelsCount;
    UInt32 dataSize;
    void *buffer;
}JBConverterInfo;

@interface JBAudioEncoder() {
    AudioChannelLayout m_ChannelLayout;
    AudioConverterRef m_audioConverter;
    uint8_t* m_pOutputBuffer;
}

@property(nonatomic, strong) dispatch_queue_t callbackQueue;
@property(nonatomic, strong) dispatch_queue_t encoderQueue;

@property(nonatomic) AudioStreamBasicDescription inputformat;
@property(nonatomic)  AudioStreamBasicDescription outputFormat;


@property(nonatomic, assign)  UInt32 outputBufferSize;
@property (nonatomic, strong) JBConfigData *configData;

@property (nonatomic, assign) uint8_t *pcmBuffer;
@property (nonatomic, assign) size_t pcmBufferSize;

@end
 
@implementation JBAudioEncoder

- (instancetype)initWithData:(JBConfigData *)data {
    self = [super init];
    if (self) {
        self.configData = data;
        NSLog(@"JBAudioEncoder initWithData");
        self.encoderQueue = dispatch_queue_create("encode audio queue jimbo", DISPATCH_QUEUE_SERIAL);
        self.callbackQueue = dispatch_queue_create("encode audio callback queue jimbo", DISPATCH_QUEUE_SERIAL);
        m_audioConverter = NULL;
        self.pcmBufferSize = 0;
        self.pcmBuffer = NULL;
    }
    return self;
}

void checkError(OSStatus status, NSString *logStr) {
    if (status == noErr) {
        return;
    }
    NSString *s = [NSString stringWithCString:__FILE__ encoding:NSUTF8StringEncoding];
    NSString *file =  [[s componentsSeparatedByString:@"/"] lastObject];
    NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    NSLog(@"[%@] %@ : %i err:%@", file ,logStr, (int)status, error);
}

- (void)setupConverter {
    
//    AudioStreamBasicDescription inFormat = *CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer));
    AudioStreamBasicDescription inFormat = self.configData.mASBD;
    
    // 配置 输出 格式 ASBD
    AudioStreamBasicDescription destinationFormat;
    memset(&destinationFormat, 0, sizeof(AudioStreamBasicDescription));
    
    destinationFormat.mSampleRate = inFormat.mSampleRate;
    destinationFormat.mFormatID = kAudioFormatMPEG4AAC; //指定流中一般音频数据格式的标识符。请参阅音频数据格式标识符。此值必须为非零。 kAudioFormatLinearPCM
//    destinationFormat.mFormatFlags = kMPEG4Object_AAC_LC; //kAudioFormatFlagIsSignedInteger 或其他
//    destinationFormat.mBytesPerPacket = 6; //每个packet 的大小，单位是 byte
    destinationFormat.mFramesPerPacket = 1024; //AAC 1024
//    destinationFormat.mBytesPerFrame = 0; //音频缓冲区中从一帧开始到下一帧开始的字节数。将此字段设置0为压缩格式。t, n:channel coun  mBytesPerFrame = n * sizeof (AudioSampleType);
//    destinationFormat.mChannelsPerFrame = inFormat.mChannelsPerFrame;
//    destinationFormat.mBitsPerChannel = 24;
//    destinationFormat.mReserved = 0;
    destinationFormat.mChannelsPerFrame = inFormat.mChannelsPerFrame;

    
    self.outputFormat = destinationFormat;

    //输入格式，输出格式，一个AudioConverterRef指针。
    OSStatus status = AudioConverterNew(&inFormat, &destinationFormat, &m_audioConverter);
//    OSStatus status = AudioConverterNewSpecific(&inFormat, &destinationFormat, 1, audioClassDesc, &m_audioConverter);
    
    
    
//    //输入格式，输出格式，一个AudioConverterRef指针。
//    OSStatus status = AudioConverterNew(&inFormat, &destinationFormat, &m_audioConverter);
    checkError(status, @"AudioConverterNew");
    if (status != noErr) {
        return;
    }
    
    
//    //channel 配置 貌似可以不设置
    m_ChannelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    m_ChannelLayout.mNumberChannelDescriptions  = 0;
    status = AudioConverterSetProperty(m_audioConverter, kAudioConverterInputChannelLayout, sizeof(AudioChannelLayout), &m_ChannelLayout);
    checkError(status, @"KAudioConverterInputChannelLayout");
//
//    status = AudioConverterSetProperty(m_audioConverter, kAudioConverterOutputChannelLayout, sizeof(AudioChannelLayout), &m_ChannelLayout);
//    checkError(status, @"KAudioConverterOutputChannelLayout");
    
    
    //bitrate 配置
    if (destinationFormat.mFormatID == kAudioFormatMPEG4AAC) {
        UInt32 outputBitRate = 64000;
        if (destinationFormat.mSampleRate >= 44100) {
            outputBitRate = 192000;
        } else if (destinationFormat.mSampleRate < 22000) {
            outputBitRate = 32000;
        }
        status = AudioConverterSetProperty(m_audioConverter, kAudioConverterEncodeBitRate, sizeof(outputBitRate), &outputBitRate);
        checkError(status, @"KAudioconverterEncodeBitRate");
    }
//    UInt32 outputBitRate = 128000;
//    status = AudioConverterSetProperty(m_audioConverter, kAudioConverterEncodeBitRate, sizeof(outputBitRate), &outputBitRate);
//    checkError(status, @"KAudioconverterEncodeBitRate");
    
    //编码质量， 低 到 max
    UInt32 tmp = kAudioConverterQuality_High;
    status = AudioConverterSetProperty(m_audioConverter, kAudioConverterCodecQuality, sizeof(tmp), &tmp);
    checkError(status, @"kAudioConverterCodecQuality");
  
}

// bufferData 是malloc 出来的地址，必须进行free操作
- (void)startEncoder:(void *)bufferData buffersize:(UInt32)buffersize {
    if (!m_audioConverter) {
        [self setupConverter];
    }
    

    dispatch_async(self.encoderQueue, ^{
        //TODO:这种方法会在每次送入 buffer 的时候开辟空间。
        //项目中用的会在初始化的时候把空间 开辟好，把size 准备好
        
        
        self.pcmBuffer = bufferData;
        self.pcmBufferSize = buffersize;
        //数据转换
        AudioBufferList outBuffer = {0};
        outBuffer.mNumberBuffers = 1;
        outBuffer.mBuffers[0].mNumberChannels = self.outputFormat.mChannelsPerFrame;
        outBuffer.mBuffers[0].mDataByteSize = (uint32_t)self.pcmBufferSize;
        outBuffer.mBuffers[0].mData  = self.pcmBuffer;
        
        UInt32 ioOutSize = 1; //输出包大小为1
        AudioStreamPacketDescription outputPacketDescriptions;
       OSStatus  status =  AudioConverterFillComplexBuffer(self->m_audioConverter,
                                                           MyAudioConverterCallback,
                                                            (__bridge void *)self,
                                                           &ioOutSize,
                                                           &outBuffer,
                                                           &outputPacketDescriptions
                                                           );
        if (status != -1)
            checkError(status, @"AudioConverterFillComplexBuffer");
        
        if (status == noErr) {
            
//            NSLog(@"size: %u   size2:%i  pcmSize:%i", (unsigned int)outBuffer.mBuffers[0].mDataByteSize, outputPacketDescriptions.mDataByteSize , buffersize);
            
            if (outBuffer.mBuffers[0].mDataByteSize <= 0) {
                return;;
            }
            
            NSData *rawAAC = [NSData dataWithBytes:outBuffer.mBuffers->mData length:outBuffer.mBuffers[0].mDataByteSize];
            
            //现在是写入文件，所以需要 添加ADTS头
            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
            NSMutableData *fullData = [NSMutableData dataWithCapacity:adtsHeader.length + rawAAC.length];
            [fullData appendData:adtsHeader];
            [fullData appendData:rawAAC];
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(audioEncoderCallback:)]) {
                [self.delegate audioEncoderCallback:fullData];
            };
        }
        free(bufferData);
    });
}

//编码后的回调函数
OSStatus MyAudioConverterCallback(AudioConverterRef inAudioConverter,
                                  UInt32 *ioDataPacketCount,
                                  AudioBufferList *ioData,
                                  AudioStreamPacketDescription **outDataPacketDescription,
                                  void *inUserData)
{
    
    JBAudioEncoder *encoder = (__bridge  JBAudioEncoder *)inUserData;
    if (encoder.pcmBufferSize == 0) {
        *ioDataPacketCount = 0;
        return -1;
    }
    
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = encoder.pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (uint32_t)encoder.pcmBufferSize;
    ioData->mBuffers[0].mNumberChannels = (uint32_t)encoder.configData.mASBD.mChannelsPerFrame;
    
    //填完数据后，清空数据
    encoder.pcmBufferSize = 0;
     *ioDataPacketCount = 1;

    return noErr;
    
}


/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  AAC ADtS头
 *  Note the packetLen must count in the ADTS header itself.
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*)adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 3;  //3: 48000 Hz      4: 44100 Hz
    int chanCfg = 2;  //1->1channels   2->2channels
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF;    // 11111111      = syncword
    packet[1] = (char)0xF9;    // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

- (void)dealloc {
//    if (self.m_pOutputBuffer) {
//        free(self.m_pOutputBuffer);
//        self.m_pOutputBuffer = NULL;
//    }
    if (m_audioConverter) {
        AudioConverterDispose(m_audioConverter);
        m_audioConverter = NULL;
    }
}
@end
