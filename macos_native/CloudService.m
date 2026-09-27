//
//  CloudService.m
//  AppleMusicRemote
//

#import "CloudService.h"

@implementation CloudService

+ (instancetype)sharedService {
    static CloudService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CloudService alloc] init];
    });
    return instance;
}

- (NSString *)upgradeArtworkUrl:(NSString *)url {
    if (!url || url.length == 0) return @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/\\d+x\\d+bb\\.(jpg|png|webp)" options:0 error:nil];
    return [regex stringByReplacingMatchesInString:url options:0 range:NSMakeRange(0, url.length) withTemplate:@"/600x600bb.$1"];
}

- (void)getExploreFeedWithCountry:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion {
    NSString *c = (country && country.length > 0) ? [country lowercaseString] : @"ru";
    
    dispatch_group_t group = dispatch_group_create();
    __block NSArray *topSongs = @[];
    __block NSArray *topAlbums = @[];
    
    // 1. Top Songs Chart from iTunes RSS
    dispatch_group_enter(group);
    NSString *songsUrlStr = [NSString stringWithFormat:@"https://itunes.apple.com/%@/rss/topsongs/limit=50/json", c];
    NSURL *songsUrl = [NSURL URLWithString:songsUrlStr];
    NSMutableURLRequest *req1 = [NSMutableURLRequest requestWithURL:songsUrl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:8.0];
    [req1 setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" forHTTPHeaderField:@"User-Agent"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req1 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"feed"][@"entry"]) {
                NSArray *entries = json[@"feed"][@"entry"];
                NSMutableArray *parsed = [NSMutableArray array];
                NSInteger rank = 1;
                for (NSDictionary *e in entries) {
                    NSString *name = e[@"im:name"][@"label"] ?: @"";
                    NSString *artist = e[@"im:artist"][@"label"] ?: @"";
                    
                    // Artwork
                    NSString *artUrl = @"";
                    NSArray *images = e[@"im:image"];
                    if ([images isKindOfClass:[NSArray class]] && images.count > 0) {
                        NSDictionary *lastImg = images.lastObject;
                        artUrl = [self upgradeArtworkUrl:lastImg[@"label"] ?: @""];
                    }
                    
                    // URL
                    NSString *urlStr = @"";
                    id linkObj = e[@"link"];
                    if ([linkObj isKindOfClass:[NSArray class]] && [linkObj count] > 0) {
                        urlStr = linkObj[0][@"attributes"][@"href"] ?: @"";
                    } else if ([linkObj isKindOfClass:[NSDictionary class]]) {
                        urlStr = linkObj[@"attributes"][@"href"] ?: @"";
                    }
                    
                    // Preview URL
                    NSString *previewUrl = @"";
                    if ([linkObj isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *l in linkObj) {
                            if ([l[@"attributes"][@"rel"] isEqualToString:@"enclosure"] || [l[@"attributes"][@"type"] containsString:@"audio"]) {
                                previewUrl = l[@"attributes"][@"href"] ?: @"";
                                break;
                            }
                        }
                    }
                    
                    NSString *idStr = e[@"id"][@"attributes"][@"im:id"] ?: @"";
                    
                    [parsed addObject:@{
                        @"rank": @(rank++),
                        @"id": idStr,
                        @"name": name,
                        @"artist": artist,
                        @"artwork": artUrl,
                        @"url": urlStr,
                        @"preview_url": previewUrl
                    }];
                }
                topSongs = parsed;
            }
        }
        dispatch_group_leave(group);
    }] resume];
    
    // 2. Top Albums Chart from iTunes RSS
    dispatch_group_enter(group);
    NSString *albumsUrlStr = [NSString stringWithFormat:@"https://itunes.apple.com/%@/rss/topalbums/limit=50/json", c];
    NSURL *albumsUrl = [NSURL URLWithString:albumsUrlStr];
    NSMutableURLRequest *req2 = [NSMutableURLRequest requestWithURL:albumsUrl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:8.0];
    [req2 setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" forHTTPHeaderField:@"User-Agent"];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req2 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"feed"][@"entry"]) {
                NSArray *entries = json[@"feed"][@"entry"];
                NSMutableArray *parsed = [NSMutableArray array];
                NSInteger rank = 1;
                for (NSDictionary *e in entries) {
                    NSString *name = e[@"im:name"][@"label"] ?: @"";
                    NSString *artist = e[@"im:artist"][@"label"] ?: @"";
                    
                    // Artwork
                    NSString *artUrl = @"";
                    NSArray *images = e[@"im:image"];
                    if ([images isKindOfClass:[NSArray class]] && images.count > 0) {
                        NSDictionary *lastImg = images.lastObject;
                        artUrl = [self upgradeArtworkUrl:lastImg[@"label"] ?: @""];
                    }
                    
                    // URL
                    NSString *urlStr = @"";
                    id linkObj = e[@"link"];
                    if ([linkObj isKindOfClass:[NSArray class]] && [linkObj count] > 0) {
                        urlStr = linkObj[0][@"attributes"][@"href"] ?: @"";
                    } else if ([linkObj isKindOfClass:[NSDictionary class]]) {
                        urlStr = linkObj[@"attributes"][@"href"] ?: @"";
                    }
                    
                    NSString *idStr = e[@"id"][@"attributes"][@"im:id"] ?: @"";
                    
                    [parsed addObject:@{
                        @"rank": @(rank++),
                        @"id": idStr,
                        @"name": name,
                        @"artist": artist,
                        @"artwork": artUrl,
                        @"url": urlStr
                    }];
                }
                topAlbums = parsed;
            }
        }
        dispatch_group_leave(group);
    }] resume];
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray *hotPicks = topSongs.count > 10 ? [topSongs subarrayWithRange:NSMakeRange(0, 10)] : topSongs;
        NSArray *stations = [self getCuratedStationsWithCountry:c];
        
        NSArray *genres = @[
            @{@"name": @"🔥 Поп-музыка", @"query": @"Pop Hits", @"color": @"linear-gradient(135deg, #fa2d48, #ff6b8b)"},
            @{@"name": @"🎸 Рок & Альтернатива", @"query": @"Rock Classics", @"color": @"linear-gradient(135deg, #e65100, #ff9800)"},
            @{@"name": @"🎤 Хип-хоп & Рэп", @"query": @"Hip Hop", @"color": @"linear-gradient(135deg, #4a148c, #7b1fa2)"},
            @{@"name": @"⚡ Электроника & Dance", @"query": @"Dance Electronic", @"color": @"linear-gradient(135deg, #00695c, #00bfa5)"},
            @{@"name": @"☕ Chill & Lo-Fi", @"query": @"Chill Beats", @"color": @"linear-gradient(135deg, #1565c0, #42a5f5)"},
            @{@"name": @"🎻 Неоклассика", @"query": @"Neoclassical", @"color": @"linear-gradient(135deg, #37474f, #78909c)"},
            @{@"name": @"🎬 Саундтреки", @"query": @"Soundtrack Movie", @"color": @"linear-gradient(135deg, #880e4f, #d81b60)"}
        ];
        
        NSDictionary *feed = @{
            @"country": c,
            @"stations": stations,
            @"hot_tracks": hotPicks,
            @"top_songs": topSongs,
            @"top_albums": topAlbums,
            @"genres": genres
        };
        completion(feed);
    });
}

- (NSArray<NSDictionary *> *)getCuratedStationsWithCountry:(NSString *)country {
    NSString *c = (country && country.length > 0) ? [country lowercaseString] : @"ru";
    BOOL isRu = [c isEqualToString:@"ru"] || [c isEqualToString:@"kz"] || [c isEqualToString:@"by"] || [c isEqualToString:@"ua"];
    
    return @[
        @{
            @"id": @"station_personal",
            @"name": isRu ? @"Моя станция" : @"My Station",
            @"subtitle": isRu ? @"Любимые треки и персональные рекомендации" : @"Favorite tracks & personal recommendations",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/44/1a/0b/441a0b59-ea4e-f29e-efef-ec8a3d758fa4/mza_10334839818817454157.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/my-station/ra.u-personal",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #fa233b, #fb5c74)"
        },
        @{
            @"id": @"station_discovery",
            @"name": isRu ? @"Станция открытий" : @"Discovery Station",
            @"subtitle": isRu ? @"Новая музыка на основе ваших вкусов" : @"New music based on what you love",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features116/v4/d1/2f/5e/d12f5e08-9df2-5d46-4c3e-cb52c4be3e6e/U1RBVElPTl9ESVNDT1ZFUllfUlUucG5n.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/discovery-station/ra.u-discovery",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #7928ca, #ff0080)"
        },
        @{
            @"id": @"station_am1",
            @"name": @"Apple Music 1",
            @"subtitle": isRu ? @"Главные мировые релизы в прямом эфире" : @"The new music that matters, live 24/7",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features124/v4/85/65/59/856559cb-1296-6e46-13a5-171b3e85e492/mza_17208465492160913075.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/apple-music-1/ra.985484166",
            @"is_live": @YES,
            @"color": @"linear-gradient(135deg, #1c1c1e, #3a3a3c)"
        },
        @{
            @"id": @"station_hits",
            @"name": @"Apple Music Hits",
            @"subtitle": isRu ? @"Культовые хиты 80-х, 90-х и 2000-х" : @"The songs you know and love",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features114/v4/89/a3/95/89a3952f-17f1-7788-cb94-825501869e80/mza_10793739775369651590.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/apple-music-hits/ra.1528646969",
            @"is_live": @YES,
            @"color": @"linear-gradient(135deg, #ff0844, #ffb199)"
        },
        @{
            @"id": @"station_country",
            @"name": @"Apple Music Country",
            @"subtitle": isRu ? @"Современное и классическое кантри" : @"Where country music lives",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features114/v4/10/a5/d8/10a5d898-1ff0-f2a8-0fec-1c39aa2cb2d8/mza_1804791557997974343.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/apple-music-country/ra.1528647035",
            @"is_live": @YES,
            @"color": @"linear-gradient(135deg, #f7971e, #ffd200)"
        },
        @{
            @"id": @"station_chill",
            @"name": isRu ? @"Chill & Lo-Fi" : @"Chill Station",
            @"subtitle": isRu ? @"Спокойный ритм и фоновые биты" : @"Laid-back sounds and mellow beats",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/55/38/c1/5538c11e-25ef-f5ba-77b3-6c708fa8d132/U0ctTVMtRy1DaGlsbC1BZHZlcnQtMDExMjIwLmpwZw.jpg/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/chill/ra.1461158652",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #00b4db, #0083b0)"
        },
        @{
            @"id": @"station_pop",
            @"name": isRu ? @"Поп-хиты Радио" : @"Today's Hits Radio",
            @"subtitle": isRu ? @"Самые популярные поп-треки мира" : @"The biggest pop anthems right now",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/44/1a/0b/441a0b59-ea4e-f29e-efef-ec8a3d758fa4/mza_10334839818817454157.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/pop-hits/ra.1461158651",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #fa2d48, #ff6b8b)"
        },
        @{
            @"id": @"station_rock",
            @"name": isRu ? @"Рок & Альтернатива" : @"Rock Classics Radio",
            @"subtitle": isRu ? @"Культовые рок-гимны и гитарные соло" : @"Greatest guitar anthems & classic rock",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features124/v4/bf/25/e9/bf25e982-f542-a764-7e8e-670564619717/mza_1043905470513901488.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/rock/ra.1461158650",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #e65100, #ff9800)"
        },
        @{
            @"id": @"station_hiphop",
            @"name": isRu ? @"Хип-Хоп & Рэп" : @"Hip-Hop & R&B",
            @"subtitle": isRu ? @"Плотные биты и свежие релизы" : @"Heavy beats and groundbreaking rap",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/6c/fb/83/6cfb8398-3162-87ad-d022-ee054d5bce1a/mza_16391444143003504868.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/hip-hop/ra.1461158649",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #4a148c, #7b1fa2)"
        },
        @{
            @"id": @"station_electronic",
            @"name": isRu ? @"Электроника & Dance" : @"Dance & Electronic",
            @"subtitle": isRu ? @"Клубный драйв и танцевальная энергия" : @"Non-stop club bangers & festival anthems",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features115/v4/71/34/46/71344696-6811-9a74-9b98-3cead081c7e9/mza_13402778007557161864.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/dance/ra.1461158648",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #00695c, #00bfa5)"
        },
        @{
            @"id": @"station_deephouse",
            @"name": @"Deep House & Melodic",
            @"subtitle": isRu ? @"Глубокое электронное звучание" : @"Deep melodic house & hypnotic rhythms",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/58/e7/08/58e70817-21a5-3a05-3ea2-9721666f3661/mza_11674488349272305574.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/deep-house/ra.1461158647",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #880e4f, #d81b60)"
        },
        @{
            @"id": @"station_jazz",
            @"name": isRu ? @"Джаз & Блюз" : @"Jazz & Blues",
            @"subtitle": isRu ? @"Безупречная классика джаза" : @"Timeless jazz standards & soothing brass",
            @"artwork": @"https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/64/73/b3/6473b320-1a13-43ef-1e0e-436ad18c3937/mza_17208465492160913075.png/600x600bb.jpg",
            @"url": @"https://music.apple.com/station/jazz/ra.1461158646",
            @"is_live": @NO,
            @"color": @"linear-gradient(135deg, #37474f, #78909c)"
        }
    ];
}

- (void)searchWithQuery:(NSString *)query country:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion {
    if (!query || query.length == 0) {
        completion(@{@"artists": @[], @"songs": @[], @"albums": @[], @"all": @[]});
        return;
    }
    
    NSString *c = (country && country.length > 0) ? [country lowercaseString] : @"ru";
    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    dispatch_group_t group = dispatch_group_create();
    __block NSMutableArray *artists = [NSMutableArray array];
    __block NSMutableArray *songs = [NSMutableArray array];
    __block NSMutableArray *albums = [NSMutableArray array];
    
    // 1. Search Artists
    dispatch_group_enter(group);
    NSString *uArtist = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=musicArtist&country=%@&limit=8", encoded, c];
    NSURLRequest *reqA = [NSURLRequest requestWithURL:[NSURL URLWithString:uArtist] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:6.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:reqA completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"results"]) {
                for (NSDictionary *it in json[@"results"]) {
                    NSString *name = it[@"artistName"] ?: @"";
                    NSString *genre = it[@"primaryGenreName"] ?: @"";
                    NSString *url = it[@"artistLinkUrl"] ?: @"";
                    NSString *aid = [NSString stringWithFormat:@"%@", it[@"artistId"] ?: @""];
                    [artists addObject:@{
                        @"type": @"artist",
                        @"id": aid,
                        @"name": name,
                        @"genre": genre,
                        @"url": url
                    }];
                }
            }
        }
        dispatch_group_leave(group);
    }] resume];
    
    // 2. Search Songs
    dispatch_group_enter(group);
    NSString *uSongs = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=song&country=%@&limit=25", encoded, c];
    NSURLRequest *reqS = [NSURLRequest requestWithURL:[NSURL URLWithString:uSongs] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:6.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:reqS completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"results"]) {
                for (NSDictionary *it in json[@"results"]) {
                    NSString *name = it[@"trackName"] ?: @"";
                    NSString *artist = it[@"artistName"] ?: @"";
                    NSString *album = it[@"collectionName"] ?: @"";
                    NSString *url = it[@"trackViewUrl"] ?: @"";
                    NSString *art = [self upgradeArtworkUrl:it[@"artworkUrl100"] ?: @""];
                    double durMs = [it[@"trackTimeMillis"] doubleValue];
                    NSString *tid = [NSString stringWithFormat:@"%@", it[@"trackId"] ?: @""];
                    NSString *preview = it[@"previewUrl"] ?: @"";
                    [songs addObject:@{
                        @"type": @"song",
                        @"id": tid,
                        @"name": name,
                        @"artist": artist,
                        @"album": album,
                        @"duration": @(durMs / 1000.0),
                        @"artwork": art,
                        @"url": url,
                        @"preview_url": preview
                    }];
                }
            }
        }
        dispatch_group_leave(group);
    }] resume];
    
    // 3. Search Albums
    dispatch_group_enter(group);
    NSString *uAlbums = [NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=album&country=%@&limit=12", encoded, c];
    NSURLRequest *reqAl = [NSURLRequest requestWithURL:[NSURL URLWithString:uAlbums] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:6.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:reqAl completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"results"]) {
                for (NSDictionary *it in json[@"results"]) {
                    NSString *name = it[@"collectionName"] ?: @"";
                    NSString *artist = it[@"artistName"] ?: @"";
                    NSString *url = it[@"collectionViewUrl"] ?: @"";
                    NSString *art = [self upgradeArtworkUrl:it[@"artworkUrl100"] ?: @""];
                    NSString *relDate = it[@"releaseDate"] ?: @"";
                    NSInteger tCount = [it[@"trackCount"] integerValue];
                    NSString *aid = [NSString stringWithFormat:@"%@", it[@"collectionId"] ?: @""];
                    [albums addObject:@{
                        @"type": @"album",
                        @"id": aid,
                        @"name": name,
                        @"artist": artist,
                        @"artwork": art,
                        @"release_date": relDate,
                        @"track_count": @(tCount),
                        @"url": url
                    }];
                }
            }
        }
        dispatch_group_leave(group);
    }] resume];
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSMutableArray *all = [NSMutableArray array];
        [all addObjectsFromArray:songs];
        [all addObjectsFromArray:albums];
        
        completion(@{
            @"artists": artists,
            @"songs": songs,
            @"albums": albums,
            @"all": all
        });
    });
}

- (void)getAlbumDetails:(NSString *)albumId country:(NSString *)country completion:(void(^)(NSDictionary * _Nullable result))completion {
    if (!albumId || albumId.length == 0) {
        completion(nil);
        return;
    }
    
    NSString *c = (country && country.length > 0) ? [country lowercaseString] : @"ru";
    NSString *uStr = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?id=%@&entity=song&country=%@", albumId, c];
    NSURL *url = [NSURL URLWithString:uStr];
    if (!url) {
        completion(nil);
        return;
    }
    
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:6.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]] || !json[@"results"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        
        NSArray *results = json[@"results"];
        if (results.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }
        
        NSDictionary *albumMeta = results[0];
        NSString *aName = albumMeta[@"collectionName"] ?: @"";
        NSString *aArtist = albumMeta[@"artistName"] ?: @"";
        NSString *aArt = [self upgradeArtworkUrl:albumMeta[@"artworkUrl100"] ?: @""];
        NSString *relDate = albumMeta[@"releaseDate"] ?: @"";
        NSString *genre = albumMeta[@"primaryGenreName"] ?: @"";
        NSString *aUrl = albumMeta[@"collectionViewUrl"] ?: @"";
        NSInteger tCount = [albumMeta[@"trackCount"] integerValue];
        
        NSMutableArray *tracks = [NSMutableArray array];
        for (NSUInteger i = 1; i < results.count; i++) {
            NSDictionary *it = results[i];
            if ([it[@"wrapperType"] isEqualToString:@"track"]) {
                NSString *tName = it[@"trackName"] ?: @"";
                NSString *tArtist = it[@"artistName"] ?: aArtist;
                NSString *tUrl = it[@"trackViewUrl"] ?: @"";
                NSString *tArt = [self upgradeArtworkUrl:it[@"artworkUrl100"] ?: aArt];
                double durMs = [it[@"trackTimeMillis"] doubleValue];
                NSInteger tNum = [it[@"trackNumber"] integerValue];
                NSString *tid = [NSString stringWithFormat:@"%@", it[@"trackId"] ?: @""];
                NSString *preview = it[@"previewUrl"] ?: @"";
                
                [tracks addObject:@{
                    @"index": @(tNum > 0 ? tNum : tracks.count + 1),
                    @"id": tid,
                    @"name": tName,
                    @"artist": tArtist,
                    @"album": aName,
                    @"duration": @(durMs / 1000.0),
                    @"artwork": tArt,
                    @"url": tUrl,
                    @"preview_url": preview
                }];
            }
        }
        
        NSDictionary *dict = @{
            @"id": albumId,
            @"name": aName,
            @"artist": aArtist,
            @"artwork": aArt,
            @"release_date": relDate,
            @"genre": genre,
            @"track_count": @(tCount > 0 ? tCount : tracks.count),
            @"url": aUrl,
            @"tracks": tracks
        };
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(dict);
        });
    }] resume];
}

@end
