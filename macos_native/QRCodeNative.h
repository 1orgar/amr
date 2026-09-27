//
//  QRCodeNative.h
//  AppleMusicRemote
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QRCodeNative : NSObject

+ (nullable NSImage *)generateQRImageForString:(NSString *)string size:(CGFloat)size;
+ (nullable NSString *)generateSVGForString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
