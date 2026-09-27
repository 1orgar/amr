//
//  NativeHTTPServer.m
//  AppleMusicRemote
//

#import "NativeHTTPServer.h"
#import "AppleMusicBridge.h"
#import "CloudService.h"
#import "QRCodeNative.h"
#import "AppConfig.h"
#import "MusicKitBridge-Swift.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <ifaddrs.h>

@interface NativeHTTPServer ()
@property (nonatomic, assign) int serverSocket;
@property (nonatomic, strong) dispatch_queue_t serverQueue;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *sseClients;
@property (nonatomic, strong) NSLock *sseLock;
@property (nonatomic, strong) NSTimer *pollerTimer;
@property (nonatomic, strong) NSDictionary *lastStatus;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *webRoot;
@end

@implementation NativeHTTPServer

+ (instancetype)sharedServer {
    static NativeHTTPServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NativeHTTPServer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverSocket = -1;
        _serverQueue = dispatch_queue_create("com.applemusicremote.httpserver", DISPATCH_QUEUE_CONCURRENT);
        _sseClients = [NSMutableArray array];
        _sseLock = [[NSLock alloc] init];
        _isRunning = NO;
        _port = 8080;
    }
    return self;
}

#pragma mark - Server Lifecycle

- (BOOL)startWithPort:(NSInteger)port webRoot:(NSString *)webRoot {
    [self stop];
    
    self.port = port;
    self.webRoot = webRoot;
    
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        NSLog(@"[HTTP] Failed to create socket");
        return NO;
    }
    
    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);
    
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[HTTP] Failed to bind socket to port %ld", (long)port);
        close(sock);
        return NO;
    }
    
    if (listen(sock, 64) < 0) {
        NSLog(@"[HTTP] Failed to listen on socket");
        close(sock);
        return NO;
    }
    
    self.serverSocket = sock;
    self.isRunning = YES;
    
    NSLog(@"[HTTP] Server started on port %ld, webRoot: %@", (long)port, webRoot);
    
    // Accept loop in background
    dispatch_async(self.serverQueue, ^{
        [self acceptLoop];
    });
    
    // Start Poller on Main Thread
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pollerTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(pollStatus)
                                                          userInfo:nil
                                                           repeats:YES];
    });
    
    return YES;
}

- (void)stop {
    self.isRunning = NO;
    if (self.pollerTimer) {
        [self.pollerTimer invalidate];
        self.pollerTimer = nil;
    }
    
    [self.sseLock lock];
    for (NSNumber *fdNum in self.sseClients) {
        int fd = [fdNum intValue];
        close(fd);
    }
    [self.sseClients removeAllObjects];
    [self.sseLock unlock];
    
    if (self.serverSocket >= 0) {
        close(self.serverSocket);
        self.serverSocket = -1;
    }
}

- (void)acceptLoop {
    while (self.isRunning && self.serverSocket >= 0) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(self.serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientSock < 0) {
            if (!self.isRunning) break;
            continue;
        }
        
        int opt = 1;
        setsockopt(clientSock, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));
        
        dispatch_async(self.serverQueue, ^{
            [self handleClient:clientSock];
        });
    }
}

#pragma mark - HTTP Request Handling

- (void)handleClient:(int)clientSock {
    char buffer[16384];
    ssize_t bytesRead = read(clientSock, buffer, sizeof(buffer) - 1);
    if (bytesRead <= 0) {
        close(clientSock);
        return;
    }
    buffer[bytesRead] = '\0';
    
    NSString *rawRequest = [NSString stringWithUTF8String:buffer];
    if (!rawRequest) {
        rawRequest = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSISOLatin1StringEncoding];
    }
    
    if (!rawRequest || rawRequest.length == 0) {
        close(clientSock);
        return;
    }
    
    NSArray *lines = [rawRequest componentsSeparatedByString:@"\r\n"];
    if (lines.count == 0) {
        close(clientSock);
        return;
    }
    
    NSArray *reqTokens = [lines[0] componentsSeparatedByString:@" "];
    if (reqTokens.count < 2) {
        close(clientSock);
        return;
    }
    
    NSString *method = reqTokens[0];
    NSString *fullPath = reqTokens[1];
    
    // Parse Query Params
    NSString *path = fullPath;
    NSMutableDictionary *queryParams = [NSMutableDictionary dictionary];
    NSRange qRange = [fullPath rangeOfString:@"?"];
    if (qRange.location != NSNotFound) {
        path = [fullPath substringToIndex:qRange.location];
        NSString *qs = [fullPath substringFromIndex:qRange.location + 1];
        NSArray *pairs = [qs componentsSeparatedByString:@"&"];
        for (NSString *p in pairs) {
            NSRange eqRange = [p rangeOfString:@"="];
            if (eqRange.location != NSNotFound) {
                NSString *rawK = [p substringToIndex:eqRange.location];
                NSString *rawV = [p substringFromIndex:eqRange.location + 1];
                NSString *k = [rawK stringByRemovingPercentEncoding] ?: rawK;
                NSString *v = [rawV stringByRemovingPercentEncoding] ?: rawV;
                queryParams[k] = v;
            }
        }
    }
    
    // Parse JSON Body for POST
    NSDictionary *bodyDict = nil;
    if ([method isEqualToString:@"POST"]) {
        NSRange bodyRange = [rawRequest rangeOfString:@"\r\n\r\n"];
        if (bodyRange.location != NSNotFound) {
            NSString *bodyStr = [rawRequest substringFromIndex:bodyRange.location + 4];
            NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
            if (bodyData) {
                bodyDict = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
            }
        }
    }
    
    // Handle CORS OPTIONS
    if ([method isEqualToString:@"OPTIONS"]) {
        NSString *resp = @"HTTP/1.1 204 No Content\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        @"Access-Control-Allow-Headers: Content-Type\r\n"
        @"Connection: close\r\n\r\n";
        send(clientSock, [resp UTF8String], [resp lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
        close(clientSock);
        return;
    }
    
    // Route SSE Events
    if ([path isEqualToString:@"/api/events"]) {
        [self handleSSEConnection:clientSock];
        return;
    }
    
    // Route API or Static Files
    if ([path hasPrefix:@"/api/"]) {
        [self handleAPIPath:path method:method query:queryParams body:bodyDict clientSock:clientSock];
    } else {
        [self handleStaticPath:path clientSock:clientSock];
    }
}

#pragma mark - REST API Dispatcher

- (void)handleAPIPath:(NSString *)path method:(NSString *)method query:(NSDictionary *)query body:(NSDictionary *)body clientSock:(int)clientSock {
    AppleMusicBridge *bridge = [AppleMusicBridge sharedBridge];
    AppConfig *config = [AppConfig sharedConfig];
    
    if ([path isEqualToString:@"/api/status"]) {
        NSDictionary *status = [bridge getPlayerStatus];
        [self sendJSONResponse:status statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/playlists"]) {
        NSArray *playlists = [bridge getPlaylists];
        [self sendJSONResponse:@{@"playlists": playlists} statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/library/artists"]) {
        NSArray *artists = [bridge getLibraryArtists];
        [self sendJSONResponse:@{@"artists": artists} statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/library/songs"]) {
        NSArray *songs = [bridge getLibrarySongs];
        [self sendJSONResponse:@{@"songs": songs} statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/playlists/tracks"]) {
        NSString *name = query[@"name"] ?: @"";
        NSArray *tracks = [bridge getPlaylistTracks:name];
        [self sendJSONResponse:@{@"playlist": name, @"tracks": tracks} statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/player/queue"] || [path isEqualToString:@"/api/queue"]) {
        NSDictionary *queueDict = [bridge getPlaybackQueue];
        [self sendJSONResponse:queueDict statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/artwork/current"]) {
        NSData *artData = [bridge getCurrentTrackArtwork];
        if (artData && artData.length > 0) {
            [self sendDataResponse:artData contentType:@"image/jpeg" statusCode:200 clientSock:clientSock];
        } else {
            [self sendJSONResponse:@{@"error": @"No artwork"} statusCode:404 clientSock:clientSock];
        }
        return;
    }
    
    if ([path isEqualToString:@"/api/artwork/playlist"]) {
        NSString *name = query[@"name"] ?: @"";
        NSData *artData = [bridge getPlaylistArtwork:name];
        if (artData && artData.length > 0) {
            [self sendDataResponse:artData contentType:@"image/jpeg" statusCode:200 clientSock:clientSock];
        } else {
            [self sendJSONResponse:@{@"error": @"No artwork"} statusCode:404 clientSock:clientSock];
        }
        return;
    }
    
    if ([path isEqualToString:@"/api/artwork/track"] || [path isEqualToString:@"/api/artwork"]) {
        NSString *idStr = query[@"id"] ?: query[@"track_id"];
        if (idStr) {
            NSData *artData = [bridge getTrackArtwork:[idStr integerValue]];
            if (artData && artData.length > 0) {
                [self sendDataResponse:artData contentType:@"image/jpeg" statusCode:200 clientSock:clientSock];
                return;
            }
        }
        [self sendJSONResponse:@{@"error": @"No artwork"} statusCode:404 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/explore"]) {
        NSString *country = query[@"country"] ?: (config.country ?: @"ru");
        NSDictionary *personalFeed = [bridge getPersonalHomeFeed];
        [[CloudService sharedService] getExploreFeedWithCountry:country completion:^(NSDictionary *cloudFeed) {
            NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:cloudFeed ?: @{}];
            
            if (personalFeed) {
                if (personalFeed[@"top_picks"] && [personalFeed[@"top_picks"] count] > 0) {
                    merged[@"top_picks"] = personalFeed[@"top_picks"];
                }
                if (personalFeed[@"recently_played"] && [personalFeed[@"recently_played"] count] > 0) {
                    merged[@"recently_played"] = personalFeed[@"recently_played"];
                }
                if (personalFeed[@"playlists_for_you"] && [personalFeed[@"playlists_for_you"] count] > 0) {
                    merged[@"playlists_for_you"] = personalFeed[@"playlists_for_you"];
                }
                if (personalFeed[@"new_releases"] && [personalFeed[@"new_releases"] count] > 0) {
                    merged[@"new_releases"] = personalFeed[@"new_releases"];
                }
            }
            
            if (!merged[@"stations"] || [merged[@"stations"] count] == 0) {
                merged[@"stations"] = [[CloudService sharedService] getCuratedStationsWithCountry:country];
            }
            
            [self sendJSONResponse:@{@"data": merged} statusCode:200 clientSock:clientSock];
        }];
        return;
    }
    
    if ([path isEqualToString:@"/api/search"]) {
        NSString *q = query[@"q"] ?: @"";
        NSString *source = query[@"source"] ?: @"cloud";
        NSString *country = query[@"country"] ?: (config.country ?: @"ru");
        
        if ([source isEqualToString:@"library"]) {
            NSArray *tracks = [bridge getLibrarySongs];
            NSMutableArray *filtered = [NSMutableArray array];
            NSString *lowerQ = [q lowercaseString];
            for (NSDictionary *t in tracks) {
                NSString *name = [t[@"name"] lowercaseString];
                NSString *artist = [t[@"artist"] lowercaseString];
                NSString *album = [t[@"album"] lowercaseString];
                if ([name containsString:lowerQ] || [artist containsString:lowerQ] || [album containsString:lowerQ]) {
                    [filtered addObject:t];
                }
            }
            [self sendJSONResponse:@{@"data": @{@"library": filtered}} statusCode:200 clientSock:clientSock];
        } else {
            [[CloudService sharedService] searchWithQuery:q country:country completion:^(NSDictionary *result) {
                [self sendJSONResponse:@{@"data": @{@"cloud": result ?: @{}}} statusCode:200 clientSock:clientSock];
            }];
        }
        return;
    }
    
    if ([path isEqualToString:@"/api/stations"]) {
        NSString *country = query[@"country"] ?: (config.country ?: @"ru");
        NSArray *stations = [[CloudService sharedService] getCuratedStationsWithCountry:country];
        [self sendJSONResponse:@{@"stations": stations ?: @[]} statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/album"]) {
        NSString *albumId = query[@"id"] ?: @"";
        NSString *country = query[@"country"] ?: (config.country ?: @"ru");
        [[CloudService sharedService] getAlbumDetails:albumId country:country completion:^(NSDictionary *result) {
            if (result) {
                [self sendJSONResponse:@{@"album": result} statusCode:200 clientSock:clientSock];
            } else {
                [self sendJSONResponse:@{@"error": @"Album not found"} statusCode:404 clientSock:clientSock];
            }
        }];
        return;
    }
    
    if ([path isEqualToString:@"/api/info"]) {
        NSArray *ips = [self getLANIPAddresses];
        NSMutableArray *urls = [NSMutableArray array];
        for (NSString *ip in ips) {
            [urls addObject:[NSString stringWithFormat:@"http://%@:%ld", ip, (long)self.port]];
        }
        NSString *primaryUrl = [self getPrimaryURL];
        NSString *qrSvg = [QRCodeNative generateSVGForString:primaryUrl];
        [self sendJSONResponse:@{
            @"port": @(self.port),
            @"primary_url": primaryUrl,
            @"urls": urls,
            @"qr_svg": qrSvg ?: @""
        } statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/qr"]) {
        NSString *url = query[@"url"] ?: [self getPrimaryURL];
        NSString *svg = [QRCodeNative generateSVGForString:url];
        [self sendDataResponse:[svg dataUsingEncoding:NSUTF8StringEncoding] contentType:@"image/svg+xml" statusCode:200 clientSock:clientSock];
        return;
    }
    
    if ([path isEqualToString:@"/api/settings"]) {
        if ([method isEqualToString:@"POST"]) {
            BOOL ok = [config saveWithDictionary:body ?: @{}];
            [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"settings": [config dictionaryRepresentation]} statusCode:ok ? 200 : 500 clientSock:clientSock];
        } else {
            [self sendJSONResponse:@{@"settings": [config dictionaryRepresentation]} statusCode:200 clientSock:clientSock];
        }
        return;
    }
    
    // POST Player Actions
    if ([path isEqualToString:@"/api/play"]) {
        BOOL ok = [bridge play];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/pause"]) {
        BOOL ok = [bridge pause];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/playpause"]) {
        BOOL ok = [bridge playPause];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/next"]) {
        BOOL ok = [bridge nextTrack];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/prev"]) {
        BOOL ok = [bridge previousTrack];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/seek"]) {
        double pos = [body[@"position"] doubleValue];
        BOOL ok = [bridge seekToPosition:pos];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"position": @(pos)} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/volume"]) {
        NSInteger vol = [body[@"volume"] integerValue];
        BOOL ok = [bridge setVolume:vol];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"volume": @(vol)} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/shuffle"]) {
        BOOL enabled = [body[@"enabled"] boolValue];
        BOOL ok = [bridge setShuffle:enabled];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"shuffle": @(enabled)} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/favorite"]) {
        BOOL ok = [bridge toggleCurrentTrackFavorite];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/repeat"]) {
        NSString *mode = body[@"mode"] ?: @"off";
        BOOL ok = [bridge setRepeatMode:mode];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"repeat": mode} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/play/playlist"]) {
        NSString *pName = body[@"playlist"] ?: @"";
        NSNumber *tId = nil;
        if (body[@"track_id"] && body[@"track_id"] != [NSNull null]) {
            tId = @([body[@"track_id"] longLongValue]);
        }
        NSNumber *tIdx = nil;
        if (body[@"track_index"] && body[@"track_index"] != [NSNull null]) {
            tIdx = @([body[@"track_index"] integerValue]);
        }
        BOOL shuffle = [body[@"shuffle"] boolValue];
        BOOL ok = [bridge playPlaylist:pName trackId:tId trackIndex:tIdx shuffle:shuffle];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"playlist": pName} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/play/track"]) {
        NSNumber *tId = nil;
        if (body[@"track_id"] && body[@"track_id"] != [NSNull null]) {
            tId = @([body[@"track_id"] longLongValue]);
        }
        BOOL ok = [bridge playTrackId:tId];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"track_id": tId ?: @0} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/play/cloud"]) {
        NSString *url = body[@"url"] ?: @"";
        NSString *storeID = body[@"id"];
        NSString *name = body[@"name"];
        NSString *artist = body[@"artist"];
        NSString *previewUrl = body[@"preview_url"] ?: @"";
        
        if (url.length == 0 && storeID) {
            url = [NSString stringWithFormat:@"https://music.apple.com/album/song/%@", storeID];
        }
        
        BOOL ok = [bridge playCloudUrl:url trackName:name artistName:artist previewUrl:previewUrl];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"url": url} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/play/station"]) {
        NSString *url = body[@"url"] ?: @"";
        NSString *name = body[@"name"] ?: @"Apple Music Radio";
        BOOL ok = [bridge playStationUrl:url name:name];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error", @"station": name} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/play/custom_queue"]) {
        NSArray *tracks = body[@"tracks"];
        BOOL shuffle = [body[@"shuffle"] boolValue];
        NSInteger startIdx = [body[@"start_index"] integerValue];
        NSString *qName = body[@"queue_name"] ?: @"Очередь";
        
        BOOL ok = [bridge playCustomTracks:tracks startIndex:startIdx shuffle:shuffle queueName:qName];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/queue/add"]) {
        NSDictionary *singleTrack = body[@"track"];
        NSArray *multipleTracks = body[@"tracks"];
        BOOL ok = NO;
        if (multipleTracks && multipleTracks.count > 0) {
            ok = [bridge enqueueTracks:multipleTracks playNext:NO];
        } else if (singleTrack) {
            ok = [bridge enqueueTrack:singleTrack playNext:NO];
        }
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/queue/play_next"]) {
        NSDictionary *singleTrack = body[@"track"];
        NSArray *multipleTracks = body[@"tracks"];
        BOOL ok = NO;
        if (multipleTracks && multipleTracks.count > 0) {
            ok = [bridge enqueueTracks:multipleTracks playNext:YES];
        } else if (singleTrack) {
            ok = [bridge enqueueTrack:singleTrack playNext:YES];
        }
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/queue/remove"]) {
        NSInteger idx = [body[@"index"] integerValue];
        BOOL ok = [bridge removeQueueTrackAtIndex:idx];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/queue/clear"]) {
        BOOL ok = [bridge clearUpcomingQueue];
        [self broadcastCurrentStatus];
        [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
        return;
    }
    if ([path isEqualToString:@"/api/player/queue/play"] || [path isEqualToString:@"/api/play/queue_index"] || [path isEqualToString:@"/api/queue/play_index"]) {
        if (bridge.isCustomQueuePlayback) {
            NSInteger idx = [body[@"index"] integerValue];
            BOOL ok = [bridge playQueueIndex:idx];
            [self broadcastCurrentStatus];
            [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
            return;
        } else {
            NSString *pName = body[@"playlist"] ?: @"";
            NSNumber *tId = nil;
            if (body[@"track_id"] && body[@"track_id"] != [NSNull null]) {
                tId = @([body[@"track_id"] longLongValue]);
            }
            BOOL ok = [bridge playPlaylist:pName trackId:tId trackIndex:nil shuffle:NO];
            [self broadcastCurrentStatus];
            [self sendJSONResponse:@{@"status": ok ? @"ok" : @"error"} statusCode:200 clientSock:clientSock];
            return;
        }
    }
    
    [self sendJSONResponse:@{@"error": @"Not found"} statusCode:404 clientSock:clientSock];
}

#pragma mark - Static File Handling

- (void)handleStaticPath:(NSString *)reqPath clientSock:(int)clientSock {
    NSString *cleanPath = reqPath;
    if ([cleanPath isEqualToString:@"/"] || cleanPath.length == 0) {
        cleanPath = @"/index.html";
    }
    
    NSString *fullFilePath = [[self.webRoot stringByAppendingPathComponent:cleanPath] stringByStandardizingPath];
    if (![fullFilePath hasPrefix:[self.webRoot stringByStandardizingPath]]) {
        [self sendJSONResponse:@{@"error": @"Access denied"} statusCode:403 clientSock:clientSock];
        return;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullFilePath]) {
        [self sendJSONResponse:@{@"error": @"File not found"} statusCode:404 clientSock:clientSock];
        return;
    }
    
    NSData *fileData = [NSData dataWithContentsOfFile:fullFilePath];
    if (!fileData) {
        [self sendJSONResponse:@{@"error": @"Read error"} statusCode:500 clientSock:clientSock];
        return;
    }
    
    NSString *ext = [[fullFilePath pathExtension] lowercaseString];
    NSString *contentType = @"text/plain";
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) contentType = @"text/html; charset=utf-8";
    else if ([ext isEqualToString:@"css"]) contentType = @"text/css; charset=utf-8";
    else if ([ext isEqualToString:@"js"]) contentType = @"application/javascript; charset=utf-8";
    else if ([ext isEqualToString:@"png"]) contentType = @"image/png";
    else if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) contentType = @"image/jpeg";
    else if ([ext isEqualToString:@"svg"]) contentType = @"image/svg+xml";
    else if ([ext isEqualToString:@"json"]) contentType = @"application/json; charset=utf-8";
    else if ([ext isEqualToString:@"ico"]) contentType = @"image/x-icon";
    else if ([ext isEqualToString:@"webp"]) contentType = @"image/webp";
    
    [self sendDataResponse:fileData contentType:contentType statusCode:200 clientSock:clientSock];
}

#pragma mark - Responses & SSE

- (void)sendJSONResponse:(NSDictionary *)dict statusCode:(int)code clientSock:(int)clientSock {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!jsonData) jsonData = [@"{\"status\":\"ok\"}" dataUsingEncoding:NSUTF8StringEncoding];
    [self sendDataResponse:jsonData contentType:@"application/json; charset=utf-8" statusCode:code clientSock:clientSock];
}

- (void)sendDataResponse:(NSData *)data contentType:(NSString *)contentType statusCode:(int)code clientSock:(int)clientSock {
    NSString *statusText = (code == 200) ? @"OK" : ((code == 404) ? @"Not Found" : @"Error");
    NSString *header = [NSString stringWithFormat:
    @"HTTP/1.1 %d %@\r\n"
    @"Content-Type: %@\r\n"
    @"Content-Length: %lu\r\n"
    @"Cache-Control: no-cache, no-store, must-revalidate\r\n"
    @"Access-Control-Allow-Origin: *\r\n"
    @"Connection: close\r\n\r\n", code, statusText, contentType, (unsigned long)data.length];
    
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    send(clientSock, [headerData bytes], [headerData length], 0);
    send(clientSock, [data bytes], [data length], 0);
    close(clientSock);
}

- (void)handleSSEConnection:(int)clientSock {
    NSString *header =
    @"HTTP/1.1 200 OK\r\n"
    @"Content-Type: text/event-stream\r\n"
    @"Cache-Control: no-cache\r\n"
    @"Connection: keep-alive\r\n"
    @"Access-Control-Allow-Origin: *\r\n\r\n";
    
    send(clientSock, [header UTF8String], [header lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
    
    // Send initial status
    NSDictionary *initialStatus = [[AppleMusicBridge sharedBridge] getPlayerStatus];
    NSData *initJson = [NSJSONSerialization dataWithJSONObject:initialStatus options:0 error:nil];
    if (initJson) {
        NSString *event = [NSString stringWithFormat:@"event: status\ndata: %@\n\n", [[NSString alloc] initWithData:initJson encoding:NSUTF8StringEncoding]];
        send(clientSock, [event UTF8String], [event lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 0);
    }
    
    [self.sseLock lock];
    [self.sseClients addObject:@(clientSock)];
    [self.sseLock unlock];
}

- (void)pollStatus {
    [[AppleMusicBridge sharedBridge] checkAndAutoAdvanceCloudQueue];
    NSDictionary *current = [[AppleMusicBridge sharedBridge] getPlayerStatus];
    if (![current isEqualToDictionary:self.lastStatus]) {
        self.lastStatus = current;
        [self broadcastStatus:current];
    }
}

- (void)broadcastCurrentStatus {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *current = [[AppleMusicBridge sharedBridge] getPlayerStatus];
        self.lastStatus = current;
        [self broadcastStatus:current];
    });
}

- (void)broadcastStatus:(NSDictionary *)status {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    if (!jsonData) return;
    
    NSString *event = [NSString stringWithFormat:@"event: status\ndata: %@\n\n", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]];
    const char *eventBytes = [event UTF8String];
    size_t eventLen = [event lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    [self.sseLock lock];
    NSMutableArray *deadClients = [NSMutableArray array];
    for (NSNumber *fdNum in self.sseClients) {
        int fd = [fdNum intValue];
        ssize_t sent = send(fd, eventBytes, eventLen, 0);
        if (sent <= 0) {
            close(fd);
            [deadClients addObject:fdNum];
        }
    }
    [self.sseClients removeObjectsInArray:deadClients];
    [self.sseLock unlock];
}

#pragma mark - Network Utilities

- (NSArray<NSString *> *)getLANIPAddresses {
    NSMutableArray *ips = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) == 0) {
        struct ifaddrs *temp = interfaces;
        while (temp != NULL) {
            if (temp->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp->ifa_name];
                NSString *addr = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp->ifa_addr)->sin_addr)];
                if (![addr isEqualToString:@"127.0.0.1"] && ([name hasPrefix:@"en"] || [name hasPrefix:@"wlan"] || [name hasPrefix:@"eth"])) {
                    if (![ips containsObject:addr]) {
                        [ips addObject:addr];
                    }
                }
            }
            temp = temp->ifa_next;
        }
        freeifaddrs(interfaces);
    }
    if (ips.count == 0) {
        [ips addObject:@"127.0.0.1"];
    }
    return ips;
}

- (NSString *)getPrimaryURL {
    NSArray *ips = [self getLANIPAddresses];
    NSString *ip = ips.firstObject ?: @"127.0.0.1";
    return [NSString stringWithFormat:@"http://%@:%ld", ip, (long)self.port];
}

@end
