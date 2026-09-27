#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSTask *serverTask;
@property (strong) NSWindow *qrWindow;
@property (strong) NSImageView *qrImageView;
@property (strong) NSTextField *qrUrlLabel;
@property (strong) NSTimer *pollTimer;

@property (copy) NSString *currentTrackTitle;
@property (copy) NSString *currentArtist;
@property (assign) BOOL isPlaying;
@property (assign) NSInteger serverPort;
@property (copy) NSString *primaryUrl;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.serverPort = 8080;
    self.primaryUrl = @"http://localhost:8080";
    self.currentTrackTitle = @"Apple Music Remote";
    self.currentArtist = @"";
    self.isPlaying = NO;

    // 1. Initialize Status Bar Item
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    if (self.statusItem.button) {
        if (@available(macOS 11.0, *)) {
            self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"music.note" accessibilityDescription:@"Apple Music Remote"];
        } else {
            self.statusItem.button.title = @"🎵";
        }
    }

    // 2. Start Server
    [self startServer];

    // 3. Build Menu
    [self rebuildMenu];

    // 4. Start Polling Timer
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(pollStatus)
                                                    userInfo:nil
                                                     repeats:YES];
    [self pollStatus];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self stopServer];
}

#pragma mark - Server Process Management

- (void)startServer {
    [self stopServer];

    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *scriptPath = [bundlePath stringByAppendingPathComponent:@"Contents/Resources/server/server.py"];
    NSString *workingDir = [bundlePath stringByAppendingPathComponent:@"Contents/Resources"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        // Fallback for workspace directory
        scriptPath = @"/Users/1orgar/Desktop/amr/server/server.py";
        workingDir = @"/Users/1orgar/Desktop/amr";
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    task.arguments = @[scriptPath, @"--port", [NSString stringWithFormat:@"%ld", (long)self.serverPort]];
    task.currentDirectoryURL = [NSURL fileURLWithPath:workingDir];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *err = nil;
    if ([task launchAndReturnError:&err]) {
        self.serverTask = task;
        NSLog(@"[Sidecar] Server started PID: %d", task.processIdentifier);
    } else {
        NSLog(@"[Sidecar] Failed to start server: %@", err);
    }
}

- (void)stopServer {
    if (self.serverTask && [self.serverTask isRunning]) {
        [self.serverTask terminate];
        self.serverTask = nil;
    }
}

#pragma mark - Menu Construction

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];

    // Track Title
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:self.currentTrackTitle action:nil keyEquivalent:@""];
    NSDictionary *titleAttr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:13]
    };
    titleItem.attributedTitle = [[NSAttributedString alloc] initWithString:self.currentTrackTitle attributes:titleAttr];
    [menu addItem:titleItem];

    // Artist
    if (self.currentArtist.length > 0) {
        NSMenuItem *artistItem = [[NSMenuItem alloc] initWithTitle:self.currentArtist action:nil keyEquivalent:@""];
        NSDictionary *artAttr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        };
        artistItem.attributedTitle = [[NSAttributedString alloc] initWithString:self.currentArtist attributes:artAttr];
        [menu addItem:artistItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    // Playback Controls
    NSString *playTitle = self.isPlaying ? @"⏸ Пауза" : @"▶️ Воспроизведение";
    NSMenuItem *playItem = [[NSMenuItem alloc] initWithTitle:playTitle action:@selector(togglePlayPause) keyEquivalent:@"p"];
    playItem.target = self;
    [menu addItem:playItem];

    NSMenuItem *nextItem = [[NSMenuItem alloc] initWithTitle:@"⏭ Следующий трек" action:@selector(nextTrack) keyEquivalent:@"n"];
    nextItem.target = self;
    [menu addItem:nextItem];

    NSMenuItem *prevItem = [[NSMenuItem alloc] initWithTitle:@"⏮ Предыдущий трек" action:@selector(prevTrack) keyEquivalent:@"b"];
    prevItem.target = self;
    [menu addItem:prevItem];

    [menu addItem:[NSMenuItem separatorItem]];

    // Remote Status
    NSMenuItem *statusHeader = [[NSMenuItem alloc] initWithTitle:@"🟢 Веб-пульт активен:" action:nil keyEquivalent:@""];
    statusHeader.enabled = NO;
    [menu addItem:statusHeader];

    NSMenuItem *copyUrlItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"  %@", self.primaryUrl] action:@selector(copyRemoteUrl) keyEquivalent:@"c"];
    copyUrlItem.target = self;
    copyUrlItem.toolTip = @"Нажмите, чтобы скопировать адрес";
    [menu addItem:copyUrlItem];

    NSMenuItem *openBrowserItem = [[NSMenuItem alloc] initWithTitle:@"🌐 Открыть веб-пульт в браузере" action:@selector(openWebRemote) keyEquivalent:@"o"];
    openBrowserItem.target = self;
    [menu addItem:openBrowserItem];

    NSMenuItem *qrItem = [[NSMenuItem alloc] initWithTitle:@"📱 Показать QR-код для телефона..." action:@selector(showQrCodeWindow) keyEquivalent:@"q"];
    qrItem.target = self;
    [menu addItem:qrItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *restartItem = [[NSMenuItem alloc] initWithTitle:@"🔄 Перезапустить сервер" action:@selector(restartServer) keyEquivalent:@"r"];
    restartItem.target = self;
    [menu addItem:restartItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"❌ Завершить" action:@selector(quitApp) keyEquivalent:@""];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
}

#pragma mark - Status Polling

- (void)pollStatus {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/api/status", (long)self.serverPort]];
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) return;
        NSError *jsonErr = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (json && [json isKindOfClass:[NSDictionary class]]) {
            NSString *state = json[@"player_state"] ?: @"stopped";
            BOOL isPlay = [state isEqualToString:@"playing"];
            NSString *title = @"Ничего не играет";
            NSString *artist = @"";

            NSDictionary *track = json[@"track"];
            if (track && [track isKindOfClass:[NSDictionary class]]) {
                title = track[@"name"] ?: @"Без названия";
                artist = track[@"artist"] ?: @"";
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.isPlaying != isPlay || ![self.currentTrackTitle isEqualToString:title] || ![self.currentArtist isEqualToString:artist]) {
                    self.isPlaying = isPlay;
                    self.currentTrackTitle = title;
                    self.currentArtist = artist;
                    [self rebuildMenu];
                }
            });
        }
    }] resume];

    // Info URL
    NSURL *infoUrl = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/api/info", (long)self.serverPort]];
    [[[NSURLSession sharedSession] dataTaskWithURL:infoUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) return;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (json && [json isKindOfClass:[NSDictionary class]]) {
            NSString *pUrl = json[@"primary_url"];
            if (pUrl && ![self.primaryUrl isEqualToString:pUrl]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.primaryUrl = pUrl;
                    [self rebuildMenu];
                });
            }
        }
    }] resume];
}

#pragma mark - Control Actions

- (void)togglePlayPause {
    [self sendPostRequest:self.isPlaying ? @"/api/pause" : @"/api/play"];
}

- (void)nextTrack {
    [self sendPostRequest:@"/api/next"];
}

- (void)prevTrack {
    [self sendPostRequest:@"/api/prev"];
}

- (void)sendPostRequest:(NSString *)endpoint {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld%@", (long)self.serverPort, endpoint]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self pollStatus];
        });
    }] resume];
}

- (void)copyRemoteUrl {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:self.primaryUrl forType:NSPasteboardTypeString];
}

- (void)openWebRemote {
    if (self.primaryUrl.length > 0) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.primaryUrl]];
    }
}

- (void)showQrCodeWindow {
    if (!self.qrWindow) {
        NSRect frame = NSMakeRect(0, 0, 320, 390);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.title = @"Apple Music Remote";
        [window center];
        window.releasedWhenClosed = NO;

        NSView *container = [[NSView alloc] initWithFrame:window.contentView.bounds];

        NSTextField *titleLabel = [NSTextField labelWithString:@"Сканируйте камерой iPhone/iPad:"];
        titleLabel.frame = NSMakeRect(10, 350, 300, 24);
        titleLabel.alignment = NSTextAlignmentCenter;
        titleLabel.font = [NSFont boldSystemFontOfSize:14];
        [container addSubview:titleLabel];

        NSImageView *imgView = [[NSImageView alloc] initWithFrame:NSMakeRect(35, 75, 250, 250)];
        imgView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [container addSubview:imgView];
        self.qrImageView = imgView;

        NSTextField *urlLabel = [NSTextField labelWithString:self.primaryUrl];
        urlLabel.frame = NSMakeRect(10, 25, 300, 24);
        urlLabel.alignment = NSTextAlignmentCenter;
        urlLabel.textColor = [NSColor systemPinkColor];
        urlLabel.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightSemibold];
        [container addSubview:urlLabel];
        self.qrUrlLabel = urlLabel;

        window.contentView = container;
        self.qrWindow = window;
    }

    self.qrUrlLabel.stringValue = self.primaryUrl;

    NSURL *qrUrl = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/api/qrcode", (long)self.serverPort]];
    [[[NSURLSession sharedSession] dataTaskWithURL:qrUrl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            NSImage *img = [[NSImage alloc] initWithData:data];
            if (img) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.qrImageView.image = img;
                });
            }
        }
    }] resume];

    [self.qrWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)restartServer {
    [self startServer];
    [self rebuildMenu];
}

- (void)quitApp {
    [self stopServer];
    [[NSApplication sharedApplication] terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
