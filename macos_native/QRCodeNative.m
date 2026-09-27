//
//  QRCodeNative.m
//  AppleMusicRemote
//

#import "QRCodeNative.h"
#import <CoreImage/CoreImage.h>

@implementation QRCodeNative

+ (NSImage *)generateQRImageForString:(NSString *)string size:(CGFloat)size {
    if (!string || string.length == 0) return nil;
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    
    CIImage *ciImage = filter.outputImage;
    if (!ciImage) return nil;
    
    CGSize extent = ciImage.extent.size;
    if (extent.width <= 0 || extent.height <= 0) return nil;
    
    CGFloat scale = size / extent.width;
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    CIImage *transformedImage = [ciImage imageByApplyingTransform:transform];
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:transformedImage fromRect:transformedImage.extent];
    if (!cgImage) return nil;
    
    NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(size, size)];
    CGImageRelease(cgImage);
    return image;
}

+ (NSString *)generateSVGForString:(NSString *)string {
    if (!string || string.length == 0) return @"";
    
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    
    CIImage *ciImage = filter.outputImage;
    if (!ciImage) return @"";
    
    CGRect rect = ciImage.extent;
    int width = (int)rect.size.width;
    int height = (int)rect.size.height;
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:rect];
    if (!cgImage) return @"";
    
    CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
    const UInt8 *pixels = CFDataGetBytePtr(pixelData);
    size_t bytesPerRow = CGImageGetBytesPerRow(cgImage);
    size_t bytesPerPixel = CGImageGetBitsPerPixel(cgImage) / 8;
    
    NSMutableString *rects = [NSMutableString string];
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            const UInt8 *pixel = pixels + (y * bytesPerRow) + (x * bytesPerPixel);
            UInt8 lum = pixel[0]; // Black pixel in CIQRCodeGenerator is 0
            if (lum < 128) {
                [rects appendFormat:@"<rect x=\"%d\" y=\"%d\" width=\"1\" height=\"1\" fill=\"#000\"/>", x, y];
            }
        }
    }
    
    CFRelease(pixelData);
    CGImageRelease(cgImage);
    
    return [NSString stringWithFormat:@"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %d %d\" shape-rendering=\"crispEdges\"><rect width=\"100%%\" height=\"100%%\" fill=\"#fff\"/>%@</svg>", width, height, rects];
}

@end
