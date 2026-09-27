//
//  AppDelegate.m
//  AppleMusicRemote
//

#import "AppDelegate.h"
#import "NativeHTTPServer.h"
#import "AppleMusicBridge.h"
#import "AppConfig.h"
#import "QRCodeNative.h"
#import "MusicKitBridge-Swift.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 1. Load config
    [[AppConfig sharedConfig] load];
    NSInteger port = [AppConfig sharedConfig].port;
    
    // Request MusicKit authorization
    [[MusicKitBridge shared] requestAuthorizationWithCompletion:^(BOOL authorized) {
        if (!authorized) {
            NSLog(@"[AppDelegate] MusicKit not authorized.");
        }
    }];
    
    // 2. Locate web directory
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *webRoot = [bundlePath stringByAppendingPathComponent:@"Contents/Resources/web"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:webRoot]) {
        NSString *currentDirPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"web"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:currentDirPath]) {
            webRoot = currentDirPath;
        } else {
            webRoot = @"/Users/kirill/Documents/projects/amr/web";
        }
    }
    
    // 3. Start embedded HTTP server (No Python!)
    BOOL serverOk = [[NativeHTTPServer sharedServer] startWithPort:port webRoot:webRoot];
    if (!serverOk) {
        NSLog(@"[AppDelegate] Failed to start native HTTP server on port %ld", (long)port);
    }
    
    // 4. Create Status Item in Menu Bar
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *menuIcon = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:@"Apple Music Remote"];
    if (!menuIcon) {
        menuIcon = [NSImage imageNamed:NSImageNameTouchBarAudioOutputVolumeHighTemplate];
    }
    [menuIcon setTemplate:YES]; // Ensure it tints correctly for dark/light mode
    self.statusItem.button.image = menuIcon;
    
    // 5. Build Menu
    [self rebuildMenu];
    
    // 6. Start Menu Poller Timer
    self.menuUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                            target:self
                                                          selector:@selector(updateMenuState)
                                                          userInfo:nil
                                                           repeats:YES];
    [self updateMenuState];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[NativeHTTPServer sharedServer] stop];
}

#pragma mark - Menu Management

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    // Header
    NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:@"Apple Music Remote (Native)" action:nil keyEquivalent:@""];
    [headerItem setEnabled:NO];
    [menu addItem:headerItem];
    
    // Status text item
    NSMenuItem *statusItem = [[NSMenuItem alloc] initWithTitle:@"Загрузка статуса..." action:nil keyEquivalent:@""];
    [statusItem setTag:100];
    [statusItem setEnabled:NO];
    [menu addItem:statusItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Settings
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Настройки HTTP порта..." action:@selector(onSettingsClicked:) keyEquivalent:@""];
    [settingsItem setTarget:self];
    [menu addItem:settingsItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Web Remote Link
    NSString *primaryUrl = [[NativeHTTPServer sharedServer] getPrimaryURL];
    NSMenuItem *urlItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Веб-пульт: %@", primaryUrl] action:@selector(onOpenWebClicked:) keyEquivalent:@""];
    [urlItem setTarget:self];
    [urlItem setTag:102];
    [menu addItem:urlItem];
    
    // QR Code Window
    NSMenuItem *qrItem = [[NSMenuItem alloc] initWithTitle:@"Показать QR-код для телефона..." action:@selector(onShowQRClicked:) keyEquivalent:@""];
    [qrItem setTarget:self];
    [menu addItem:qrItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Restart Server
    NSMenuItem *restartItem = [[NSMenuItem alloc] initWithTitle:@"Перезапустить сервер" action:@selector(onRestartServerClicked:) keyEquivalent:@""];
    [restartItem setTarget:self];
    [menu addItem:restartItem];
    
    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Завершить" action:@selector(onQuitClicked:) keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [menu addItem:quitItem];
    
    self.statusMenu = menu;
    self.statusItem.menu = menu;
}

- (void)updateMenuState {
    NSDictionary *status = [[AppleMusicBridge sharedBridge] getPlayerStatus];
    NSString *pState = status[@"player_state"] ?: @"stopped";
    id trackObj = status[@"track"];
    
    NSMenuItem *statusMenuItem = [self.statusMenu itemWithTag:100];
    
    if ([trackObj isKindOfClass:[NSDictionary class]] && trackObj[@"name"]) {
        NSString *name = trackObj[@"name"];
        NSString *artist = trackObj[@"artist"];
        NSString *title = [NSString stringWithFormat:@"%@ — %@", name, artist];
        if (title.length > 35) {
            title = [[title substringToIndex:32] stringByAppendingString:@"..."];
        }
        [statusMenuItem setTitle:title];
    } else {
        [statusMenuItem setTitle:@"Музыка не воспроизводится"];
    }
}


#pragma mark - Actions

- (void)onSettingsClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Настройки Apple Music Remote"];
    [alert setInformativeText:@"Введите HTTP порт для веб-сервера и регион (например: ru, us):"];
    [alert addButtonWithTitle:@"Сохранить"];
    [alert addButtonWithTitle:@"Отмена"];
    
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 8;
    
    NSTextField *inputPort = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [inputPort setStringValue:[NSString stringWithFormat:@"%ld", (long)[AppConfig sharedConfig].port]];
    [inputPort setPlaceholderString:@"Порт (8080)"];
    
    NSPopUpButton *regionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    NSArray *regions = @[@"ru", @"us", @"gb", @"de", @"fr", @"jp", @"au", @"ca"];
    [regionPopup addItemsWithTitles:@[@"Россия (RU)", @"США (US)", @"Великобритания (GB)", @"Германия (DE)", @"Франция (FR)", @"Япония (JP)", @"Австралия (AU)", @"Канада (CA)"]];
    
    NSString *currentRegion = [AppConfig sharedConfig].country ?: @"ru";
    NSInteger idx = [regions indexOfObject:currentRegion];
    if (idx != NSNotFound) {
        [regionPopup selectItemAtIndex:idx];
    } else {
        [regionPopup selectItemAtIndex:0];
    }
    
    [stack addView:inputPort inGravity:NSStackViewGravityTop];
    [stack addView:regionPopup inGravity:NSStackViewGravityTop];
    
    [alert setAccessoryView:stack];
    
    [alert.window setLevel:NSFloatingWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
    
    NSInteger response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSInteger newPort = [inputPort.stringValue integerValue];
        NSInteger selectedIdx = [regionPopup indexOfSelectedItem];
        NSString *newRegion = selectedIdx >= 0 && selectedIdx < regions.count ? regions[selectedIdx] : @"ru";
        
        if (newPort > 0 && newPort <= 65535) {
            [AppConfig sharedConfig].port = newPort;
            [AppConfig sharedConfig].country = newRegion;
            [[AppConfig sharedConfig] saveWithDictionary:@{@"port": @(newPort), @"country": newRegion}];
            [self onRestartServerClicked:nil];
        }
    }
}

- (void)onOpenWebClicked:(id)sender {
    NSString *primaryUrl = [[NativeHTTPServer sharedServer] getPrimaryURL];
    NSURL *url = [NSURL URLWithString:primaryUrl];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)onShowQRClicked:(id)sender {
    NSString *primaryUrl = [[NativeHTTPServer sharedServer] getPrimaryURL];
    NSImage *qrImage = [QRCodeNative generateQRImageForString:primaryUrl size:220.0];
    
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 280, 360)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Apple Music Remote"];
    [window center];
    [window setLevel:NSFloatingWindowLevel];
    
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:window.contentView.bounds];
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effectView.material = NSVisualEffectMaterialHUDWindow;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(30, 95, 220, 220)];
    imageView.image = qrImage;
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 240, 40)];
    label.stringValue = [NSString stringWithFormat:@"Отсканируйте камерой телефона:\n%@", primaryUrl];
    label.alignment = NSTextAlignmentCenter;
    label.editable = NO;
    label.bordered = NO;
    label.backgroundColor = [NSColor clearColor];
    label.textColor = [NSColor whiteColor];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    
    NSButton *openBtn = [NSButton buttonWithTitle:@"Открыть в браузере" target:self action:@selector(onOpenWebClicked:)];
    openBtn.frame = NSMakeRect(50, 15, 180, 28);
    openBtn.bezelStyle = NSBezelStyleRounded;
    
    [effectView addSubview:imageView];
    [effectView addSubview:label];
    [effectView addSubview:openBtn];
    
    [window setContentView:effectView];
    
    self.qrWindowController = [[NSWindowController alloc] initWithWindow:window];
    [self.qrWindowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)onRestartServerClicked:(id)sender {
    NSInteger port = [AppConfig sharedConfig].port;
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *webRoot = [bundlePath stringByAppendingPathComponent:@"Contents/Resources/web"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:webRoot]) {
        webRoot = @"/Users/1orgar/Desktop/amr/web";
    }
    [[NativeHTTPServer sharedServer] startWithPort:port webRoot:webRoot];
    [self rebuildMenu];
    [self updateMenuState];
}

- (void)onQuitClicked:(id)sender {
    [[NSApplication sharedApplication] terminate:nil];
}

@end
