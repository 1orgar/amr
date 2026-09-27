//
//  AppDelegate.h
//  AppleMusicRemote
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSWindowController *qrWindowController;
@property (nonatomic, strong) NSTimer *menuUpdateTimer;

@end

NS_ASSUME_NONNULL_END
