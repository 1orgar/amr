//
//  AppConfig.h
//  AppleMusicRemote
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppConfig : NSObject

@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *country;
@property (nonatomic, copy) NSString *musickitDeveloperToken;

+ (instancetype)sharedConfig;
- (void)load;
- (BOOL)saveWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
