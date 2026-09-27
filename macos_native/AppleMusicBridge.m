//
//  AppleMusicBridge.m
//  AppleMusicRemote
//

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "AppleMusicBridge.h"
#import "MusicApp.h"
#import "MusicKitBridge-Swift.h"

static NSString *const kTrackSep = @"___TRACK_SEP___";
static NSString *const kFieldSep = @"___FIELD_SEP___";

@interface AppleMusicBridge ()
@property (nonatomic, strong) NSCache<NSString *, NSData *> *artworkCache;
@property (nonatomic, strong) MusicApplication *musicApp;
@property (nonatomic, strong) NSDictionary *cachedHomeFeed;
@property (nonatomic, strong) NSDate *homeFeedTimestamp;
@property (nonatomic, copy, nullable) NSString *currentOriginalPlaylistName;
@property (nonatomic, strong, nullable) NSMutableArray<NSDictionary *> *activeCustomQueue;
@property (nonatomic, assign) NSInteger activeCustomQueueIndex;
@property (nonatomic, strong, nullable) NSString *activeCustomQueueName;
@property (nonatomic, assign) BOOL isCustomQueuePlayback;
@property (nonatomic, assign) BOOL isRadioPlayback;
@property (nonatomic, strong, nullable) NSString *activeStationName;
@property (nonatomic, assign) BOOL lastWasPlayingCloud;
@property (nonatomic, strong, nullable) NSDate *lastCloudPlayTime;
@end

@implementation AppleMusicBridge

+ (instancetype)sharedBridge {
    static AppleMusicBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AppleMusicBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _artworkCache = [[NSCache alloc] init];
        _artworkCache.countLimit = 100;
        _musicApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.Music"];
        _activeCustomQueue = [NSMutableArray array];
        _activeCustomQueueIndex = 0;
    }
    return self;
}

#pragma mark - Player Controls

- (NSDictionary *)getPlayerStatus {
    // 1. Radio / Station Playback Mode
    if (self.isRadioPlayback) {
        MusicEPlS pState = self.musicApp.playerState;
        NSString *stateStr = (pState == MusicEPlSPlaying) ? @"playing" : ((pState == MusicEPlSPaused) ? @"paused" : @"stopped");
        SBAMTrack *currentTrack = self.musicApp.currentTrack;
        NSString *tName = currentTrack.name ?: (self.activeStationName ?: @"Apple Music Radio");
        NSString *tArtist = currentTrack.artist ?: @"Apple Music";
        NSString *tAlbum = currentTrack.album ?: @"Прямой эфир";
        double pos = self.musicApp.playerPosition;
        double dur = currentTrack.duration;
        
        BOOL hasArt = NO;
        @try {
            if ([[currentTrack artworks] count] > 0) hasArt = YES;
        } @catch (NSException *e) {}
        
        NSString *artUrl = hasArt ? [NSString stringWithFormat:@"/api/artwork/current?id=%ld", (long)currentTrack.databaseID] : @"";
        
        return @{
            @"player_state": stateStr,
            @"position": @(pos),
            @"duration": @(dur > 0 ? dur : 0),
            @"volume": @(self.musicApp.soundVolume),
            @"shuffle": @(NO),
            @"repeat": @"off",
            @"playlist": self.activeStationName ?: @"Apple Music Radio",
            @"is_radio": @YES,
            @"audio_quality": @"Lossless (ALAC 24-bit/48kHz)",
            @"track": @{
                @"id": @(currentTrack.databaseID),
                @"name": tName,
                @"artist": tArtist,
                @"album": tAlbum,
                @"duration": @(dur),
                @"has_artwork": @(hasArt),
                @"artwork_url": artUrl,
                @"favorited": @(NO)
            }
        };
    }

    MusicEPlS pState = self.musicApp.playerState;
    NSString *stateStr = @"stopped";
    
    if (pState == MusicEPlSPlaying) stateStr = @"playing";
    else if (pState == MusicEPlSPaused) stateStr = @"paused";
    else if (pState == MusicEPlSFastForwarding) stateStr = @"fast forwarding";
    else if (pState == MusicEPlSRewinding) stateStr = @"rewinding";
    
    if (pState == MusicEPlSStopped) {
        if (self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueueIndex < self.activeCustomQueue.count) {
            NSDictionary *qTrack = self.activeCustomQueue[self.activeCustomQueueIndex];
            NSString *artUrl = qTrack[@"artwork"] ?: @"";
            return @{
                @"player_state": @"stopped",
                @"position": @0,
                @"duration": @([qTrack[@"duration"] doubleValue]),
                @"volume": @(self.musicApp.soundVolume),
                @"shuffle": @(self.musicApp.shuffleEnabled),
                @"repeat": @"off",
                @"playlist": self.activeCustomQueueName ?: @"Очередь",
                @"track": @{
                    @"id": qTrack[@"id"] ?: @0,
                    @"name": qTrack[@"name"] ?: @"",
                    @"artist": qTrack[@"artist"] ?: @"",
                    @"album": qTrack[@"album"] ?: @"",
                    @"duration": @([qTrack[@"duration"] doubleValue]),
                    @"has_artwork": @(artUrl.length > 0),
                    @"artwork_url": artUrl,
                    @"favorited": @(NO)
                }
            };
        }
        return @{
            @"player_state": stateStr,
            @"position": @0,
            @"duration": @0,
            @"volume": @(self.musicApp.soundVolume),
            @"shuffle": @(self.musicApp.shuffleEnabled),
            @"repeat": @"off",
            @"track": [NSNull null]
        };
    }
    
    SBAMTrack *currentTrack = self.musicApp.currentTrack;
    NSString *tName = currentTrack.name ?: @"";
    NSString *tArtist = currentTrack.artist ?: @"";
    NSString *tAlbum = currentTrack.album ?: @"";
    double pos = self.musicApp.playerPosition;
    double dur = currentTrack.duration;
    NSInteger vol = self.musicApp.soundVolume;
    BOOL shuf = self.musicApp.shuffleEnabled;
    
    // Enrich with active custom queue if track is numeric stream or empty
    if (self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueueIndex < self.activeCustomQueue.count) {
        NSDictionary *curQueueTrack = self.activeCustomQueue[self.activeCustomQueueIndex];
        BOOL isNumeric = NO;
        if (tName.length > 0) {
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([tName rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                isNumeric = YES;
            }
        }
        if (tName.length == 0 || isNumeric) {
            tName = curQueueTrack[@"name"] ?: tName;
            tArtist = curQueueTrack[@"artist"] ?: tArtist;
            tAlbum = curQueueTrack[@"album"] ?: tAlbum;
            if (dur <= 0.0) dur = [curQueueTrack[@"duration"] doubleValue];
        }
    }
    
    MusicERpt rMode = self.musicApp.songRepeat;
    NSString *repMode = @"off";
    if (rMode == MusicERptOne) repMode = @"one";
    else if (rMode == MusicERptAll) repMode = @"all";
    
    BOOL hasArt = NO;
    BOOL isFavorited = NO;
    @try {
        if ([[currentTrack artworks] count] > 0) hasArt = YES;
        isFavorited = currentTrack.favorited || currentTrack.loved;
    } @catch (NSException *e) {}
    
    NSString *currentPlName = @"Музыка";
    if (self.isCustomQueuePlayback && self.activeCustomQueueName.length > 0) {
        currentPlName = self.activeCustomQueueName;
    } else {
        @try {
            NSString *pName = self.musicApp.currentPlaylist.name;
            if (pName && pName.length > 0) currentPlName = pName;
        } @catch (NSException *e) {}
    }
    
    id trackObj = [NSNull null];
    if (tName.length > 0) {
        NSString *artUrl = hasArt ? [NSString stringWithFormat:@"/api/artwork/current?id=%ld", (long)currentTrack.databaseID] : @"";
        if (artUrl.length == 0 && self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueueIndex < self.activeCustomQueue.count) {
            NSString *customArt = self.activeCustomQueue[self.activeCustomQueueIndex][@"artwork"];
            if (customArt.length > 0) {
                artUrl = customArt;
                hasArt = YES;
            }
        }
        trackObj = @{
            @"id": @(currentTrack.databaseID),
            @"name": tName,
            @"artist": tArtist,
            @"album": tAlbum,
            @"duration": @(dur),
            @"has_artwork": @(hasArt),
            @"artwork_url": artUrl,
            @"favorited": @(isFavorited)
        };
    }
    
    return @{
        @"player_state": stateStr,
        @"position": @(pos),
        @"duration": @(dur),
        @"volume": @(vol),
        @"shuffle": @(shuf),
        @"repeat": repMode,
        @"playlist": currentPlName,
        @"track": trackObj
    };
}

- (BOOL)toggleCurrentTrackFavorite {
    @try {
        SBAMTrack *t = self.musicApp.currentTrack;
        if (t) {
            BOOL cur = NO;
            @try { cur = t.favorited || t.loved; } @catch (NSException *e) {}
            BOOL nextVal = !cur;
            @try { t.favorited = nextVal; } @catch (NSException *e) {}
            @try { t.loved = nextVal; } @catch (NSException *e) {}
            return YES;
        }
    } @catch (NSException *e) {}
    return NO;
}

- (BOOL)play {
    @try {
        if (self.musicApp.playerState == MusicEPlSStopped) {
            [self.musicApp playOnce:NO];
        } else {
            [self.musicApp playpause];
        }
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)pause {
    @try {
        [self.musicApp pause];
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)playPause {
    @try {
        [self.musicApp playpause];
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)nextTrack {
    @try {
        if (self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueue.count > 0) {
            if (self.activeCustomQueueIndex + 1 < self.activeCustomQueue.count) {
                return [self playQueueIndex:self.activeCustomQueueIndex + 1];
            } else {
                MusicERpt rMode = self.musicApp.songRepeat;
                if (rMode == MusicERptAll) {
                    return [self playQueueIndex:0];
                }
            }
            return NO;
        }
        [self.musicApp nextTrack];
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)previousTrack {
    @try {
        if (self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueue.count > 0) {
            double pos = self.musicApp.playerPosition;
            if (pos > 3.0) {
                self.musicApp.playerPosition = 0;
                return YES;
            }
            if (self.activeCustomQueueIndex > 0) {
                return [self playQueueIndex:self.activeCustomQueueIndex - 1];
            }
            return NO;
        }
        [self.musicApp previousTrack];
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)seekToPosition:(double)position {
    @try {
        self.musicApp.playerPosition = position;
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)setVolume:(NSInteger)volume {
    @try {
        self.musicApp.soundVolume = volume;
        return YES;
    } @catch (NSException *e) { return NO; }
}

- (BOOL)setShuffle:(BOOL)enabled {
    @try {
        if (enabled) {
            MusicPlaylist *curPl = self.musicApp.currentPlaylist;
            NSString *plName = self.currentOriginalPlaylistName ?: curPl.name;
            NSNumber *curId = @(self.musicApp.currentTrack.databaseID);
            return [self playPlaylist:plName trackId:curId trackIndex:nil shuffle:YES];
        } else {
            if (self.currentOriginalPlaylistName.length > 0) {
                NSNumber *curId = @(self.musicApp.currentTrack.databaseID);
                return [self playPlaylist:self.currentOriginalPlaylistName trackId:curId trackIndex:nil shuffle:NO];
            } else {
                self.musicApp.shuffleEnabled = NO;
                return YES;
            }
        }
    } @catch (NSException *e) { return NO; }
}

- (BOOL)setRepeatMode:(NSString *)mode {
    @try {
        MusicERpt rMode = MusicERptOff;
        if ([mode isEqualToString:@"all"]) rMode = MusicERptAll;
        else if ([mode isEqualToString:@"one"]) rMode = MusicERptOne;
        self.musicApp.songRepeat = rMode;
        return YES;
    } @catch (NSException *e) { return NO; }
}

#pragma mark - Playlists & Tracks

- (NSArray<NSDictionary *> *)getPlaylists {
    NSMutableArray *list = [NSMutableArray array];
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            @try {
                NSString *name = p.name;
                if ([name isEqualToString:@"Музыка"] || [name isEqualToString:@"Music"] || [name isEqualToString:@"Библиотека"] || [name isEqualToString:@"Очередь AMR"]) {
                    continue;
                }
                NSInteger count = [[p tracks] count];
                if (count > 0) {
                    [list addObject:@{@"name": name ?: @"", @"track_count": @(count)}];
                }
            } @catch (NSException *e) {}
        }
    } @catch (NSException *e) {}
    
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return list;
}

static BOOL isValidLibraryTrack(NSString *name, NSString *artist, double duration) {
    if (!name || name.length == 0) return NO;
    if (duration <= 0.0) return NO;
    
    // Filter purely numeric names (such as temporary streaming/catalog IDs e.g. "1569456892")
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([name rangeOfCharacterFromSet:nonDigits].location == NSNotFound) return NO;
    
    // Filter raw media / playlist file names (.mkv.m3u etc)
    if ([name hasSuffix:@".mkv.m3u"] || [name hasSuffix:@".m3u"]) return NO;
    
    return YES;
}

- (NSArray<NSDictionary *> *)getLibraryArtists {
    NSMutableSet *artistSet = [NSMutableSet set];
    NSMutableArray *list = [NSMutableArray array];
    
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            NSString *name = p.name;
            if ([name isEqualToString:@"Музыка"] || [name isEqualToString:@"Music"] || [name isEqualToString:@"Библиотека"]) {
                SBElementArray<SBAMTrack *> *tracks = [p tracks];
                for (SBAMTrack *t in tracks) {
                    @try {
                        NSString *artist = t.artist;
                        if (artist && artist.length > 0 && isValidLibraryTrack(t.name, artist, t.duration) && ![artistSet containsObject:artist]) {
                            [artistSet addObject:artist];
                            [list addObject:@{@"name": artist}];
                        }
                    } @catch (NSException *e) {}
                }
                break; // Found the main library playlist
            }
        }
    } @catch (NSException *e) {}
    
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return list;
}

- (NSArray<NSDictionary *> *)getLibrarySongs {
    NSMutableArray *list = [NSMutableArray array];
    
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            NSString *name = p.name;
            if ([name isEqualToString:@"Музыка"] || [name isEqualToString:@"Music"] || [name isEqualToString:@"Библиотека"]) {
                SBElementArray<SBAMTrack *> *tracks = [p tracks];
                NSInteger idx = 1;
                for (SBAMTrack *t in tracks) {
                    @try {
                        NSString *tName = t.name ?: @"";
                        NSString *tArtist = t.artist ?: @"";
                        double dur = t.duration;
                        if (isValidLibraryTrack(tName, tArtist, dur)) {
                            [list addObject:@{
                                @"index": @(idx++),
                                @"id": @(t.databaseID),
                                @"name": tName,
                                @"artist": tArtist,
                                @"album": t.album ?: @"",
                                @"duration": @(dur)
                            }];
                        }
                    } @catch (NSException *e) {}
                }
                break; // Found the main library playlist
            }
        }
    } @catch (NSException *e) {}
    
    return list;
}

- (NSArray<NSDictionary *> *)getPlaylistTracks:(NSString *)playlistName {
    if (!playlistName || playlistName.length == 0) return @[];
    NSMutableArray *list = [NSMutableArray array];
    
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            if ([p.name isEqualToString:playlistName]) {
                SBElementArray<SBAMTrack *> *tracks = [p tracks];
                NSInteger idx = 1;
                for (SBAMTrack *t in tracks) {
                    @try {
                        NSString *name = t.name ?: @"";
                        NSString *artist = t.artist ?: @"";
                        double dur = t.duration;
                        if (isValidLibraryTrack(name, artist, dur)) {
                            [list addObject:@{
                                @"index": @(idx++),
                                @"id": @(t.databaseID),
                                @"name": name,
                                @"artist": artist,
                                @"album": t.album ?: @"",
                                @"duration": @(dur),
                                @"artwork": [NSString stringWithFormat:@"/api/artwork/track?id=%ld", (long)t.databaseID]
                            }];
                        }
                    } @catch (NSException *e) {}
                }
                break;
            }
        }
    } @catch (NSException *e) {}
    
    return list;
}

- (BOOL)playPlaylist:(NSString *)playlistName trackId:(NSNumber *)trackId trackIndex:(NSNumber *)trackIndex {
    return [self playPlaylist:playlistName trackId:trackId trackIndex:trackIndex shuffle:NO];
}

- (BOOL)playPlaylist:(NSString *)playlistName trackId:(NSNumber *)trackId trackIndex:(NSNumber *)trackIndex shuffle:(BOOL)shuffle {
    if (!playlistName || playlistName.length == 0) playlistName = @"Музыка";
    if ([playlistName isEqualToString:@"Очередь AMR"] && self.currentOriginalPlaylistName.length > 0) {
        playlistName = self.currentOriginalPlaylistName;
    }
    self.currentOriginalPlaylistName = playlistName;
    self.isCustomQueuePlayback = NO;
    self.activeCustomQueue = [NSMutableArray array];
    self.activeCustomQueueName = nil;
    
    @try {
        NSString *escapedPl = [playlistName stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        
        if (shuffle) {
            NSArray<NSDictionary *> *allTracks = [self getPlaylistTracks:playlistName];
            if (allTracks.count == 0 && ![playlistName isEqualToString:@"Музыка"]) {
                allTracks = [self getLibrarySongs];
            }
            if (allTracks.count > 0) {
                NSMutableArray<NSDictionary *> *shuffled = [allTracks mutableCopy];
                for (NSUInteger i = shuffled.count - 1; i > 0; i--) {
                    NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
                    [shuffled exchangeObjectAtIndex:i withObjectAtIndex:j];
                }
                if (trackId && [trackId integerValue] > 0) {
                    NSInteger targetId = [trackId integerValue];
                    NSUInteger foundIdx = NSNotFound;
                    for (NSUInteger i = 0; i < shuffled.count; i++) {
                        if ([shuffled[i][@"id"] integerValue] == targetId) {
                            foundIdx = i;
                            break;
                        }
                    }
                    if (foundIdx != NSNotFound && foundIdx != 0) {
                        NSDictionary *match = shuffled[foundIdx];
                        [shuffled removeObjectAtIndex:foundIdx];
                        [shuffled insertObject:match atIndex:0];
                    }
                }
                
                // Build dynamic synchronized queue playlist in Apple Music
                NSMutableString *script = [NSMutableString stringWithFormat:
                    @"tell application \"Music\"\n"
                    @"  try\n"
                    @"    set qPl to (first user playlist whose name is \"Очередь AMR\")\n"
                    @"  on error\n"
                    @"    set qPl to (make new user playlist with properties {name:\"Очередь AMR\"})\n"
                    @"  end try\n"
                    @"  delete every track of qPl\n"
                ];
                
                for (NSDictionary *t in shuffled) {
                    NSInteger tid = [t[@"id"] integerValue];
                    if (tid > 0) {
                        [script appendFormat:@"  try\n"
                                             @"    duplicate (first track of playlist \"%@\" whose database ID is %ld) to qPl\n"
                                             @"  end try\n", escapedPl, (long)tid];
                    }
                }
                
                [script appendString:@"  set shuffle enabled to false\n"];
                [script appendString:@"  play qPl\n"];
                [script appendString:@"end tell"];
                
                NSAppleScript *as = [[NSAppleScript alloc] initWithSource:script];
                NSDictionary *err = nil;
                [as executeAndReturnError:&err];
                return (err == nil);
            }
        }
        
        // Sequential Mode
        NSMutableString *script = [NSMutableString stringWithFormat:@"tell application \"Music\"\n"];
        [script appendString:@"  set shuffle enabled to false\n"];
        
        if (trackId && [trackId integerValue] > 0) {
            [script appendFormat:@"  try\n"
                                 @"    play (first track of playlist \"%@\" whose database ID is %ld)\n"
                                 @"  on error\n"
                                 @"    play playlist \"%@\"\n"
                                 @"  end try\n", escapedPl, (long)[trackId integerValue], escapedPl];
        } else if (trackIndex && [trackIndex integerValue] > 0) {
            [script appendFormat:@"  try\n"
                                 @"    play track %ld of playlist \"%@\"\n"
                                 @"  on error\n"
                                 @"    play playlist \"%@\"\n"
                                 @"  end try\n", (long)[trackIndex integerValue], escapedPl, escapedPl];
        } else {
            [script appendFormat:@"  play playlist \"%@\"\n", escapedPl];
        }
        [script appendString:@"end tell"];
        
        NSAppleScript *as = [[NSAppleScript alloc] initWithSource:script];
        NSDictionary *err = nil;
        [as executeAndReturnError:&err];
        return (err == nil);
    } @catch (NSException *e) {
        return NO;
    }
}

- (BOOL)playTrackId:(NSNumber *)trackId {
    return NO;
}

- (BOOL)playCustomQueueIndex:(NSInteger)index {
    return [self playQueueIndex:index];
}

- (BOOL)playStationUrl:(NSString *)url name:(NSString *)name {
    if (!url || url.length == 0) return NO;
    self.isRadioPlayback = YES;
    self.activeStationName = name.length > 0 ? name : @"Apple Music Radio";
    self.isCustomQueuePlayback = NO;
    self.activeCustomQueue = [NSMutableArray array];
    self.activeCustomQueueName = nil;
    self.currentOriginalPlaylistName = self.activeStationName;
    
    NSString *playUrl = url;
    if ([playUrl hasPrefix:@"https://"]) {
        playUrl = [@"music://" stringByAppendingString:[playUrl substringFromIndex:8]];
    }
    NSString *s = [NSString stringWithFormat:
        @"tell application \"Music\"\n"
        @"  open location \"%@\"\n"
        @"  play\n"
        @"end tell", playUrl];
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:s];
    [as executeAndReturnError:nil];
    return YES;
}

- (BOOL)playCloudUrl:(NSString *)url trackName:(NSString *)name artistName:(NSString *)artist {
    return [self playCloudUrl:url trackName:name artistName:artist previewUrl:nil];
}

- (BOOL)playCloudUrl:(NSString *)url trackName:(NSString *)name artistName:(NSString *)artist previewUrl:(NSString *)previewUrl {
    self.isRadioPlayback = NO;
    self.activeStationName = nil;
    
    // 1. Strict match in local library: BOTH title AND artist must match
    if (name.length > 0 && artist.length > 0) {
        NSString *escapedName = [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *escapedArtist = [artist stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *searchAppleScript = [NSString stringWithFormat:
            @"tell application \"Music\"\n"
            @"  try\n"
            @"    set foundTracks to (every track of library playlist 1 whose name is \"%@\" and artist is \"%@\")\n"
            @"    if (count of foundTracks) > 0 then\n"
            @"      play item 1 of foundTracks\n"
            @"      return \"ok\"\n"
            @"    end if\n"
            @"  end try\n"
            @"  return \"not_found\"\n"
            @"end tell", escapedName, escapedArtist];
        NSAppleScript *as = [[NSAppleScript alloc] initWithSource:searchAppleScript];
        NSAppleEventDescriptor *res = [as executeAndReturnError:nil];
        if ([[res stringValue] isEqualToString:@"ok"]) {
            return YES;
        }
    }
    
    // 2. Open full cloud track in Music.app for Lossless playback
    if (url.length > 0) {
        NSString *playUrl = url;
        if ([playUrl hasPrefix:@"https://"]) {
            playUrl = [@"music://" stringByAppendingString:[playUrl substringFromIndex:8]];
        }
        NSString *s = [NSString stringWithFormat:
            @"tell application \"Music\"\n"
            @"  open location \"%@\"\n"
            @"  play\n"
            @"end tell", playUrl];
        NSAppleScript *as = [[NSAppleScript alloc] initWithSource:s];
        [as executeAndReturnError:nil];
    }
    
    return YES;
}

- (BOOL)playQueueIndex:(NSInteger)index {
    if (!self.activeCustomQueue || index < 0 || index >= self.activeCustomQueue.count) {
        return NO;
    }
    
    self.activeCustomQueueIndex = index;
    self.isCustomQueuePlayback = YES;
    self.isRadioPlayback = NO;
    NSDictionary *track = self.activeCustomQueue[index];
    
    NSString *name = track[@"name"] ?: @"";
    NSString *artist = track[@"artist"] ?: @"";
    NSString *url = track[@"url"] ?: @"";
    id trackId = track[@"id"];
    
    self.lastWasPlayingCloud = YES;
    self.lastCloudPlayTime = [NSDate date];
    
    if (url.length == 0 && trackId && [trackId integerValue] > 0) {
        url = [NSString stringWithFormat:@"https://music.apple.com/album/song/%ld", (long)[trackId integerValue]];
    }
    
    return [self playCloudUrl:url trackName:name artistName:artist previewUrl:nil];
}

- (BOOL)enqueueTrack:(NSDictionary *)track playNext:(BOOL)playNext {
    if (!track) return NO;
    if (!self.activeCustomQueue) {
        self.activeCustomQueue = [NSMutableArray array];
        self.activeCustomQueueIndex = 0;
        self.isCustomQueuePlayback = YES;
        self.isRadioPlayback = NO;
        self.activeCustomQueueName = @"Очередь";
        [self.activeCustomQueue addObject:track];
        return [self playQueueIndex:0];
    }
    
    if (self.activeCustomQueue.count == 0) {
        [self.activeCustomQueue addObject:track];
        self.activeCustomQueueIndex = 0;
        self.isCustomQueuePlayback = YES;
        self.isRadioPlayback = NO;
        return [self playQueueIndex:0];
    }
    
    if (playNext) {
        NSInteger insertIdx = MIN(self.activeCustomQueue.count, self.activeCustomQueueIndex + 1);
        [self.activeCustomQueue insertObject:track atIndex:insertIdx];
    } else {
        [self.activeCustomQueue addObject:track];
    }
    
    return YES;
}

- (BOOL)enqueueTracks:(NSArray<NSDictionary *> *)tracks playNext:(BOOL)playNext {
    if (!tracks || tracks.count == 0) return NO;
    if (!self.activeCustomQueue || self.activeCustomQueue.count == 0) {
        return [self playCustomTracks:tracks startIndex:0 shuffle:NO queueName:@"Очередь"];
    }
    
    if (playNext) {
        NSInteger insertIdx = MIN(self.activeCustomQueue.count, self.activeCustomQueueIndex + 1);
        NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertIdx, tracks.count)];
        [self.activeCustomQueue insertObjects:tracks atIndexes:indexes];
    } else {
        [self.activeCustomQueue addObjectsFromArray:tracks];
    }
    return YES;
}

- (BOOL)removeQueueTrackAtIndex:(NSInteger)index {
    if (!self.activeCustomQueue || index < 0 || index >= self.activeCustomQueue.count) {
        return NO;
    }
    [self.activeCustomQueue removeObjectAtIndex:index];
    if (index < self.activeCustomQueueIndex) {
        self.activeCustomQueueIndex--;
    }
    return YES;
}

- (BOOL)clearUpcomingQueue {
    if (!self.activeCustomQueue || self.activeCustomQueue.count == 0) {
        return YES;
    }
    if (self.activeCustomQueueIndex + 1 < self.activeCustomQueue.count) {
        NSRange removeRange = NSMakeRange(self.activeCustomQueueIndex + 1, self.activeCustomQueue.count - (self.activeCustomQueueIndex + 1));
        [self.activeCustomQueue removeObjectsInRange:removeRange];
    }
    return YES;
}

- (void)checkAndAutoAdvanceCloudQueue {
    if (!self.isCustomQueuePlayback || !self.activeCustomQueue || self.activeCustomQueue.count == 0) {
        return;
    }
    
    MusicEPlS pState = self.musicApp.playerState;
    double pos = self.musicApp.playerPosition;
    double dur = self.musicApp.currentTrack.duration;
    
    if (dur <= 0.0 && self.activeCustomQueueIndex < self.activeCustomQueue.count) {
        dur = [self.activeCustomQueue[self.activeCustomQueueIndex][@"duration"] doubleValue];
    }
    
    if (pState == MusicEPlSPlaying) {
        self.lastWasPlayingCloud = YES;
        if (dur > 3.0 && pos > 0.0 && pos >= (dur - 0.8)) {
            // Song ended, smoothly auto-advance to next track in queue!
            self.lastWasPlayingCloud = NO;
            if (self.activeCustomQueueIndex + 1 < self.activeCustomQueue.count) {
                [self nextTrack];
            }
        }
    } else if (pState == MusicEPlSStopped && self.lastWasPlayingCloud) {
        NSTimeInterval elapsed = self.lastCloudPlayTime ? [[NSDate date] timeIntervalSinceDate:self.lastCloudPlayTime] : 10.0;
        if (elapsed > 2.5) {
            self.lastWasPlayingCloud = NO;
            if (self.activeCustomQueueIndex + 1 < self.activeCustomQueue.count) {
                [self nextTrack];
            }
        }
    }
}

- (BOOL)playCustomTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIdx shuffle:(BOOL)shuffle queueName:(NSString *)queueName {
    if (tracks.count == 0) return NO;
    
    NSString *displayName = queueName.length > 0 ? queueName : @"Очередь";
    self.currentOriginalPlaylistName = displayName;
    self.activeCustomQueueName = displayName;
    self.isCustomQueuePlayback = YES;
    self.isRadioPlayback = NO;
    
    NSMutableArray<NSDictionary *> *finalTrackList = [tracks mutableCopy];
    
    // If shuffle requested
    if (shuffle) {
        for (NSUInteger i = finalTrackList.count - 1; i > 0; i--) {
            NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
            [finalTrackList exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
        if (startIdx >= 0 && startIdx < tracks.count) {
            NSDictionary *sel = tracks[startIdx];
            NSUInteger found = [finalTrackList indexOfObject:sel];
            if (found != NSNotFound && found != 0) {
                [finalTrackList removeObjectAtIndex:found];
                [finalTrackList insertObject:sel atIndex:0];
            }
        }
    } else if (startIdx > 0 && startIdx < finalTrackList.count) {
        NSArray *before = [finalTrackList subarrayWithRange:NSMakeRange(0, startIdx)];
        NSArray *fromStart = [finalTrackList subarrayWithRange:NSMakeRange(startIdx, finalTrackList.count - startIdx)];
        NSMutableArray *reordered = [fromStart mutableCopy];
        [reordered addObjectsFromArray:before];
        finalTrackList = reordered;
    }
    
    self.activeCustomQueue = finalTrackList;
    self.activeCustomQueueIndex = 0;

    return [self playQueueIndex:0];
}

- (NSData *)getCurrentTrackArtwork {
    @try {
        SBAMTrack *currentTrack = self.musicApp.currentTrack;
        SBElementArray<MusicArtwork *> *artworks = [currentTrack artworks];
        if (artworks.count > 0) {
            MusicArtwork *art = artworks[0];
            id d = [art data];
            if ([d isKindOfClass:[NSImage class]]) {
                NSImage *img = (NSImage *)d;
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
                NSData *jpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}];
                return jpeg;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

- (NSData *)getPlaylistArtwork:(NSString *)playlistName {
    if (!playlistName || playlistName.length == 0) return nil;
    NSData *cached = [self.artworkCache objectForKey:playlistName];
    if (cached) return cached;
    
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            if ([p.name isEqualToString:playlistName]) {
                SBElementArray<SBAMTrack *> *tracks = [p tracks];
                int checked = 0;
                for (SBAMTrack *t in tracks) {
                    checked++;
                    @try {
                        NSArray<MusicArtwork *> *artworks = [t artworks];
                        if (artworks.count > 0) {
                            id d = [artworks[0] data];
                            if ([d isKindOfClass:[NSImage class]]) {
                                NSImage *img = (NSImage *)d;
                                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
                                NSData *jpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}];
                                if (jpeg) {
                                    [self.artworkCache setObject:jpeg forKey:playlistName];
                                    return jpeg;
                                }
                            }
                        }
                    } @catch (NSException *e) {}
                    if (checked >= 30) break;
                }
                break;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

- (NSDictionary *)getPersonalHomeFeed {
    if (self.cachedHomeFeed && self.homeFeedTimestamp && [[NSDate date] timeIntervalSinceDate:self.homeFeedTimestamp] < 20.0) {
        return self.cachedHomeFeed;
    }
    
    NSMutableArray<NSDictionary *> *allTracks = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *playlistsList = [NSMutableArray array];
    
    NSMutableCharacterSet *queryValCharset = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [queryValCharset removeCharactersInString:@"&+=?#"];
    
    @try {
        SBElementArray<MusicPlaylist *> *playlists = [self.musicApp playlists];
        for (MusicPlaylist *p in playlists) {
            NSString *pName = p.name;
            if ([pName isEqualToString:@"Музыка"] || [pName isEqualToString:@"Music"] || [pName isEqualToString:@"Библиотека"]) {
                SBElementArray<SBAMTrack *> *tracks = [p tracks];
                for (SBAMTrack *t in tracks) {
                    @try {
                        NSString *name = t.name ?: @"";
                        NSString *artist = t.artist ?: @"";
                        NSString *album = t.album ?: @"";
                        double dur = t.duration;
                        
                        if (isValidLibraryTrack(name, artist, dur)) {
                            NSInteger count = t.playedCount;
                            NSDate *pDate = t.playedDate;
                            NSDate *aDate = t.dateAdded;
                            NSInteger dbId = t.databaseID;
                            
                            [allTracks addObject:@{
                                @"id": @(dbId),
                                @"name": name,
                                @"artist": artist,
                                @"album": album,
                                @"played_count": @(count),
                                @"played_date": pDate ? @([pDate timeIntervalSince1970]) : @(0),
                                @"date_added": aDate ? @([aDate timeIntervalSince1970]) : @(0),
                                @"artwork": [NSString stringWithFormat:@"/api/artwork/track?id=%ld", (long)dbId],
                                @"is_local": @YES
                            }];
                        }
                    } @catch (NSException *e) {}
                }
            } else if (![pName isEqualToString:@"Медиатека"] && ![pName isEqualToString:@"Музыка"] && ![pName isEqualToString:@"Music"]) {
                NSInteger count = [p tracks].count;
                if (count > 0) {
                    NSString *enc = [pName stringByAddingPercentEncodingWithAllowedCharacters:queryValCharset];
                    [playlistsList addObject:@{
                        @"name": pName,
                        @"track_count": @(count),
                        @"artwork": [NSString stringWithFormat:@"/api/artwork/playlist?name=%@", enc ?: @""],
                        @"is_playlist": @YES
                    }];
                }
            }
        }
    } @catch (NSException *e) {}
    
    // 1. Top Picks (only tracks that have played_count > 0)
    NSMutableArray *topCandidates = [NSMutableArray array];
    for (NSDictionary *t in allTracks) {
        if ([t[@"played_count"] integerValue] > 0) {
            [topCandidates addObject:t];
        }
    }
    NSArray *topPicks = [topCandidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"played_count"] compare:a[@"played_count"]];
    }];
    if (topPicks.count > 15) topPicks = [topPicks subarrayWithRange:NSMakeRange(0, 15)];
    
    // 2. Recently Played (only tracks with played_date > 0)
    NSMutableArray *recentCandidates = [NSMutableArray array];
    for (NSDictionary *t in allTracks) {
        if ([t[@"played_date"] doubleValue] > 0) {
            [recentCandidates addObject:t];
        }
    }
    NSArray *recentlyPlayed = [recentCandidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"played_date"] compare:a[@"played_date"]];
    }];
    if (recentlyPlayed.count > 15) recentlyPlayed = [recentlyPlayed subarrayWithRange:NSMakeRange(0, 15)];
    
    // 3. Recently Added (sorted by date_added)
    NSArray *recentlyAdded = [allTracks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"date_added"] compare:a[@"date_added"]];
    }];
    if (recentlyAdded.count > 15) recentlyAdded = [recentlyAdded subarrayWithRange:NSMakeRange(0, 15)];
    
    NSDictionary *feed = @{
        @"top_picks": topPicks,
        @"recently_played": recentlyPlayed,
        @"playlists_for_you": playlistsList,
        @"new_releases": recentlyAdded
    };
    
    self.cachedHomeFeed = feed;
    self.homeFeedTimestamp = [NSDate date];
    return feed;
}

- (NSData *)getTrackArtwork:(NSInteger)trackId {
    if (trackId <= 0) return nil;
    NSString *cacheKey = [NSString stringWithFormat:@"track_%ld", (long)trackId];
    NSData *cached = [self.artworkCache objectForKey:cacheKey];
    if (cached) return cached;
    
    @try {
        // 1. Fast path: Check currently active playlist first
        MusicPlaylist *curPl = self.musicApp.currentPlaylist;
        if (curPl) {
            for (SBAMTrack *t in [curPl tracks]) {
                if (t.databaseID == trackId) {
                    NSArray *artworks = [t artworks];
                    if (artworks.count > 0) {
                        id d = [artworks[0] data];
                        if ([d isKindOfClass:[NSImage class]]) {
                            NSImage *img = (NSImage *)d;
                            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
                            NSData *jpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}];
                            if (jpeg) {
                                [self.artworkCache setObject:jpeg forKey:cacheKey];
                                return jpeg;
                            }
                        }
                    }
                    break;
                }
            }
        }
        
        // 2. Search across all playlists
        for (MusicPlaylist *p in [self.musicApp playlists]) {
            if (curPl && [p.name isEqualToString:curPl.name]) continue;
            for (SBAMTrack *t in [p tracks]) {
                if (t.databaseID == trackId) {
                    NSArray *artworks = [t artworks];
                    if (artworks.count > 0) {
                        id d = [artworks[0] data];
                        if ([d isKindOfClass:[NSImage class]]) {
                            NSImage *img = (NSImage *)d;
                            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
                            NSData *jpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{}];
                            if (jpeg) {
                                [self.artworkCache setObject:jpeg forKey:cacheKey];
                                return jpeg;
                            }
                        }
                    }
                    break;
                }
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

- (NSDictionary *)getPlaybackQueue {
    SBAMTrack *curTrack = self.musicApp.currentTrack;
    MusicPlaylist *curPl = self.musicApp.currentPlaylist;
    
    NSString *curName = curTrack.name ?: @"";
    NSString *curArtist = curTrack.artist ?: @"";
    
    if (self.isCustomQueuePlayback && self.activeCustomQueue && self.activeCustomQueue.count > 0) {
        if (curName.length > 0) {
            for (NSInteger i = 0; i < self.activeCustomQueue.count; i++) {
                NSDictionary *t = self.activeCustomQueue[i];
                NSString *tName = t[@"name"] ?: @"";
                NSString *tArtist = t[@"artist"] ?: @"";
                if ([tName localizedCaseInsensitiveCompare:curName] == NSOrderedSame) {
                    if (tArtist.length == 0 || curArtist.length == 0 || [tArtist localizedCaseInsensitiveCompare:curArtist] == NSOrderedSame) {
                        self.activeCustomQueueIndex = i;
                        break;
                    }
                }
            }
        }
        
        NSMutableArray *formattedTracks = [NSMutableArray array];
        for (NSInteger i = 0; i < self.activeCustomQueue.count; i++) {
            NSDictionary *t = self.activeCustomQueue[i];
            BOOL isCurrent = (i == self.activeCustomQueueIndex);
            
            NSString *art = t[@"artwork"] ?: @"";
            if (art.length == 0 && t[@"id"]) {
                art = [NSString stringWithFormat:@"/api/artwork/track?id=%@", t[@"id"]];
            }
            
            [formattedTracks addObject:@{
                @"index": @(i + 1),
                @"id": t[@"id"] ?: @(i + 1),
                @"name": t[@"name"] ?: @"",
                @"artist": t[@"artist"] ?: @"",
                @"album": t[@"album"] ?: @"",
                @"duration": t[@"duration"] ?: @(0),
                @"is_current": @(isCurrent),
                @"artwork": art,
                @"url": t[@"url"] ?: @""
            }];
        }
        
        NSArray *upcoming = @[];
        if (self.activeCustomQueueIndex + 1 < formattedTracks.count) {
            upcoming = [formattedTracks subarrayWithRange:NSMakeRange(self.activeCustomQueueIndex + 1, formattedTracks.count - (self.activeCustomQueueIndex + 1))];
        }
        
        return @{
            @"playlist": self.activeCustomQueueName ?: @"Очередь",
            @"current_index": @(self.activeCustomQueueIndex),
            @"total_tracks": @(formattedTracks.count),
            @"shuffle": @(self.musicApp.shuffleEnabled),
            @"upcoming_tracks": upcoming,
            @"tracks": formattedTracks
        };
    }
    
    NSString *plName = curPl.name;
    if (!plName || plName.length == 0) {
        plName = @"Музыка";
    }
    
    BOOL isQueuePlaylist = [plName isEqualToString:@"Очередь AMR"];
    BOOL isShuffle = isQueuePlaylist || self.musicApp.shuffleEnabled;
    NSString *displayPlaylistName = isQueuePlaylist ? (self.currentOriginalPlaylistName ?: @"Перемешанный плейлист") : plName;
    
    NSMutableArray<NSDictionary *> *tracks = [NSMutableArray array];
    NSInteger curIdx = -1;
    NSInteger validIdx = 1;
    NSInteger curDbId = curTrack.databaseID;
    
    @try {
        NSArray<SBAMTrack *> *rawTracks = [curPl tracks];
        if (rawTracks.count == 0 && ![plName isEqualToString:@"Музыка"] && !isQueuePlaylist) {
            for (MusicPlaylist *p in [self.musicApp playlists]) {
                if ([p.name isEqualToString:@"Музыка"] || [p.name isEqualToString:@"Music"]) {
                    rawTracks = [p tracks];
                    displayPlaylistName = p.name;
                    break;
                }
            }
        }
        
        for (SBAMTrack *t in rawTracks) {
            NSString *name = t.name ?: @"";
            NSString *artist = t.artist ?: @"";
            double dur = t.duration;
            
            if (isValidLibraryTrack(name, artist, dur)) {
                BOOL isCurrent = (t.databaseID == curDbId) || ([name isEqualToString:curTrack.name] && [artist isEqualToString:curTrack.artist]);
                if (isCurrent && curIdx == -1) {
                    curIdx = tracks.count;
                }
                [tracks addObject:@{
                    @"index": @(validIdx++),
                    @"id": @(t.databaseID),
                    @"name": name,
                    @"artist": artist,
                    @"album": t.album ?: @"",
                    @"duration": @(dur),
                    @"is_current": @(isCurrent),
                    @"artwork": [NSString stringWithFormat:@"/api/artwork/track?id=%ld", (long)t.databaseID]
                }];
            }
        }
    } @catch (NSException *e) {}
    
    NSArray *upcoming = @[];
    if (curIdx != -1 && curIdx + 1 < tracks.count) {
        upcoming = [tracks subarrayWithRange:NSMakeRange(curIdx + 1, tracks.count - (curIdx + 1))];
    } else if (curIdx == -1 && tracks.count > 0) {
        upcoming = tracks;
    }
    
    return @{
        @"playlist": displayPlaylistName,
        @"current_index": @(curIdx),
        @"total_tracks": @(tracks.count),
        @"shuffle": @(isShuffle),
        @"upcoming_tracks": upcoming,
        @"tracks": tracks
    };
}

@end
