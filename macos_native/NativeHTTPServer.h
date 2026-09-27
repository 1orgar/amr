//
//  NativeHTTPServer.h
//  AppleMusicRemote
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NativeHTTPServer : NSObject

@property (nonatomic, assign, readonly) NSInteger port;
@property (nonatomic, copy, readonly) NSString *webRoot;
@property (nonatomic, assign, readonly) BOOL isRunning;

+ (instancetype)sharedServer;

- (BOOL)startWithPort:(NSInteger)port webRoot:(NSString *)webRoot;
- (void)stop;
- (NSArray<NSString *> *)getLANIPAddresses;
- (NSString *)getPrimaryURL;

@end

NS_ASSUME_NONNULL_END
