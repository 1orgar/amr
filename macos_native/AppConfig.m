//
//  AppConfig.m
//  AppleMusicRemote
//

#import "AppConfig.h"

static NSString *const kConfigFileName = @".apple_music_remote_config.json";

@implementation AppConfig

+ (instancetype)sharedConfig {
    static AppConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AppConfig alloc] init];
        [instance load];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _port = 8080;
        _country = @"ru";
        _musickitDeveloperToken = @"";
    }
    return self;
}

- (NSString *)configFilePath {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:kConfigFileName];
}

- (void)load {
    NSString *path = [self configFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)json;
        if (dict[@"port"]) {
            self.port = [dict[@"port"] integerValue];
        }
        if (dict[@"country"] && [dict[@"country"] isKindOfClass:[NSString class]]) {
            self.country = dict[@"country"];
        }
        if (dict[@"musickit_developer_token"] && [dict[@"musickit_developer_token"] isKindOfClass:[NSString class]]) {
            self.musickitDeveloperToken = dict[@"musickit_developer_token"];
        }
    }
}

- (BOOL)saveWithDictionary:(NSDictionary *)dict {
    if (dict[@"port"]) {
        NSInteger p = [dict[@"port"] integerValue];
        if (p > 0 && p < 65536) {
            self.port = p;
        }
    }
    if (dict[@"country"] && [dict[@"country"] isKindOfClass:[NSString class]]) {
        self.country = [dict[@"country"] lowercaseString];
    }
    if (dict[@"musickit_developer_token"] && [dict[@"musickit_developer_token"] isKindOfClass:[NSString class]]) {
        self.musickitDeveloperToken = dict[@"musickit_developer_token"];
    }
    
    NSDictionary *outDict = [self dictionaryRepresentation];
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:outDict options:NSJSONWritingPrettyPrinted error:&err];
    if (!data) return NO;
    
    return [data writeToFile:[self configFilePath] atomically:YES];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"port": @(self.port),
        @"country": self.country ?: @"ru",
        @"musickit_developer_token": self.musickitDeveloperToken ?: @""
    };
}

@end
