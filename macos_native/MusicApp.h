#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>

@class MusicApplication, SBAMTrack, MusicPlaylist, MusicArtwork;

// =========================================================================
// MusicArtwork
// =========================================================================
@interface MusicArtwork : SBObject
@property (copy, readonly) NSImage *data;
@property (copy, readonly) NSData *rawData;
@end

// =========================================================================
// SBAMTrack
// =========================================================================
@interface SBAMTrack : SBObject
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *artist;
@property (copy, readonly) NSString *album;
@property (readonly) double duration;
@property (readonly) NSInteger databaseID;
@property (copy, readonly) NSString *persistentID;
@property (readonly) NSInteger playedCount;
@property (copy, readonly) NSDate *playedDate;
@property (copy, readonly) NSDate *dateAdded;
@property BOOL favorited;
@property BOOL loved;

- (SBElementArray<MusicArtwork *> *)artworks;
- (void) playOnce:(BOOL)once;
@end

// =========================================================================
// MusicPlaylist
// =========================================================================
@interface MusicPlaylist : SBObject
@property (copy, readonly) NSString *name;
- (SBElementArray<SBAMTrack *> *)tracks;
- (void) playOnce:(BOOL)once;
@end

// =========================================================================
// MusicApplication
// =========================================================================
typedef NS_ENUM(NSInteger, MusicEPlS) {
    MusicEPlSStopped = 'kPSS',
    MusicEPlSPlaying = 'kPSP',
    MusicEPlSPaused = 'kPSp',
    MusicEPlSFastForwarding = 'kPSF',
    MusicEPlSRewinding = 'kPSR'
};

typedef NS_ENUM(NSInteger, MusicERpt) {
    MusicERptOff = 'kRPO',
    MusicERptOne = 'kRP1',
    MusicERptAll = 'kRPA'
};

@interface MusicApplication : SBApplication
@property (readonly) MusicEPlS playerState;
@property double playerPosition;
@property NSInteger soundVolume;
@property BOOL shuffleEnabled;
@property MusicERpt songRepeat;

@property (copy, readonly) SBAMTrack *currentTrack;
@property (copy, readonly) MusicPlaylist *currentPlaylist;

- (SBElementArray<MusicPlaylist *> *)playlists;
- (SBElementArray<SBAMTrack *> *)tracks;

- (void) playpause;
- (void) playOnce:(BOOL)once;
- (void) pause;
- (void) nextTrack;
- (void) previousTrack;

@end
