#import "JBConfigData.h"
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>

NSString *const JBStopNotification = @"JBStopNotification";

@implementation JBConfigData

+ (instancetype)shareInstance {
    
    static JBConfigData *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[JBConfigData alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    captureASBD = {0};
    encodeASBD = {0};
    return self;
}

#pragma mark po或者打印时打出内部信息
- (NSString *)description
{
    NSMutableString* text = [NSMutableString stringWithFormat:@"<%@> \n", [self class]];
    NSArray* properties = [self filterPropertys];
    [properties enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* key = (NSString*)obj;
        id value = [self valueForKey:key];
        NSString* valueDescription = (value)?[value description]:@"(null)";
        
        if ( ![value respondsToSelector:@selector(count)] && [valueDescription length] > 60  ) {
            valueDescription = [NSString stringWithFormat:@"%@...", [valueDescription substringToIndex:59]];
        }
        valueDescription = [valueDescription stringByReplacingOccurrencesOfString:@"\n" withString:@"\n   "];
        [text appendFormat:@"   [%@]: %@\n", key, valueDescription];
    }];
    [text appendFormat:@"</%@>", [self class]];;
    return text;
}

#pragma mark 获取一个类的属性列表
- (NSArray *)filterPropertys
{
    NSMutableArray* props = [NSMutableArray array];
    unsigned int count;
    objc_property_t *properties = class_copyPropertyList([self class], &count);
    for(int i = 0; i < count; i++){
        objc_property_t property = properties[i];
        const char* char_f =property_getName(property);
        NSString *propertyName = [NSString stringWithUTF8String:char_f];
        [props addObject:propertyName];
    }
    free(properties);
    return props;
}

@end
