//
//  CloudService.h
//  AppleMusicRemote
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CloudService : NSObject

+ (instancetype)sharedService;

- (void)getExploreFeedWithCountry:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion;
- (void)searchWithQuery:(NSString *)query country:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion;
- (void)getAlbumDetails:(NSString *)albumId country:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion;
- (NSArray<NSDictionary *> *)getCuratedStationsWithCountry:(NSString *)country;

@end

NS_ASSUME_NONNULL_END
