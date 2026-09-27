//
//  AppleMusicBridge.h
//  AppleMusicRemote
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppleMusicBridge : NSObject

+ (instancetype)sharedBridge;

- (NSDictionary *)getPlayerStatus;
- (BOOL)play;
- (BOOL)pause;
- (BOOL)playPause;
- (BOOL)nextTrack;
- (BOOL)previousTrack;
- (BOOL)seekToPosition:(double)position;
- (BOOL)setVolume:(NSInteger)volume;
- (BOOL)setShuffle:(BOOL)enabled;
- (BOOL)setRepeatMode:(NSString *)mode;
- (BOOL)toggleCurrentTrackFavorite;

- (NSArray<NSDictionary *> *)getPlaylists;
- (NSArray<NSDictionary *> *)getLibraryArtists;
- (NSArray<NSDictionary *> *)getLibrarySongs;
- (NSArray<NSDictionary *> *)getPlaylistTracks:(NSString *)playlistName;

- (BOOL)playPlaylist:(NSString *)playlistName trackId:(nullable NSNumber *)trackId trackIndex:(nullable NSNumber *)trackIndex;
- (BOOL)playPlaylist:(NSString *)playlistName trackId:(nullable NSNumber *)trackId trackIndex:(nullable NSNumber *)trackIndex shuffle:(BOOL)shuffle;
- (BOOL)playTrackId:(NSNumber *)trackId;
- (BOOL)playCloudUrl:(NSString *)url trackName:(nullable NSString *)name artistName:(nullable NSString *)artist;
- (BOOL)playCloudUrl:(NSString *)url trackName:(nullable NSString *)name artistName:(nullable NSString *)artist previewUrl:(nullable NSString *)previewUrl;
- (BOOL)playCustomTracks:(NSArray<NSDictionary *> *)tracks startIndex:(NSInteger)startIdx shuffle:(BOOL)shuffle queueName:(nullable NSString *)queueName;
- (BOOL)playCustomQueueIndex:(NSInteger)index;
- (BOOL)playStationUrl:(NSString *)url name:(nullable NSString *)name;
- (BOOL)enqueueTrack:(NSDictionary *)track playNext:(BOOL)playNext;
- (BOOL)enqueueTracks:(NSArray<NSDictionary *> *)tracks playNext:(BOOL)playNext;
- (BOOL)removeQueueTrackAtIndex:(NSInteger)index;
- (BOOL)clearUpcomingQueue;
- (BOOL)playQueueIndex:(NSInteger)index;
- (void)checkAndAutoAdvanceCloudQueue;

- (NSDictionary *)getPersonalHomeFeed;
- (NSDictionary *)getPlaybackQueue;
- (nullable NSData *)getCurrentTrackArtwork;
- (nullable NSData *)getPlaylistArtwork:(NSString *)playlistName;
- (nullable NSData *)getTrackArtwork:(NSInteger)trackId;

@property (nonatomic, assign, readonly) BOOL isCustomQueuePlayback;
@property (nonatomic, strong, nullable, readonly) NSString *activeCustomQueueName;
@property (nonatomic, assign, readonly) BOOL isRadioPlayback;
@property (nonatomic, strong, nullable, readonly) NSString *activeStationName;

@end

NS_ASSUME_NONNULL_END
