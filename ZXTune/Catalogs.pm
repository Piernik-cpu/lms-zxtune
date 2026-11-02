package Plugins::ZXTune::Catalogs;

use strict;
use warnings;

use File::Spec;
use File::Basename qw(basename dirname);
use URI::Escape qw(uri_escape uri_unescape);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Networking::SimpleAsyncHTTP;

use Plugins::ZXTune::Metadata;
use Plugins::ZXTune::ProtocolHandler;

my $log         = logger('plugin.zxtune');
my $prefs       = preferences('plugin.zxtune');
my $serverPrefs = preferences('server');

use constant ICON_DEFAULT => 'plugins/ZXTune/html/images/icon.png';

# In-memory cache for frequently accessed XML/HTML lists (with TTL)
my %HTTP_CACHE;
use constant CACHE_TTL => 1800; # 30 minutes

# 31 JoshW console/computer sub-catalogues from VfsRootJoshw.java & vfs.xml
my @JOSHW_CATALOGS = (
    [ 'nsf',     'Nintendo Entertainment System (NSF/NSFE)' ],
    [ 'spc',     'Super Nintendo / SNES (SPC/RSN)' ],
    [ 'gbs',     'Game Boy / Game Boy Color (GBS)' ],
    [ 'gsf',     'Game Boy Advance (GSF)' ],
    [ '2sf',     'Nintendo DS (2SF)' ],
    [ '3sf',     'Nintendo 3DS (3SF)' ],
    [ 'usf',     'Nintendo 64 (USF)' ],
    [ 'gcn',     'Nintendo GameCube (GCN)' ],
    [ 'wii',     'Nintendo Wii' ],
    [ 'wiiu',    'Nintendo Wii U' ],
    [ 'switch',  'Nintendo Switch' ],
    [ 'smd',     'Sega Mega Drive / Genesis / Sega CD (VGM/GYM)' ],
    [ 'ssf',     'Sega Saturn (SSF)' ],
    [ 'dsf',     'Sega Dreamcast (DSF)' ],
    [ 'kss',     'MSX / Master System / Game Gear (KSS)' ],
    [ 'hes',     'PC Engine / TurboGrafx-16 (HES)' ],
    [ 'psf',     'Sony PlayStation 1 (PSF)' ],
    [ 'psf2',    'Sony PlayStation 2 (PSF2)' ],
    [ 'psf3',    'Sony PlayStation 3 (PSF3)' ],
    [ 'psf4',    'Sony PlayStation 4 (PSF4)' ],
    [ 'psf5',    'Sony PlayStation 5 (PSF5)' ],
    [ 'psp',     'Sony PlayStation Portable (PSP)' ],
    [ 'vita',    'Sony PlayStation Vita' ],
    [ 's98',     'NEC PC-88 / PC-98 / Sharp X68000 (S98)' ],
    [ 'fmtowns', 'Fujitsu FM Towns' ],
    [ 'ncd',     'SNK Neo Geo CD' ],
    [ '3do',     '3DO Interactive Multiplayer' ],
    [ 'pc',      'PC Game Music' ],
    [ 'xbox',    'Microsoft Xbox' ],
    [ 'x360',    'Microsoft Xbox 360' ],
    [ 'mobile',  'Mobile Platforms' ],
);

# AMP Country IDs from vfs.xml (vfs_amp_countries_list)
my @AMP_COUNTRIES = (
    [ 1, 'Argentina' ], [ 2, 'Australia' ], [ 3, 'Austria' ], [ 4, 'Belarus' ],
    [ 5, 'Belgium' ], [ 6, 'Brazil' ], [ 7, 'Bulgaria' ], [ 8, 'Canada' ],
    [ 9, 'Chile' ], [ 10, 'Costa Rica' ], [ 11, 'Croatia' ], [ 12, 'Cyprus' ],
    [ 13, 'Czech Republic' ], [ 14, 'Denmark' ], [ 15, 'Dominican Republic' ],
    [ 16, 'Estonia' ], [ 17, 'Finland' ], [ 18, 'France' ], [ 19, 'Germany' ],
    [ 20, 'Greece' ], [ 21, 'Hungary' ], [ 22, 'Iceland' ], [ 23, 'Ireland' ],
    [ 24, 'Isle of Man' ], [ 25, 'Isle of Wight' ], [ 26, 'Israel' ],
    [ 27, 'Italy' ], [ 28, 'Japan' ], [ 29, 'Jordan' ], [ 30, 'Lichtenstein' ],
    [ 31, 'Luxembourg' ], [ 32, 'Macedonia' ], [ 33, 'Malta' ], [ 34, 'Martinique' ],
    [ 35, 'Mexico' ], [ 36, 'New Caledonia' ], [ 37, 'New Zealand' ],
    [ 38, 'Northern Ireland' ], [ 39, 'Norway' ], [ 40, 'Poland' ],
    [ 41, 'Portugal' ], [ 42, 'Quebec' ], [ 43, 'Romania' ], [ 44, 'Russia' ],
    [ 45, 'Scotland' ], [ 46, 'Serbia' ], [ 47, 'Singapore' ], [ 48, 'Slovakia' ],
    [ 49, 'Slovenia' ], [ 50, 'South Africa' ], [ 51, 'Spain' ], [ 52, 'Sweden' ],
    [ 53, 'Switzerland' ], [ 54, 'Taiwan' ], [ 55, 'The Netherlands' ],
    [ 56, 'Turkey' ], [ 57, 'USA' ], [ 58, 'Ukraine' ], [ 59, 'United Kingdom' ],
    [ 60, 'Unknown' ], [ 61, 'Uruguay' ], [ 62, 'Venezuela' ], [ 63, 'Wales' ],
    [ 64, 'Yugoslavia (ex)' ], [ 74, 'Corsica' ], [ 79, 'R.I.P' ],
    [ 86, 'Latvia' ], [ 87, 'Peru' ], [ 92, 'Thailand' ], [ 99, 'Iran' ],
    [ 101, 'Iraq' ], [ 114, 'Paraguay' ], [ 120, 'Malaysia' ], [ 122, 'Guatemala' ],
);

# ModArchive Genre list
my @MODARCHIVE_GENRES = (
    [ 2,  'Electronic - General' ],
    [ 3,  'Electronic - Ambient' ],
    [ 4,  'Electronic - Dance' ],
    [ 6,  'Electronic - Drum & Bass' ],
    [ 7,  'Electronic - House' ],
    [ 9,  'Electronic - Progressive' ],
    [ 10, 'Electronic - Rave' ],
    [ 11, 'Electronic - Techno' ],
    [ 12, 'Electronic - Trance' ],
    [ 8,  'Chiptune' ],
    [ 54, 'Demo Style' ],
    [ 55, 'One Hour Compo' ],
    [ 48, 'Video Game' ],
    [ 13, 'Pop - General' ],
    [ 14, 'Pop - Synth' ],
    [ 15, 'Rock - General' ],
    [ 18, 'Rock - Hard' ],
    [ 19, 'Rock - Metal' ],
    [ 25, 'Jazz - General' ],
    [ 27, 'Jazz - Funk' ],
    [ 33, 'Orchestral / Classical' ],
    [ 35, 'Soundtrack' ],
    [ 41, 'World / Folk' ],
    [ 49, 'Alternative / Industrial' ],
);

# ZX-Art localized compo names from VfsRootZxart.kt / vfs.xml
my %ZXART_COMPOS = (
    unknown        => 'Unknown compo',
    standard       => 'Common music compo',
    ay             => 'AY music compo',
    beeper         => 'Beeper music compo',
    copyay         => 'Copy AY compo',
    nocopyay       => 'No-copy AY compo',
    realtime       => 'Realtime compo',
    realtimeay     => 'Realtime AY compo',
    realtimebeeper => 'Realtime beeper compo',
    out            => 'Out of compo',
    wild           => 'Wild compo',
    experimental   => 'Experimental music compo',
    oldschool      => 'Oldschool music compo',
    mainstream     => 'Mainstream music compo',
    progressive    => 'Progressive music compo',
    ts             => 'TurboSound music compo',
    tsfm           => 'TSFM music compo',
    related        => 'Music from event works',
);

# ---------------------------------------------------------------------------
# Utility Helpers
# ---------------------------------------------------------------------------

sub decodeEntities {
    my $str = shift // '';
    $str =~ s/&amp;/&/g;
    $str =~ s/&lt;/</g;
    $str =~ s/&gt;/>/g;
    $str =~ s/&quot;/"/g;
    $str =~ s/&#0*39;/'/g;
    $str =~ s/&apos;/'/g;
    $str =~ s/&nbsp;/ /g;
    $str =~ s/&#(\d+);/chr($1)/ge;
    $str =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

sub stripTags {
    my $str = shift // '';
    $str =~ s/<[^>]*>//g;
    return decodeEntities($str);
}

sub fetchUrl {
    my ($url, $cb, $opts) = @_;
    $opts ||= {};
    my @urls = ref($url) eq 'ARRAY' ? @$url : split(/\|/, $url);
    @urls = grep { defined $_ && /^https?:\/\//i } @urls;

    if (!@urls) {
        return $cb->(undef, 'Invalid URL');
    }

    my $cacheKey = $urls[0];
    if (!$opts->{noCache} && exists $HTTP_CACHE{$cacheKey}) {
        my $entry = $HTTP_CACHE{$cacheKey};
        if (time() - $entry->{time} < CACHE_TTL) {
            return $cb->($entry->{body}, undef);
        }
    }

    my $tryCurlFallback = sub {
        for my $u (@urls) {
            my $body = '';
            if (open(my $pipe, '-|', 'curl', '-s', '-L', '-k', '--max-time', ($opts->{timeout} || 25), '-A', 'ZXTune/5112 LMS/1.0', $u)) {
                local $/;
                $body = <$pipe>;
                close($pipe);
            }
            if ((!defined $body || !length $body) && open(my $wpipe, '-|', 'wget', '-q', '--no-check-certificate', '-T', ($opts->{timeout} || 25), '-U', 'ZXTune/5112 LMS/1.0', '-O', '-', $u)) {
                local $/;
                $body = <$wpipe>;
                close($wpipe);
            }
            if (defined $body && length $body) {
                if (!$opts->{noCache}) {
                    if (scalar(keys %HTTP_CACHE) > 150) {
                        %HTTP_CACHE = ();
                    }
                    $HTTP_CACHE{$cacheKey} = {
                        time => time(),
                        body => $body,
                    };
                }
                return $cb->($body, undef);
            }
        }
        return $cb->(undef, "Failed to load URL: $urls[0]");
    };

    my $tryIdx;
    $tryIdx = sub {
        my $i = shift;
        if ($i >= scalar(@urls)) {
            return $tryCurlFallback->();
        }
        my $u = $urls[$i];
        my $http = Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $res  = shift;
                my $body = $res->content;
                if (defined $body && length $body) {
                    if (!$opts->{noCache}) {
                        if (scalar(keys %HTTP_CACHE) > 150) {
                            %HTTP_CACHE = ();
                        }
                        $HTTP_CACHE{$cacheKey} = {
                            time => time(),
                            body => $body,
                        };
                    }
                    return $cb->($body, undef);
                }
                $tryIdx->($i + 1);
            },
            sub {
                my ($http, $err) = @_;
                $log->warn("HTTP fetch failed ($u): $err");
                $tryIdx->($i + 1);
            },
            {
                timeout => $opts->{timeout} || 20,
                cache   => 0,
            }
        );
        $http->get($u, 'User-Agent' => 'ZXTune/5112 LMS/1.0');
    };

    $tryIdx->(0);
}

sub isContainerExtension {
    my ($ext) = @_;
    return 0 unless defined $ext && length $ext;
    return ($ext =~ /^(zip|7z|rar|lha|lzh|rsn|trd|scl|fdi|dsk|hrip|ay|sid|psid|rsid|nsf|nsfe|gbs|sap|kss|hes)$/i) ? 1 : 0;
}

sub makeTrackItem {
    my ($args) = @_;
    my $title    = $args->{title}    || 'Unknown Track';
    my $artist   = $args->{artist}   || '';
    my $album    = $args->{album}    || '';
    my $url      = $args->{url}      || '';
    my $resolve  = $args->{resolve}  || '';
    my $resId    = $args->{res_id}   || '';
    my $resAlbum = $args->{res_album}|| '';
    my $subpath  = $args->{subpath}  // '';
    my $duration = $args->{duration} || 0;
    my $ext      = $args->{ext}      || '';
    my $icon     = $args->{icon}     || ICON_DEFAULT;
    my $desc     = $args->{desc}     || '';

    if (!$ext && $url =~ /\.([a-zA-Z0-9]{2,8})(?:$|\?|#|\|)/) {
        $ext = lc($1);
    }

    my $display = length($artist) ? "$artist - $title" : $title;
    if (length($desc)) {
        $display .= " ($desc)";
    }
    my $line2 = join(' | ', grep { defined $_ && length $_ } ($artist, $album, $desc));

    # If this remote file is a multi-track archive/container (e.g. JoshW .7z, Aminet .lha, HVSC .sid, ASMA .sap, Scene.org .zip, OCReMix .rsn),
    # make it a browsable folder that downloads, indexes, and lists all tracks inside the game/archive as a playlist!
    my $unpack = $prefs->get('unpack_archives') // 1;
    if ($unpack && !$args->{force_audio} && !length($subpath) && !length($resolve) && isContainerExtension($ext)) {
        return {
            name        => $display,
            line1       => $title,
            line2       => $line2,
            type        => 'link',
            url         => \&menuRemoteArchive,
            image       => $icon,
            passthrough => [ {
                url    => $url,
                title  => $title,
                artist => $artist,
                album  => $album,
                ext    => $ext,
                icon   => $icon,
            } ],
        };
    }

    my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('track', {
        url       => $url,
        resolve   => $resolve,
        res_id    => $resId,
        res_album => $resAlbum,
        subpath   => $subpath,
        title     => $title,
        artist    => $artist,
        album     => $album,
        duration  => $duration,
        ext       => $ext,
        icon      => $icon,
    });

    return {
        name        => $display,
        line1       => $title,
        line2       => $line2,
        type        => 'audio',
        url         => $zxtUrl,
        image       => $icon,
        on_select   => 'play',
        playall     => 1,
    };
}

# ---------------------------------------------------------------------------
# Online Catalogue & Album Favourites System
# ---------------------------------------------------------------------------

my %FAV_HANDLERS = (
    remote_archive    => \&menuRemoteArchive,
    httpdir           => \&menuHttpDirBrowse,
    khinsider_album   => \&menuKhinsiderAlbumTracks,
    vgmrips_pack      => \&menuVGMRipsPackDetail,
    zxtunes_author    => \&menuZXTunesAuthorTracks,
    zxart_author      => \&menuZXArtAuthorTracks,
    zxart_party       => \&menuZXArtPartyTracks,
    modarchive_artist => \&menuModArchiveArtistTracks,
    modland_group     => \&menuModLandTracks,
    amp_author        => \&menuAMPAuthorTracks,
    ocremix_game      => \&menuOCRemixGameDetail,
    ocremix_album     => \&menuOCRemixAlbumTracks,
    local_archive     => \&menuLocalArchive,
    local_dir         => \&menuLocalDir,
);

sub _getFavorites {
    my $favs = $prefs->get('favorites');
    return (ref($favs) eq 'ARRAY') ? $favs : [];
}

sub isFavorite {
    my ($favId) = @_;
    return 0 unless defined $favId && length $favId;
    my $favs = _getFavorites();
    return (grep { $_ && $_->{id} && $_->{id} eq $favId } @$favs) ? 1 : 0;
}

sub makeFavoriteToggleItem {
    my ($spec) = @_;
    return () unless $spec && $spec->{id} && $spec->{handler};
    my $title = $spec->{title} || 'Album';
    my $saved = isFavorite($spec->{id});
    my $label = $saved
        ? "[- Remove '$title' from ZXTune Favourites]"
        : "[+ Add '$title' to ZXTune Favourites]";

    my @out;
    if ($spec->{justToggled}) {
        push @out, {
            name => $saved ? "Added '$title' to ZXTune Favourites!" : "Removed '$title' from ZXTune Favourites.",
            type => 'text',
        };
    }
    push @out, {
        name        => $label,
        type        => 'link',
        url         => \&menuToggleFavorite,
        passthrough => [ $spec ],
        image       => $spec->{icon} || ICON_DEFAULT,
    };
    return @out;
}

sub menuToggleFavorite {
    my ($client, $cb, $args, $spec) = @_;
    my $id   = $spec->{id} || '';
    my $favs = _getFavorites();

    if (isFavorite($id)) {
        my @filtered = grep { $_ && $_->{id} && $_->{id} ne $id } @$favs;
        $prefs->set('favorites', \@filtered);
    } else {
        my $entry = {
            id      => $id,
            title   => $spec->{title}   || 'Saved Album',
            cat     => $spec->{cat}     || 'ZXTune',
            handler => $spec->{handler} || '',
            pt      => $spec->{pt}      || {},
            icon    => $spec->{icon}    || ICON_DEFAULT,
        };
        push @$favs, $entry;
        $prefs->set('favorites', $favs);
    }
    $prefs->savenow();

    my $handlerSub = $FAV_HANDLERS{$spec->{handler} || ''};
    if ($handlerSub) {
        my %newPt = %{ $spec->{pt} || {} };
        $newPt{_favJustToggled} = 1;
        return $handlerSub->($client, $cb, $args, \%newPt);
    }
    return menuFavorites($client, $cb, $args);
}

sub menuFavorites {
    my ($client, $cb, $args) = @_;
    my $favs = _getFavorites();
    my @items;

    if (!@$favs) {
        push @items, {
            name => 'No favourites saved yet. Open any album, game, or author in Online Catalogues and click [+ Add to ZXTune Favourites]!',
            type => 'text',
        };
        return $cb->({ items => \@items });
    }

    for my $f (@$favs) {
        next unless $f && $f->{handler} && $FAV_HANDLERS{$f->{handler}};
        my $cat   = $f->{cat}   || 'ZXTune';
        my $title = $f->{title} || 'Saved Collection';
        my $icon  = $f->{icon}  || ICON_DEFAULT;
        push @items, {
            name        => "[$cat] $title",
            line1       => $title,
            line2       => "$cat Favourite",
            type        => 'link',
            url         => $FAV_HANDLERS{$f->{handler}},
            passthrough => [ $f->{pt} || {} ],
            image       => $icon,
        };
    }

    push @items, {
        name  => '[Manage / Remove Saved Favourites...]',
        type  => 'link',
        url   => \&menuRemoveFavoriteList,
        image => ICON_DEFAULT,
    };

    $cb->({ items => \@items });
}

sub menuRemoveFavoriteList {
    my ($client, $cb, $args) = @_;
    my $favs = _getFavorites();
    my @items;

    for my $f (@$favs) {
        next unless $f && $f->{id};
        my $cat   = $f->{cat}   || 'ZXTune';
        my $title = $f->{title} || 'Saved Collection';
        push @items, {
            name        => "[- Delete] [$cat] $title",
            type        => 'link',
            url         => \&menuDeleteFavorite,
            passthrough => [ { id => $f->{id} } ],
            image       => $f->{icon} || ICON_DEFAULT,
        };
    }

    if (!@items) {
        push @items, { name => 'No favourites to remove', type => 'text' };
    }
    $cb->({ items => \@items });
}

sub menuDeleteFavorite {
    my ($client, $cb, $args, $pt) = @_;
    my $id   = $pt->{id} || '';
    my $favs = _getFavorites();
    my @filtered = grep { $_ && $_->{id} && $_->{id} ne $id } @$favs;
    $prefs->set('favorites', \@filtered);
    $prefs->savenow();
    return menuFavorites($client, $cb, $args);
}

sub menuRemoteArchive {
    my ($client, $cb, $args, $pt) = @_;
    my $url    = $pt->{url}    || '';
    my $title  = $pt->{title}  || 'Archive';
    my $artist = $pt->{artist} || '';
    my $album  = $pt->{album}  || $title;
    my $ext    = $pt->{ext}    || 'dat';
    my $icon   = $pt->{icon}   || ICON_DEFAULT;

    Plugins::ZXTune::ProtocolHandler->downloadUrlToCache($url, $ext, sub {
        my ($cacheFile, $err) = @_;
        if (!$cacheFile || $err) {
            return $cb->({
                items => [ {
                    name => "Error downloading $title: " . ($err || 'Failed'),
                    type => 'text',
                } ]
            });
        }

        Plugins::ZXTune::Metadata->resolveGameMetadata($title, sub {
            my ($gameMeta) = @_;
            my $cleanGame  = ($gameMeta && $gameMeta->{gameTitle}) ? $gameMeta->{gameTitle} : $title;
            my $resolvedIcon = ($icon && $icon ne ICON_DEFAULT)
                             ? $icon
                             : (($gameMeta && $gameMeta->{cover}) ? $gameMeta->{cover} : ICON_DEFAULT);

            my $modules = Plugins::ZXTune::Metadata->indexFile($cacheFile, $title);
            my @items;

            push @items, makeFavoriteToggleItem({
                id          => "archive:$url",
                title       => $cleanGame,
                cat         => $album || 'Online Archive',
                handler     => 'remote_archive',
                pt          => { url => $url, title => $title, artist => $artist, album => $album, ext => $ext, icon => $resolvedIcon },
                icon        => $resolvedIcon,
                justToggled => $pt->{_favJustToggled},
            });

            if ($modules && @$modules) {
                for my $m (@$modules) {
                    my $mTitle  = $m->{title} || $cleanGame;
                    my $mArtist = ($m->{artist} && $m->{artist} ne 'Unknown Composer')
                                ? $m->{artist}
                                : (($gameMeta && $gameMeta->{artist}) || $artist || $cleanGame);
                    my $mAlbum  = ($m->{album} && $m->{album} !~ /^[0-9a-f]{40}$/i) ? $m->{album} : $cleanGame;

                    my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
                        file    => $cacheFile,
                        subpath => $m->{subpath},
                        title   => $mTitle,
                        artist  => $mArtist,
                        album   => $mAlbum,
                        type    => $m->{type},
                        icon    => $resolvedIcon,
                    });

                    my $desc = join(' | ', grep { defined $_ && length $_ } ($m->{type}, $m->{subpath}, $m->{program}));
                    push @items, {
                        name      => sprintf("%02d. %s - %s%s", $m->{tracknum}, $mArtist, $mTitle, length($desc) ? " ($desc)" : ""),
                        line1     => sprintf("%02d. %s", $m->{tracknum}, $mTitle),
                        line2     => join(' | ', grep { defined $_ && length $_ } ($mArtist, $mAlbum, $desc)),
                        type      => 'audio',
                        url       => $zxtUrl,
                        image     => $resolvedIcon,
                        on_select => 'play',
                        playall   => 1,
                    };
                }
            } else {
                my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
                    file   => $cacheFile,
                    title  => $cleanGame,
                    artist => ($gameMeta && $gameMeta->{artist}) || $artist || $album,
                    album  => $cleanGame,
                    icon   => $resolvedIcon,
                });
                push @items, {
                    name      => $cleanGame,
                    type      => 'audio',
                    url       => $zxtUrl,
                    image     => $resolvedIcon,
                    on_select => 'play',
                    playall   => 1,
                };
            }

            $cb->({ items => \@items });
        });
    });
}

# ---------------------------------------------------------------------------
# Top-Level Menus
# ---------------------------------------------------------------------------

sub getMainMenu {
    my ($class, $client, $cb, $args) = @_;

    my $savedLocalDir = $prefs->get('local_music_dir') || '';
    my $hasSavedDir   = (length($savedLocalDir) && -d $savedLocalDir) ? 1 : 0;
    my $localItem     = $hasSavedDir
        ? {
            name        => 'Local Chiptunes & Archives (' . (basename($savedLocalDir) || $savedLocalDir) . ')',
            type        => 'link',
            url         => \&menuLocalDir,
            passthrough => [ { dir => $savedLocalDir } ],
            image       => ICON_DEFAULT,
        }
        : {
            name  => 'Local Chiptunes & Archives Browser',
            type  => 'link',
            url   => \&menuLocalRoots,
            image => ICON_DEFAULT,
        };

    my $favCount = scalar(@{ _getFavorites() });
    my $favLabel = $favCount > 0
        ? "Favourites ($favCount Saved Albums & Collections)"
        : 'Favourites (Saved Albums & Collections)';

    my @items = (
        {
            name  => 'Online Catalogues (14 Archives)',
            type  => 'link',
            url   => \&menuOnlineCatalogs,
            image => ICON_DEFAULT,
        },
        {
            name  => $favLabel,
            type  => 'link',
            url   => \&menuFavorites,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Radio (Random Tunes & Compilations)',
            type  => 'link',
            url   => \&menuRadio,
            image => ICON_DEFAULT,
        },
        $localItem,
        {
            name  => 'Global Search Across Catalogues',
            type  => 'search',
            url   => \&menuGlobalSearch,
            image => ICON_DEFAULT,
        },
    );

    $cb->({ items => \@items });
}

sub menuOnlineCatalogs {
    my ($client, $cb, $args) = @_;

    my @items = (
        {
            name  => 'ZXTunes.com - ZX Spectrum Musicians Catalogue',
            line1 => 'ZXTunes.com',
            line2 => 'ZX Spectrum AY/YM & Beeper Music Collection',
            type  => 'link',
            url   => \&menuZXTunesRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'ZX-Art.ee - Modern ZX Spectrum Music & Parties',
            line1 => 'ZX-Art.ee',
            line2 => 'Authors, Demoparties, Compos & Top 100 Tracks',
            type  => 'link',
            url   => \&menuZXArtRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'The Mod Archive - Tracker Modules (MOD/XM/IT/S3M)',
            line1 => 'The Mod Archive',
            line2 => 'Artists, Genres, Charts, Random & Search (modarchive.org)',
            type  => 'link',
            url   => \&menuModArchiveRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'ModLand - Largest Tracker & Chiptune Archive',
            line1 => 'ModLand (Exotica / ftp.modland.com)',
            line2 => '400,000+ Modules by Author, Collection, Format & Directory',
            type  => 'link',
            url   => \&menuModLandRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'High Voltage SID Collection (HVSC) - Commodore 64',
            line1 => 'High Voltage SID Collection (HVSC)',
            line2 => '55,000+ C64 SID Tunes (DEMOS, GAMES, MUSICIANS)',
            type  => 'link',
            url   => \&menuHVSCRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Atari SAP Music Archive (ASMA) - Atari XL/XE',
            line1 => 'Atari SAP Music Archive (ASMA)',
            line2 => 'Atari 8-bit POKEY Music (Composers, Games, Groups, Misc)',
            type  => 'link',
            url   => \&menuASMARoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'AYGOR - The AY Great Original Resource',
            line1 => 'AYGOR',
            line2 => 'ZX Spectrum / Amstrad / Atari ST AY Collection',
            type  => 'link',
            url   => \&menuAYGORRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'JoshW - Console & Computer Chiptune Archives (31 Systems)',
            line1 => 'JoshW Console & Computer Archives',
            line2 => 'NES, SNES, GB, GBA, DS, N64, Genesis, Saturn, PS1/2, PC Engine, MSX...',
            type  => 'link',
            url   => \&menuJoshWRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Amiga Music Preservation (AMP) - Amiga Demoscene',
            line1 => 'Amiga Music Preservation (amp.dascene.net)',
            line2 => 'Handles A-Z, Countries, Demoscene Groups & Module Search',
            type  => 'link',
            url   => \&menuAMPRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Aminet - Amiga Music Modules Archive',
            line1 => 'Aminet Music Modules (aminet.net/mods)',
            line2 => 'Browse Subdirectories & Search Aminet Modules',
            type  => 'link',
            url   => \&menuAminetRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Scene.org - Demoscene Music Archive',
            line1 => 'Scene.org (files.scene.org/browse/music)',
            line2 => 'Artists, Compos, Music Disks, Groups, Labels & Parties',
            type  => 'link',
            url   => \&menuSceneRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'VGMRips - Arcade, Console & Computer VGM Packs',
            line1 => 'VGMRips (vgmrips.net)',
            line2 => 'Companies, Composers, Sound Chips, Systems & Random Packs',
            type  => 'link',
            url   => \&menuVGMRipsRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Khinsider - Video Game Soundtracks',
            line1 => 'Video Game Music (downloads.khinsider.com)',
            line2 => 'Top 40, New 100, Favorites, Series, Platforms, A-Z & Years',
            type  => 'link',
            url   => \&menuKhinsiderRoot,
            image => ICON_DEFAULT,
        },
        {
            name  => 'OverClocked ReMix (OCReMix) - Game Music & Chiptunes',
            line1 => 'OverClocked ReMix (ocremix.org)',
            line2 => 'Systems, Organizations, Games, Chiptunes & Remixes',
            type  => 'link',
            url   => \&menuOCRemixRoot,
            image => ICON_DEFAULT,
        },
    );

    $cb->({ items => \@items });
}

# ---------------------------------------------------------------------------
# Radio Menu & Random Feed Generator
# ---------------------------------------------------------------------------

sub menuRadio {
    my ($client, $cb, $args) = @_;

    my @items = (
        {
            name      => 'ZXTune All-Catalogue Megamix Radio (Continuous Shuffle)',
            type      => 'audio',
            url       => 'zxtune://radio/all/title=ZXTune%20Megamix%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name      => 'The Mod Archive - Random Tracker Radio',
            type      => 'audio',
            url       => 'zxtune://radio/modarchive/title=ModArchive%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name      => 'VGMRips - Random Arcade & Console VGM Radio',
            type      => 'audio',
            url       => 'zxtune://radio/vgmrips/title=VGMRips%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name      => 'ZX-Art - Random ZX Spectrum Party & Top Tunes Radio',
            type      => 'audio',
            url       => 'zxtune://radio/zxart/title=ZX-Art%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name      => 'ZXTunes.com - Random ZX Spectrum Chiptune Radio',
            type      => 'audio',
            url       => 'zxtune://radio/zxtunes/title=ZXTunes%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name      => 'Khinsider - Random Video Game Soundtrack Radio',
            type      => 'audio',
            url       => 'zxtune://radio/khinsider/title=Khinsider%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
    );

    $cb->({ items => \@items });
}

sub fetchRandomRadioTrack {
    my ($class, $source, $cb) = @_;
    $source = lc($source || 'all');

    if ($source eq 'all') {
        my @pool = ('modarchive', 'vgmrips', 'zxart', 'zxtunes', 'khinsider');
        $source = $pool[int(rand(scalar(@pool)))];
    }

    if ($source eq 'modarchive') {
        return _randomModArchiveTrack($cb);
    } elsif ($source eq 'vgmrips') {
        return _randomVGMRipsTrack($cb);
    } elsif ($source eq 'zxart') {
        return _randomZXArtTrack($cb);
    } elsif ($source eq 'zxtunes') {
        return _randomZXTunesTrack($cb);
    } elsif ($source eq 'khinsider') {
        return _randomKhinsiderTrack($cb);
    } else {
        return _randomModArchiveTrack($cb);
    }
}

sub _randomModArchiveTrack {
    my ($cb) = @_;
    my $key = $prefs->get('modarchive_key') || '';
    if (length $key) {
        my $u = "https://api.modarchive.org/xml-tools.php?key=" . uri_escape($key) . "&request=random";
        fetchUrl($u, sub {
            my ($xml, $err) = @_;
            my @tracks = _parseModArchiveXmlTracks($xml);
            if (@tracks) {
                my $t = $tracks[int(rand(scalar(@tracks)))];
                return $cb->({
                    url    => "https://api.modarchive.org/downloads.php?moduleid=$t->{id}",
                    title  => $t->{title} || $t->{filename},
                    artist => $t->{artist} || 'The Mod Archive',
                    album  => 'The Mod Archive Radio',
                    ext    => $t->{ext} || 'mod',
                });
            }
            _randomModArchiveWebTrack($cb);
        }, { noCache => 1 });
        return;
    }
    _randomModArchiveWebTrack($cb);
}

sub _randomModArchiveWebTrack {
    my ($cb) = @_;
    fetchUrl('https://modarchive.org/index.php?request=view_by_random', sub {
        my ($html, $err) = @_;
        if ($html && $html =~ /downloads\.php\?moduleid=(\d+)#([^"'\s<>]+)/i) {
            my $id    = $1;
            my $fname = uri_unescape($2);
            my $title = $fname;
            if ($html =~ /<h1[^>]*>(.*?)<\/h1>/is) {
                $title = stripTags($1) || $fname;
            }
            my $ext = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'mod';
            return $cb->({
                url    => "https://api.modarchive.org/downloads.php?moduleid=$id",
                title  => $title,
                artist => 'The Mod Archive',
                album  => "ModArchive #$id ($fname)",
                ext    => $ext,
            });
        }
        $cb->(undef, $err || 'Could not parse random ModArchive module');
    }, { noCache => 1 });
}

sub _randomVGMRipsTrack {
    my ($cb) = @_;
    fetchUrl('https://vgmrips.net/packs/random', sub {
        my ($html, $err) = @_;
        return $cb->(undef, $err) if !$html;
        my ($packTitle, $img, @tracks) = _parseVGMRipsPackPage($html);
        if (@tracks) {
            my $t = $tracks[int(rand(scalar(@tracks)))];
            return $cb->({
                url    => $t->{url},
                title  => $t->{title},
                artist => $t->{artist} || 'VGMRips',
                album  => $packTitle   || 'VGMRips Radio',
                icon   => $img         || ICON_DEFAULT,
                ext    => 'vgz',
            });
        }
        $cb->(undef, 'No tracks found in random VGMRips pack');
    }, { noCache => 1 });
}

sub _randomZXArtTrack {
    my ($cb) = @_;
    fetchUrl('https://zxart.ee/zxtune/language:eng/action:topTunes/limit:100', sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXArtXmlTracks($xml);
        if (@tracks) {
            my $t = $tracks[int(rand(scalar(@tracks)))];
            return $cb->({
                url    => "https://zxart.ee/file/id:$t->{id}",
                title  => $t->{title} || $t->{filename},
                artist => $t->{artist} || 'ZX-Art',
                album  => $t->{year} ? "ZX-Art ($t->{year})" : 'ZX-Art Top 100',
                ext    => $t->{ext} || 'pt3',
            });
        }
        $cb->(undef, $err || 'No ZX-Art tracks found');
    });
}

sub _randomZXTunesTrack {
    my ($cb) = @_;
    _getZXTunesAuthors(sub {
        my ($authors) = @_;
        if (!$authors || !@$authors) {
            return $cb->(undef, 'Could not load ZXTunes authors');
        }
        my $a = $authors->[int(rand(scalar(@$authors)))];
        my $u = "https://zxtunes.com/xml.php?scope=tracks&fields=filename,title,duration,date&author_id=$a->{id}";
        fetchUrl($u, sub {
            my ($xml, $err) = @_;
            my @tracks = _parseZXTunesXmlTracks($xml, $a->{nickname});
            if (@tracks) {
                my $t = $tracks[int(rand(scalar(@tracks)))];
                return $cb->({
                    url      => "https://zxtunes.com/downloads.php?id=$t->{id}",
                    title    => $t->{title} || $t->{filename},
                    artist   => $a->{nickname},
                    album    => $t->{date} ? "ZXTunes ($t->{date})" : 'ZXTunes.com',
                    duration => $t->{duration} || 0,
                    ext      => $t->{ext} || 'pt3',
                });
            }
            $cb->(undef, 'No tracks for ZXTunes author');
        });
    });
}

sub _randomKhinsiderTrack {
    my ($cb) = @_;
    fetchUrl('https://downloads.khinsider.com/random-album', sub {
        my ($html, $err) = @_;
        return $cb->(undef, $err) if !$html;
        my ($albumId, $albumTitle, $img, @tracks) = _parseKhinsiderAlbumPage($html);
        if (@tracks) {
            my $t = $tracks[int(rand(scalar(@tracks)))];
            _resolveKhinsiderTrack($albumId, $t->{id}, sub {
                my ($dlUrl) = @_;
                return $cb->(undef, 'Failed to resolve Khinsider track') unless $dlUrl;
                my $ext = ($dlUrl =~ /\.([a-zA-Z0-9]+)(?:$|\?)/) ? lc($1) : 'mp3';
                $cb->({
                    url    => $dlUrl,
                    title  => $t->{title},
                    artist => 'Khinsider VGM',
                    album  => $albumTitle || $albumId,
                    icon   => $img || ICON_DEFAULT,
                    ext    => $ext,
                });
            });
            return;
        }
        $cb->(undef, 'No tracks found on random Khinsider album');
    }, { noCache => 1 });
}

# ---------------------------------------------------------------------------
# Dynamic Track URL Resolution (Khinsider / OCReMix)
# ---------------------------------------------------------------------------

sub resolveTrackDownload {
    my ($class, $params, $cb) = @_;
    my $type = $params->{resolve} || '';

    if ($type eq 'khinsider') {
        my $albumId = $params->{res_album} || '';
        my $trackId = $params->{res_id}    || '';
        return _resolveKhinsiderTrack($albumId, $trackId, $cb);
    } elsif ($type eq 'ocremix') {
        my $remixId = $params->{res_id} || '';
        my $u = "https://ocremix.org/remix/$remixId";
        fetchUrl($u, sub {
            my ($html, $err) = @_;
            if ($html && $html =~ /href=["'](https?:\/\/ocrmirror\.org\/files\/[^"']+)["']/i) {
                my $dl = $1;
                my $ext = ($dl =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'mp3';
                return $cb->($dl, { ext => $ext });
            }
            $cb->(undef);
        });
        return;
    }

    $cb->(undef);
}

sub _extractKhinsiderAudioUrls {
    my ($html) = @_;
    return () unless defined $html && length $html;

    my @links;
    my %seen;
    my $addLink = sub {
        my $raw = shift // '';
        $raw = decodeEntities($raw);
        $raw =~ s/^\s+|\s+$//g;
        $raw = "https:$raw" if $raw =~ /^\/\//;
        $raw =~ s/\s+/%20/g;
        return unless $raw =~ /^https?:\/\//i;
        return if $raw =~ /\/game-soundtracks\/album\//i;
        return if $seen{$raw}++;
        push @links, $raw;
    };

    # 1. Links containing <span class="songDownloadLink">
    while ($html =~ /<a[^>]+href=["']((?:https?:)?\/\/[^"']+)["'][^>]*>(?:(?!<\/a>).)*?songDownloadLink/gis) {
        $addLink->($1);
    }
    # 2. <audio id="audio" src="..."> player element
    while ($html =~ /<audio[^>]+src=["']((?:https?:)?\/\/[^"']+)["']/gis) {
        $addLink->($1);
    }
    # 3. Direct CDN links (/soundtracks/... or vgmsite / vgmtreasurechest / vgmdownloads)
    while ($html =~ /href=["']((?:https?:)?\/\/[^"']*\/soundtracks\/[^"']+\.(?:flac|mp3|ogg|m4a|wav)(?:\?[^"']*)?)["']/gis) {
        $addLink->($1);
    }

    return @links;
}

sub _resolveKhinsiderTrack {
    my ($albumId, $trackId, $cb) = @_;
    return $cb->(undef) unless defined $trackId && length $trackId;

    my @candidateUrls;
    my %seenU;
    my $addCandidate = sub {
        my $u = shift;
        return unless defined $u && $u =~ /^https?:\/\//i;
        push @candidateUrls, $u unless $seenU{$u}++;
    };

    if ($trackId =~ /^https?:\/\//i) {
        $addCandidate->($trackId);
    } elsif ($trackId =~ /^\/game-soundtracks\/album\//i) {
        $addCandidate->("https://downloads.khinsider.com$trackId");
    }

    # Also build double-encoded and single-encoded track page URLs from the track filename
    my $rawFile = $trackId;
    $rawFile =~ s#^.*/##;
    my $decodedFile = uri_unescape(uri_unescape($rawFile));
    if (length($albumId) && length($decodedFile)) {
        # Khinsider track page URLs use double-encoded filenames (e.g. %2520)
        $addCandidate->("https://downloads.khinsider.com/game-soundtracks/album/$albumId/" . uri_escape(uri_escape($decodedFile)));
        $addCandidate->("https://downloads.khinsider.com/game-soundtracks/album/$albumId/$rawFile");
        $addCandidate->("https://downloads.khinsider.com/game-soundtracks/album/$albumId/" . uri_escape($decodedFile));
    }

    my $tryPage;
    $tryPage = sub {
        my $idx = shift;
        if ($idx >= scalar(@candidateUrls)) {
            return $cb->(undef);
        }
        fetchUrl($candidateUrls[$idx], sub {
            my ($html, $err) = @_;
            my @links = _extractKhinsiderAudioUrls($html);
            if (@links) {
                # Prefer FLAC if present, otherwise MP3 / first link (with MP3 as fallback mirror!)
                my ($flac) = grep { /\.flac(?:$|\?)/i } @links;
                my ($mp3)  = grep { /\.mp3(?:$|\?)/i }  @links;
                my $picked = $flac || $mp3 || $links[0];
                my $ext    = ($picked =~ /\.([a-zA-Z0-9]+)(?:$|\?)/) ? lc($1) : 'mp3';
                # If both FLAC and MP3 exist, join with '|' so if one mirror fails, downloadUrlToCache tries the other
                if ($flac && $mp3 && $flac ne $mp3) {
                    $picked = "$flac|$mp3";
                }
                return $cb->($picked, { ext => $ext });
            }
            $tryPage->($idx + 1);
        });
    };

    $tryPage->(0);
}

# ---------------------------------------------------------------------------
# 1. ZXTunes.com Catalogue (https://zxtunes.com/xml.php)
# ---------------------------------------------------------------------------

sub menuZXTunesRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name  => 'Authors (A-Z)',
            type  => 'link',
            url   => \&menuZXTunesLetters,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Search Authors',
            type  => 'search',
            url   => \&menuZXTunesSearch,
            image => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub _getZXTunesAuthors {
    my ($cb) = @_;
    fetchUrl('https://zxtunes.com/xml.php?scope=authors&fields=nickname,name,tracks,photo', sub {
        my ($xml, $err) = @_;
        if (!$xml) {
            return $cb->([]);
        }
        my @authors;
        while ($xml =~ /<author\s+id=["'](\d+)["'][^>]*>(.*?)<\/author>/gis) {
            my $id   = int($1);
            my $body = $2;
            my ($nick)   = ($body =~ /<nickname>(.*?)<\/nickname>/is);
            my ($name)   = ($body =~ /<name>(.*?)<\/name>/is);
            my ($tracks) = ($body =~ /<tracks>(\d+)<\/tracks>/is);
            my ($photo)  = ($body =~ /<photo>(\d+)<\/photo>/is);
            $tracks = int($tracks || 0);
            next unless $tracks > 0 && defined $nick && length $nick;
            push @authors, {
                id       => $id,
                nickname => decodeEntities($nick),
                name     => decodeEntities($name // ''),
                tracks   => $tracks,
                photo    => int($photo || 0),
            };
        }
        @authors = sort { lc($a->{nickname}) cmp lc($b->{nickname}) } @authors;
        $cb->(\@authors);
    });
}

sub menuZXTunesLetters {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $l ('#', 'A' .. 'Z') {
        push @items, {
            name        => $l,
            type        => 'link',
            url         => \&menuZXTunesAuthorsByLetter,
            passthrough => [ { letter => $l } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuZXTunesAuthorsByLetter {
    my ($client, $cb, $args, $pt) = @_;
    my $letter = $pt->{letter} || 'A';
    _getZXTunesAuthors(sub {
        my ($authors) = @_;
        my @items;
        for my $a (@$authors) {
            my $first = uc(substr($a->{nickname}, 0, 1));
            my $match = ($letter eq '#') ? ($first !~ /^[A-Z]$/) : ($first eq $letter);
            next unless $match;
            my $label = length($a->{name}) ? "$a->{nickname} ($a->{name}) [$a->{tracks}]" : "$a->{nickname} [$a->{tracks}]";
            my $img   = $a->{photo} ? "https://zxtunes.com/photo/$a->{id}.jpg" : ICON_DEFAULT;
            push @items, {
                name        => $label,
                type        => 'link',
                url         => \&menuZXTunesAuthorTracks,
                image       => $img,
                passthrough => [ $a ],
            };
        }
        $cb->({ items => \@items });
    });
}

sub menuZXTunesSearch {
    my ($client, $cb, $args) = @_;
    my $q = lc($args->{search} || '');
    _getZXTunesAuthors(sub {
        my ($authors) = @_;
        my @items;
        for my $a (@$authors) {
            if (index(lc($a->{nickname}), $q) >= 0 || index(lc($a->{name}), $q) >= 0) {
                my $label = length($a->{name}) ? "$a->{nickname} ($a->{name}) [$a->{tracks}]" : "$a->{nickname} [$a->{tracks}]";
                push @items, {
                    name        => $label,
                    type        => 'link',
                    url         => \&menuZXTunesAuthorTracks,
                    image       => $a->{photo} ? "https://zxtunes.com/photo/$a->{id}.jpg" : ICON_DEFAULT,
                    passthrough => [ $a ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuZXTunesAuthorTracks {
    my ($client, $cb, $args, $author) = @_;
    my $u = "https://zxtunes.com/xml.php?scope=tracks&fields=filename,title,duration,date&author_id=$author->{id}";
    fetchUrl($u, sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXTunesXmlTracks($xml, $author->{nickname});
        my $img    = $author->{photo} ? "https://zxtunes.com/photo/$author->{id}.jpg" : ICON_DEFAULT;
        my @items;
        push @items, makeFavoriteToggleItem({
            id          => "zxtunes:$author->{id}",
            title       => "$author->{nickname} (ZXTunes)",
            cat         => 'ZXTunes.com',
            handler     => 'zxtunes_author',
            pt          => { id => $author->{id}, nickname => $author->{nickname}, name => $author->{name}, photo => $author->{photo} },
            icon        => $img,
            justToggled => $author->{_favJustToggled},
        });
        for my $t (@tracks) {
            push @items, makeTrackItem({
                title    => $t->{title} || $t->{filename},
                artist   => $author->{nickname},
                album    => $t->{date} ? "ZXTunes ($t->{date})" : 'ZXTunes.com',
                url      => "https://zxtunes.com/downloads.php?id=$t->{id}",
                duration => $t->{duration},
                ext      => $t->{ext},
                icon     => $img,
                desc     => $t->{date} ? "$t->{filename} | $t->{date}" : $t->{filename},
            });
        }
        $cb->({ items => \@items });
    });
}

sub _parseZXTunesXmlTracks {
    my ($xml, $authorName) = @_;
    return () unless $xml;
    my @out;
    while ($xml =~ /<track\s+id=["'](\d+)["'][^>]*>(.*?)<\/track>/gis) {
        my $id   = int($1);
        my $body = $2;
        my ($fname)  = ($body =~ /<filename>(.*?)<\/filename>/is);
        my ($title)  = ($body =~ /<title>(.*?)<\/title>/is);
        my ($frames) = ($body =~ /<duration>(\d+)<\/duration>/is);
        my ($date)   = ($body =~ /<date>(\d+)<\/date>/is);
        $fname = decodeEntities($fname // "track_$id.pt3");
        $title = decodeEntities($title // '');
        my $ext  = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'pt3';
        my $secs = $frames ? int($frames / 50) : 0;
        push @out, {
            id       => $id,
            filename => $fname,
            title    => length($title) ? $title : $fname,
            duration => $secs,
            date     => $date || '',
            ext      => $ext,
            artist   => $authorName || 'ZXTunes',
        };
    }
    return @out;
}

# ---------------------------------------------------------------------------
# 2. ZX-Art.ee Catalogue (https://zxart.ee/zxtune/...)
# ---------------------------------------------------------------------------

sub menuZXArtRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name  => 'Top 100 Tracks',
            type  => 'link',
            url   => \&menuZXArtTop,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Authors (A-Z)',
            type  => 'link',
            url   => \&menuZXArtAuthorLetters,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Parties (By Year)',
            type  => 'link',
            url   => \&menuZXArtPartyYears,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Search Tracks',
            type  => 'search',
            url   => \&menuZXArtSearch,
            image => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuZXArtTop {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://zxart.ee/zxtune/language:eng/action:topTunes/limit:100', sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXArtXmlTracks($xml);
        @tracks = sort { ($b->{votes} || 0) <=> ($a->{votes} || 0) } @tracks;
        my @items = map { _zxartTrackToItem($_) } @tracks;
        $cb->({ items => \@items });
    });
}

sub menuZXArtSearch {
    my ($client, $cb, $args) = @_;
    my $q = $args->{search} || '';
    my $u = 'https://zxart.ee/zxtune/language:eng/action:search/query:' . uri_escape($q);
    fetchUrl($u, sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXArtXmlTracks($xml);
        my @items  = map { _zxartTrackToItem($_) } @tracks;
        $cb->({ items => \@items });
    });
}

sub menuZXArtAuthorLetters {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $l ('#', 'A' .. 'Z') {
        push @items, {
            name        => $l,
            type        => 'link',
            url         => \&menuZXArtAuthorsByLetter,
            passthrough => [ { letter => $l } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuZXArtAuthorsByLetter {
    my ($client, $cb, $args, $pt) = @_;
    my $letter = $pt->{letter} || 'A';
    fetchUrl('https://zxart.ee/zxtune/language:eng/action:authors', sub {
        my ($xml, $err) = @_;
        my @authors;
        if ($xml) {
            while ($xml =~ /<author>(.*?)<\/author>/gis) {
                my $b = $1;
                my ($id)   = ($b =~ /<id>(\d+)<\/id>/is);
                my ($nick) = ($b =~ /<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>/is);
                my ($real) = ($b =~ /<realName>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/realName>/is);
                next unless $id && defined $nick && length $nick;
                $nick = decodeEntities($nick);
                $real = decodeEntities($real // '');
                my $first = uc(substr($nick, 0, 1));
                my $match = ($letter eq '#') ? ($first !~ /^[A-Z]$/) : ($first eq $letter);
                next unless $match;
                push @authors, { id => int($id), nickname => $nick, name => $real };
            }
        }
        @authors = sort { lc($a->{nickname}) cmp lc($b->{nickname}) } @authors;
        my @items = map {
            {
                name        => length($_->{name}) ? "$_->{nickname} ($_->{name})" : $_->{nickname},
                type        => 'link',
                url         => \&menuZXArtAuthorTracks,
                passthrough => [ $_ ],
            }
        } @authors;
        $cb->({ items => \@items });
    });
}

sub menuZXArtAuthorTracks {
    my ($client, $cb, $args, $author) = @_;
    my $u = "https://zxart.ee/zxtune/language:eng/action:tunes/authorId:$author->{id}";
    fetchUrl($u, sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXArtXmlTracks($xml, $author->{nickname});
        my @items  = makeFavoriteToggleItem({
            id          => "zxart_author:$author->{id}",
            title       => "$author->{nickname} (ZX-Art)",
            cat         => 'ZX-Art.ee',
            handler     => 'zxart_author',
            pt          => { id => $author->{id}, nickname => $author->{nickname}, name => $author->{name} },
            icon        => ICON_DEFAULT,
            justToggled => $author->{_favJustToggled},
        });
        push @items, map { _zxartTrackToItem($_) } @tracks;
        $cb->({ items => \@items });
    });
}

sub menuZXArtPartyYears {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://zxart.ee/zxtune/language:eng/action:parties', sub {
        my ($xml, $err) = @_;
        my %years;
        if ($xml) {
            while ($xml =~ /<party>(.*?)<\/party>/gis) {
                my $b = $1;
                my ($yr) = ($b =~ /<year>(\d+)<\/year>/is);
                $years{int($yr || 0)}++;
            }
        }
        my @items;
        for my $y (sort { $b <=> $a } keys %years) {
            push @items, {
                name        => $y ? "$y ($years{$y} parties)" : "Unknown Year ($years{$y})",
                type        => 'link',
                url         => \&menuZXArtPartiesByYear,
                passthrough => [ { year => $y } ],
            };
        }
        $cb->({ items => \@items });
    });
}

sub menuZXArtPartiesByYear {
    my ($client, $cb, $args, $pt) = @_;
    my $year = int($pt->{year} || 0);
    fetchUrl('https://zxart.ee/zxtune/language:eng/action:parties', sub {
        my ($xml, $err) = @_;
        my @parties;
        if ($xml) {
            while ($xml =~ /<party>(.*?)<\/party>/gis) {
                my $b = $1;
                my ($id)   = ($b =~ /<id>(\d+)<\/id>/is);
                my ($name) = ($b =~ /<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>/is);
                my ($yr)   = ($b =~ /<year>(\d+)<\/year>/is);
                next unless $id && int($yr || 0) == $year;
                push @parties, { id => int($id), name => decodeEntities($name // "Party $id"), year => $year };
            }
        }
        @parties = sort { lc($a->{name}) cmp lc($b->{name}) } @parties;
        my @items = map {
            {
                name        => $_->{name},
                type        => 'link',
                url         => \&menuZXArtPartyTracks,
                passthrough => [ $_ ],
            }
        } @parties;
        $cb->({ items => \@items });
    });
}

sub menuZXArtPartyTracks {
    my ($client, $cb, $args, $party) = @_;
    my $u = "https://zxart.ee/zxtune/language:eng/action:tunes/partyId:$party->{id}";
    fetchUrl($u, sub {
        my ($xml, $err) = @_;
        my @tracks = _parseZXArtXmlTracks($xml);
        @tracks = sort { ($a->{place} || 999) <=> ($b->{place} || 999) } @tracks;
        my @items = makeFavoriteToggleItem({
            id          => "zxart_party:$party->{id}",
            title       => "$party->{name} ($party->{year})",
            cat         => 'ZX-Art.ee Party',
            handler     => 'zxart_party',
            pt          => { id => $party->{id}, name => $party->{name}, year => $party->{year} },
            icon        => ICON_DEFAULT,
            justToggled => $party->{_favJustToggled},
        });
        push @items, map { _zxartTrackToItem($_, $party->{name}) } @tracks;
        $cb->({ items => \@items });
    });
}

sub _parseZXArtXmlTracks {
    my ($xml, $defaultArtist) = @_;
    return () unless $xml;
    my @out;
    while ($xml =~ /<tune>(.*?)<\/tune>/gis) {
        my $b = $1;
        my ($id)     = ($b =~ /<id>(\d+)<\/id>/is);
        my ($fname)  = ($b =~ /<originalFileName>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/originalFileName>/is);
        my ($title)  = ($b =~ /<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>/is);
        my ($iauth)  = ($b =~ /<internalAuthor>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/internalAuthor>/is);
        my ($ititle) = ($b =~ /<internalTitle>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/internalTitle>/is);
        my ($votes)  = ($b =~ /<votes>([0-9.]+)<\/votes>/is);
        my ($time)   = ($b =~ /<time>([^<]+)<\/time>/is);
        my ($year)   = ($b =~ /<year>(\d+)<\/year>/is);
        my ($compo)  = ($b =~ /<compo>([^<]+)<\/compo>/is);
        my ($place)  = ($b =~ /<partyplace>(\d+)<\/partyplace>/is);

        next unless $id;
        $fname = decodeEntities($fname // "tune_$id.pt3");
        $title = decodeEntities($title // $ititle // $fname);
        $iauth = decodeEntities($iauth // $defaultArtist // 'ZX-Art');
        my $ext = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'pt3';

        my $secs = 0;
        if ($time && $time =~ /^(?:(\d+):)?(\d+):(\d+)/) {
            $secs = (defined $1 ? int($1) * 3600 : 0) + int($2) * 60 + int($3);
        }

        push @out, {
            id       => int($id),
            filename => $fname,
            title    => $title,
            artist   => $iauth,
            votes    => $votes || '',
            duration => $secs,
            year     => int($year || 0),
            compo    => $compo ? ($ZXART_COMPOS{lc($compo)} || $compo) : '',
            place    => int($place || 0),
            ext      => $ext,
        };
    }
    return @out;
}

sub _zxartTrackToItem {
    my ($t, $partyName) = @_;
    my @meta;
    push @meta, "#$t->{place}" if $t->{place};
    push @meta, $t->{compo}    if $t->{compo};
    push @meta, $t->{year}     if $t->{year};
    push @meta, "*$t->{votes}" if $t->{votes};

    return makeTrackItem({
        title    => $t->{title},
        artist   => $t->{artist},
        album    => $partyName || ($t->{year} ? "ZX-Art ($t->{year})" : 'ZX-Art.ee'),
        url      => "https://zxart.ee/file/id:$t->{id}",
        duration => $t->{duration},
        ext      => $t->{ext},
        desc     => join(' | ', @meta),
    });
}

# ---------------------------------------------------------------------------
# 3. The Mod Archive (https://modarchive.org & https://api.modarchive.org)
# ---------------------------------------------------------------------------

sub menuModArchiveRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name      => 'Random Pick! (Stream Random Modules)',
            type      => 'audio',
            url       => 'zxtune://radio/modarchive/title=ModArchive%20Random%20Pick',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name  => 'Artists (A-Z)',
            type  => 'link',
            url   => \&menuModArchiveArtistLetters,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Genres',
            type  => 'link',
            url   => \&menuModArchiveGenres,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Top Favourites Chart',
            type  => 'link',
            url   => \&menuModArchiveChart,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Search Modules (Filename or Song Title)',
            type  => 'search',
            url   => \&menuModArchiveSearch,
            image => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuModArchiveArtistLetters {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $l ('A' .. 'Z') {
        push @items, {
            name        => $l,
            type        => 'link',
            url         => \&menuModArchiveArtistsByLetter,
            passthrough => [ { letter => $l, page => 1 } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuModArchiveArtistsByLetter {
    my ($client, $cb, $args, $pt) = @_;
    my $letter = $pt->{letter} || 'A';
    my $page   = int($pt->{page} || 1);
    my $u      = "https://modarchive.org/index.php?request=search_artist&query=$letter&search_type=guessed_artist&page=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a[^>]+href=["'][^"']*request=view_artist_modules(?:&amp;|&)query=(\d+)["'][^>]*>(.*?)<\/a>/gis) {
                my $id   = int($1);
                my $name = stripTags($2);
                next if !$name || $seen{$id}++;
                push @items, {
                    name        => $name,
                    type        => 'link',
                    url         => \&menuModArchiveArtistTracks,
                    passthrough => [ { id => $id, name => $name, page => 1 } ],
                };
            }
            if ($html =~ /page=(\d+)[^>]*>(?:Next|&gt;|\xBB)/i) {
                push @items, {
                    name        => "Next Page (" . ($page + 1) . ") ->",
                    type        => 'link',
                    url         => \&menuModArchiveArtistsByLetter,
                    passthrough => [ { letter => $letter, page => $page + 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuModArchiveArtistTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $id   = $pt->{id};
    my $name = $pt->{name} || "Artist #$id";
    my $page = int($pt->{page} || 1);
    my $u    = "https://modarchive.org/index.php?request=view_artist_modules&query=$id&page=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = makeFavoriteToggleItem({
            id          => "modarchive_artist:$id",
            title       => "$name (ModArchive)",
            cat         => 'The Mod Archive',
            handler     => 'modarchive_artist',
            pt          => { id => $id, name => $name, page => 1 },
            icon        => ICON_DEFAULT,
            justToggled => $pt->{_favJustToggled},
        });
        my @tracks = _parseModArchiveWebTracks($html, $name);
        push @items, @tracks;
        if ($html && $html =~ /page=(\d+)[^>]*>(?:Next|&gt;|\xBB)/i && scalar(@tracks) >= 20) {
            push @items, {
                name        => "Next Page (" . ($page + 1) . ") ->",
                type        => 'link',
                url         => \&menuModArchiveArtistTracks,
                passthrough => [ { id => $id, name => $name, page => $page + 1 } ],
            };
        }
        $cb->({ items => \@items });
    });
}

sub menuModArchiveGenres {
    my ($client, $cb, $args) = @_;
    my @items = map {
        {
            name        => $_->[1],
            type        => 'link',
            url         => \&menuModArchiveGenreTracks,
            passthrough => [ { id => $_->[0], name => $_->[1], page => 1 } ],
        }
    } @MODARCHIVE_GENRES;
    $cb->({ items => \@items });
}

sub menuModArchiveGenreTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $id   = $pt->{id};
    my $name = $pt->{name};
    my $page = int($pt->{page} || 1);
    my $u    = "https://modarchive.org/index.php?request=search&search_type=genre&query=$id&page=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = _parseModArchiveWebTracks($html, $name);
        if (scalar(@items) >= 20) {
            push @items, {
                name        => "Next Page (" . ($page + 1) . ") ->",
                type        => 'link',
                url         => \&menuModArchiveGenreTracks,
                passthrough => [ { id => $id, name => $name, page => $page + 1 } ],
            };
        }
        $cb->({ items => \@items });
    });
}

sub menuModArchiveChart {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://modarchive.org/index.php?request=view_chart&query=tophits', sub {
        my ($html, $err) = @_;
        my @items = _parseModArchiveWebTracks($html, 'ModArchive Top Chart');
        $cb->({ items => \@items });
    });
}

sub menuModArchiveSearch {
    my ($client, $cb, $args) = @_;
    my $q = $args->{search} || '';
    my $u = 'https://modarchive.org/index.php?request=search&query=' . uri_escape($q) . '&submit=Find&search_type=filename_or_songtitle';
    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = _parseModArchiveWebTracks($html, 'The Mod Archive');
        $cb->({ items => \@items });
    });
}

sub _parseModArchiveWebTracks {
    my ($html, $defaultAlbum) = @_;
    return () unless $html;
    my @items;
    my %seen;

    while ($html =~ /downloads\.php\?moduleid=(\d+)#([^"'\s<>]+)["'][^>]*>(.*?)<\/a>(.{0,500})/gis) {
        my $id    = int($1);
        my $fname = uri_unescape($2);
        my $linkT = stripTags($3);
        my $after = $4 // '';
        next if $seen{$id}++;

        my $title = ($linkT && $linkT !~ /^download$/i) ? $linkT : $fname;
        if ($after =~ /view_player(?:&amp;|&)query=$id["'][^>]*>(.*?)<\/a>/is) {
            my $pt = stripTags($1);
            $title = $pt if length $pt;
        }
        my $ext = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'mod';

        push @items, makeTrackItem({
            title  => $title,
            artist => $defaultAlbum || 'The Mod Archive',
            album  => 'The Mod Archive',
            url    => "https://api.modarchive.org/downloads.php?moduleid=$id",
            ext    => $ext,
            desc   => $fname,
        });
    }
    return @items;
}

sub _parseModArchiveXmlTracks {
    my ($xml) = @_;
    return () unless $xml;
    my @out;
    while ($xml =~ /<module>(.*?)<\/module>/gis) {
        my $b = $1;
        my ($id)    = ($b =~ /<id>(\d+)<\/id>/is);
        my ($fname) = ($b =~ /<filename>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/filename>/is);
        my ($title) = ($b =~ /<songtitle>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/songtitle>/is);
        my ($alias) = ($b =~ /<artist_info>.*?<alias>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/alias>/is);
        next unless $id;
        $fname = decodeEntities($fname // "mod_$id.mod");
        $title = decodeEntities($title // $fname);
        my $ext = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'mod';
        push @out, {
            id       => int($id),
            filename => $fname,
            title    => $title,
            artist   => decodeEntities($alias // 'The Mod Archive'),
            ext      => $ext,
        };
    }
    return @out;
}

# ---------------------------------------------------------------------------
# 4. ModLand (Exotica Special:Modland & ftp.amigascne.org mirror)
# ---------------------------------------------------------------------------

sub menuModLandRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name        => 'Authors (A-Z)',
            type        => 'link',
            url         => \&menuModLandLetters,
            passthrough => [ { type => 'aut', label => 'Authors' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Collections (A-Z)',
            type        => 'link',
            url         => \&menuModLandLetters,
            passthrough => [ { type => 'col', label => 'Collections' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Formats (A-Z)',
            type        => 'link',
            url         => \&menuModLandLetters,
            passthrough => [ { type => 'for', label => 'Formats' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Browse Direct Mirror Tree (pub/modules/)',
            type        => 'link',
            url         => \&menuHttpDirBrowse,
            passthrough => [ {
                base  => 'https://ftp.amigascne.org/mirrors/ftp.modland.com/pub/modules/',
                path  => '',
                album => 'ModLand',
            } ],
            image       => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuModLandLetters {
    my ($client, $cb, $args, $pt) = @_;
    my @items;
    for my $l ('#', 'A' .. 'Z') {
        push @items, {
            name        => $l,
            type        => 'link',
            url         => \&menuModLandGroups,
            passthrough => [ { type => $pt->{type}, letter => $l, page => 1 } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuModLandGroups {
    my ($client, $cb, $args, $pt) = @_;
    my $type   = $pt->{type}   || 'aut';
    my $letter = $pt->{letter} || 'A';
    my $page   = int($pt->{page} || 1);
    my $u      = "https://www.exotica.org.uk/mediawiki/index.php?title=Special:Modland&md=b_${type}&st=" . uri_escape($letter) . "&pg=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            while ($html =~ /<tr[^>]*>\s*<td[^>]*>\s*<a[^>]+href=["'][^"']*md=${type}(?:&amp;|&)id=(\d+)["'][^>]*>(.*?)<\/a>\s*<\/td>\s*<td[^>]*>\s*(\d+)/gis) {
                my $id    = int($1);
                my $name  = stripTags($2);
                my $count = int($3);
                next unless length $name;
                push @items, {
                    name        => "$name ($count tracks)",
                    type        => 'link',
                    url         => \&menuModLandTracks,
                    passthrough => [ { type => $type, id => $id, name => $name, page => 1 } ],
                };
            }
            if ($html =~ /showing page (\d+) of (\d+)/i && int($1) < int($2)) {
                push @items, {
                    name        => "Next Page (" . ($page + 1) . " / $2) ->",
                    type        => 'link',
                    url         => \&menuModLandGroups,
                    passthrough => [ { type => $type, letter => $letter, page => $page + 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuModLandTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $type = $pt->{type} || 'aut';
    my $id   = $pt->{id};
    my $name = $pt->{name} || 'ModLand';
    my $page = int($pt->{page} || 1);
    my $u    = "https://www.exotica.org.uk/mediawiki/index.php?title=Special:Modland&md=${type}&id=$id&pg=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = makeFavoriteToggleItem({
            id          => "modland:$type:$id",
            title       => "$name (ModLand)",
            cat         => 'ModLand',
            handler     => 'modland_group',
            pt          => { type => $type, id => $id, name => $name, page => 1 },
            icon        => ICON_DEFAULT,
            justToggled => $pt->{_favJustToggled},
        });
        if ($html) {
            while ($html =~ /href=["'][^"']*file=(pub\/modules\/[^"'&]+)["'][^>]*>(.*?)<\/a>/gis) {
                my $relPath = $1;
                my $label   = stripTags($2);
                my $fname   = $relPath;
                $fname =~ s#^.*/##;
                $fname = uri_unescape($fname);
                my $ext = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'mod';
                my $dl1 = "https://ftp.amigascne.org/mirrors/ftp.modland.com/$relPath";
                my $dl2 = "https://modland.com/$relPath";

                push @items, makeTrackItem({
                    title  => $label || $fname,
                    artist => $name,
                    album  => 'ModLand',
                    url    => "$dl1|$dl2",
                    ext    => $ext,
                    desc   => uri_unescape($relPath),
                });
            }
            if ($html =~ /showing page (\d+) of (\d+)/i && int($1) < int($2)) {
                push @items, {
                    name        => "Next Page (" . ($page + 1) . " / $2) ->",
                    type        => 'link',
                    url         => \&menuModLandTracks,
                    passthrough => [ { type => $type, id => $id, name => $name, page => $page + 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

# ---------------------------------------------------------------------------
# Generic HTTP Directory Browser (HVSC, ASMA, AYGOR, JoshW, Scene.org)
# Ports ZXTune's app.zxtune.fs.httpdir.RemoteCatalog (XML <list>, <table>, <pre>)
# ---------------------------------------------------------------------------

sub menuHttpDirBrowse {
    my ($client, $cb, $args, $pt) = @_;
    my $base  = $pt->{base};
    my $alt   = $pt->{alt} || '';
    my $path  = $pt->{path} // '';
    my $album = $pt->{album} || 'ZXTune Online';

    my $fullUrl = $base . $path;
    my @tryUrls = ($fullUrl);
    if (length $alt) {
        push @tryUrls, $alt . $path;
    }

    fetchUrl(\@tryUrls, sub {
        my ($html, $err) = @_;
        if (!$html) {
            return $cb->({ items => [ { name => "Error loading directory: " . ($err || 'empty'), type => 'text' } ] });
        }

        my ($dirs, $files) = _parseHttpDirPage($html);
        my @items;

        if (length $path) {
            push @items, makeFavoriteToggleItem({
                id          => "httpdir:$base$path",
                title       => $album,
                cat         => ($album =~ /^([^-(\/]+)/) ? $1 : 'Online Folder',
                handler     => 'httpdir',
                pt          => { base => $base, alt => $alt, path => $path, album => $album },
                icon        => ICON_DEFAULT,
                justToggled => $pt->{_favJustToggled},
            });
        }

        for my $d (@$dirs) {
            my $sub = $path . $d->{href};
            $sub .= '/' unless $sub =~ /\/$/;
            push @items, {
                name        => $d->{desc} ? "$d->{name} ($d->{desc})" : $d->{name},
                type        => 'link',
                url         => \&menuHttpDirBrowse,
                passthrough => [ {
                    base  => $base,
                    alt   => $alt,
                    path  => $sub,
                    album => "$album / $d->{name}",
                } ],
            };
        }

        for my $f (@$files) {
            my $fileUrl = $base . $path . $f->{href};
            if (length $alt) {
                $fileUrl .= '|' . $alt . $path . $f->{href};
            }
            my $fname = $f->{name};
            my $ext   = ($fname =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'dat';

            # Skip non-audio readme/text/image files in raw HTTP directories
            next if $ext =~ /^(txt|diz|nfo|doc|pdf|htm|html|jpg|jpeg|png|gif|bmp|md5|sfv|css|js)$/i;

            # Format JoshW-style filenames cleanly if applicable
            my $cleanTitle = $fname;
            $cleanTitle =~ s/\.[^.]+$//;
            my $gameMeta = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($cleanTitle);
            my $icon     = ($gameMeta && $gameMeta->{cover}) ? $gameMeta->{cover} : ICON_DEFAULT;

            push @items, makeTrackItem({
                title  => $cleanTitle,
                artist => ($gameMeta && $gameMeta->{artist}) || $album,
                album  => $album,
                url    => $fileUrl,
                ext    => $ext,
                icon   => $icon,
                desc   => join(' | ', grep { defined $_ && length $_ } ($f->{size}, $f->{desc})),
            });
        }

        $cb->({ items => \@items });
    });
}

sub _parseHttpDirPage {
    my ($doc) = @_;
    my (@dirs, @files);

    # 1. XML <list><directory ...>name</directory><file size="..." ...>name</file></list>
    if ($doc =~ /<list[^>]*>/i) {
        while ($doc =~ /<directory([^>]*)>(.*?)<\/directory>/gis) {
            my $attr = $1;
            my $name = stripTags($2);
            $name =~ s/\/+$//;
            next if !$name || $name eq '.' || $name eq '..';
            my ($mtime) = ($attr =~ /mtime=["']([^"']+)["']/i);
            push @dirs, { name => $name, href => uri_escape($name) . '/', desc => $mtime || '' };
        }
        while ($doc =~ /<file([^>]*)>(.*?)<\/file>/gis) {
            my $attr = $1;
            my $name = stripTags($2);
            next unless length $name;
            my ($size)  = ($attr =~ /size=["'](\d+)["']/i);
            my ($mtime) = ($attr =~ /mtime=["']([^"']+)["']/i);
            my $szStr   = $size ? int($size / 1024) . ' KB' : '';
            push @files, { name => $name, href => uri_escape($name), size => $szStr, desc => $mtime || '' };
        }
        return (\@dirs, \@files) if @dirs || @files;
    }

    # 2. Apache / Nginx HTML <table> or <pre> anchor listings
    my %seen;
    while ($doc =~ /<a\s+[^>]*href=["']([^"'?#]+)["'][^>]*>(.*?)<\/a>((?:(?!<a\s).){0,300})/gis) {
        my $href  = $1;
        my $text  = stripTags($2);
        my $after = stripTags($3);

        $href =~ s/&amp;/&/g;
        next if $href =~ /^(?:https?:|mailto:|javascript:|\/|\.\.)/i;
        next if $text =~ /^Parent Directory$/i;

        my $decoded = uri_unescape($href);
        $decoded =~ s/^\.\///;
        next if !length($decoded) || $decoded eq '.' || $decoded eq '..';
        next if $seen{$decoded}++;

        if ($decoded =~ /\/$/) {
            my $dname = $decoded;
            $dname =~ s/\/+$//;
            next if $dname =~ /\//; # skip non-child links
            push @dirs, {
                name => $dname,
                href => $href,
                desc => '',
            };
        } else {
            next if $decoded =~ /\//;
            my $size = '';
            if ($after =~ /\b(\d+(?:\.\d+)?\s*[KMGB]{1,2})\b/i) {
                $size = $1;
            } elsif ($after =~ /([0-9.]+[KMGB]?)\s*$/i) {
                $size = $1;
            }
            push @files, {
                name => $decoded,
                href => $href,
                size => $size,
                desc => '',
            };
        }
    }

    return (\@dirs, \@files);
}

# ---------------------------------------------------------------------------
# 5. High Voltage SID Collection (HVSC)
# ---------------------------------------------------------------------------

sub menuHVSCRoot {
    my ($client, $cb, $args) = @_;
    return menuHttpDirBrowse($client, $cb, $args, {
        base  => 'https://hvsc.brona.dk/HVSC/C64Music/',
        alt   => 'https://www.prg.dtu.dk/HVSC/C64Music/',
        path  => '',
        album => 'HVSC C64Music',
    });
}

# ---------------------------------------------------------------------------
# 6. Atari SAP Music Archive (ASMA)
# ---------------------------------------------------------------------------

sub menuASMARoot {
    my ($client, $cb, $args) = @_;
    return menuHttpDirBrowse($client, $cb, $args, {
        base  => 'https://asma.atari.org/asma/',
        path  => '',
        album => 'ASMA Atari SAP',
    });
}

# ---------------------------------------------------------------------------
# 7. AYGOR - The AY Great Original Resource
# ---------------------------------------------------------------------------

sub menuAYGORRoot {
    my ($client, $cb, $args) = @_;
    return menuHttpDirBrowse($client, $cb, $args, {
        base  => 'http://abrimaal.pro-e.pl/ayon/',
        path  => '',
        album => 'AYGOR',
    });
}

# ---------------------------------------------------------------------------
# 8. JoshW Console & Computer Archives (31 Sub-Catalogues)
# ---------------------------------------------------------------------------

sub menuJoshWRoot {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $cat (@JOSHW_CATALOGS) {
        my ($id, $title) = @$cat;
        push @items, {
            name        => $title,
            type        => 'link',
            url         => \&menuHttpDirBrowse,
            passthrough => [ {
                base  => "https://$id.joshw.info/",
                alt   => "http://$id.joshw.info/",
                path  => '',
                album => "JoshW ($title)",
            } ],
            image       => ICON_DEFAULT,
        };
    }
    $cb->({ items => \@items });
}

# ---------------------------------------------------------------------------
# 9. Amiga Music Preservation - AMP (https://amp.dascene.net)
# ---------------------------------------------------------------------------

sub menuAMPRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name  => 'Handles (0-9, A-Z)',
            type  => 'link',
            url   => \&menuAMPLetters,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Countries',
            type  => 'link',
            url   => \&menuAMPCountries,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Groups',
            type  => 'link',
            url   => \&menuAMPGroups,
            image => ICON_DEFAULT,
        },
        {
            name  => 'Search Modules',
            type  => 'search',
            url   => \&menuAMPSearch,
            image => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuAMPLetters {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $l ('0-9', 'a' .. 'z') {
        push @items, {
            name        => uc($l),
            type        => 'link',
            url         => \&menuAMPAuthorsQuery,
            passthrough => [ { req => 'list', search => $l, pos => 0 } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuAMPCountries {
    my ($client, $cb, $args) = @_;
    my @items = map {
        {
            name        => $_->[1],
            type        => 'link',
            url         => \&menuAMPAuthorsQuery,
            passthrough => [ { req => 'country', search => $_->[0], pos => 0 } ],
        }
    } @AMP_COUNTRIES;
    $cb->({ items => \@items });
}

sub menuAMPGroups {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://amp.dascene.net/newresult.php?request=groups', sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            while ($html =~ /<a\s+href=["']newresult\.php\?request=groupid(?:&amp;|&)search=(\d+)["'][^>]*>(.*?)<\/a>/gis) {
                my $id   = int($1);
                my $name = stripTags($2);
                next unless length $name;
                push @items, {
                    name        => $name,
                    type        => 'link',
                    url         => \&menuAMPAuthorsQuery,
                    passthrough => [ { req => 'groupid', search => $id, pos => 0 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuAMPAuthorsQuery {
    my ($client, $cb, $args, $pt) = @_;
    my $req    = $pt->{req};
    my $search = $pt->{search};
    my $pos    = int($pt->{pos} || 0);
    my $u      = "https://amp.dascene.net/newresult.php?request=$req&search=" . uri_escape($search) . "&position=$pos";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']detail\.php\?view=(\d+)["'][^>]*>(.*?)<\/a>(.{0,400})/gis) {
                my $id     = int($1);
                my $handle = stripTags($2);
                my $after  = $3 // '';
                next if !$handle || $seen{$id}++;
                my $real = '';
                if ($after =~ /Real Name:?<\/td>\s*<td[^>]*>(.*?)<\/td>/is) {
                    $real = stripTags($1);
                    $real = '' if $real eq 'n/a';
                }
                push @items, {
                    name        => length($real) ? "$handle ($real)" : $handle,
                    type        => 'link',
                    url         => \&menuAMPAuthorTracks,
                    passthrough => [ { id => $id, handle => $handle } ],
                };
            }
            if ($html =~ /position=(\d+)["'][^>]*>\s*<img[^>]+right\.gif/i && int($1) > $pos) {
                my $nextPos = int($1);
                push @items, {
                    name        => "Next Page ($nextPos) ->",
                    type        => 'link',
                    url         => \&menuAMPAuthorsQuery,
                    passthrough => [ { req => $req, search => $search, pos => $nextPos } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuAMPAuthorTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $id     = $pt->{id};
    my $handle = $pt->{handle} || 'AMP';
    my $u      = "https://amp.dascene.net/detail.php?detail=modules&view=$id";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = makeFavoriteToggleItem({
            id          => "amp:$id",
            title       => "$handle (AMP)",
            cat         => 'Amiga Music Preservation',
            handler     => 'amp_author',
            pt          => { id => $id, handle => $handle },
            icon        => ICON_DEFAULT,
            justToggled => $pt->{_favJustToggled},
        });
        push @items, _parseAMPTracks($html, $handle);
        $cb->({ items => \@items });
    });
}

sub menuAMPSearch {
    my ($client, $cb, $args) = @_;
    my $q = $args->{search} || '';
    my $u = "https://amp.dascene.net/newresult.php?request=module&search=" . uri_escape($q);
    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = _parseAMPTracks($html, 'AMP');
        $cb->({ items => \@items });
    });
}

sub _parseAMPTracks {
    my ($html, $defaultAuthor) = @_;
    return () unless $html;
    my @items;
    my %seen;
    while ($html =~ /<a\s+href=["']downmod\.php\?index=(\d+)["'][^>]*>(.*?)<\/a>(.{0,400})/gis) {
        my $id    = int($1);
        my $name  = stripTags($2);
        my $after = $3 // '';
        next if !$name || $seen{$id}++;
        my $author = $defaultAuthor;
        if ($after =~ /detail\.php\?view=\d+["'][^>]*>(.*?)<\/a>/is) {
            my $a = stripTags($1);
            $author = $a if length $a;
        }
        my $size = '';
        if ($after =~ /(\d+\s*Kb)/i) {
            $size = $1;
        }
        push @items, makeTrackItem({
            title  => $name,
            artist => $author,
            album  => 'Amiga Music Preservation',
            url    => "https://amp.dascene.net/downmod.php?index=$id",
            ext    => 'gz',
            desc   => $size,
        });
    }
    return @items;
}

# ---------------------------------------------------------------------------
# 10. Aminet Music Modules (https://aminet.net/mods)
# ---------------------------------------------------------------------------

sub menuAminetRoot {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://aminet.net/tree?path=mods', sub {
        my ($html, $err) = @_;
        my @items = (
            {
                name  => 'Search Aminet Modules',
                type  => 'search',
                url   => \&menuAminetSearch,
                image => ICON_DEFAULT,
            }
        );
        if ($html) {
            while ($html =~ /<a\s+href=["'][^"']*path=mods\/([^"'&]+)["'][^>]*>mods\/\1<\/a>\s*-\s*([^\r\n<]+)/gis) {
                my $sub  = $1;
                my $desc = stripTags($2);
                push @items, {
                    name        => "mods/$sub - $desc",
                    type        => 'link',
                    url         => \&menuAminetDir,
                    passthrough => [ { path => $sub, page => 0 } ],
                };
            }
        }
        # Fallback standard Aminet mods subdirs if tree layout changes
        if (scalar(@items) == 1) {
            for my $sub (qw(8voic chip demo funk hardc jungl med melod misc piano pop pro rock s3m smpl synth techn tranc voice xm)) {
                push @items, {
                    name        => "mods/$sub",
                    type        => 'link',
                    url         => \&menuAminetDir,
                    passthrough => [ { path => $sub, page => 0 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuAminetDir {
    my ($client, $cb, $args, $pt) = @_;
    my $path = $pt->{path};
    my $page = int($pt->{page} || 0);
    my $u    = "https://aminet.net/search?path=mods/$path" . ($page ? "&page=$page" : '');

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = _parseAminetSearchRows($html);
        if (scalar(@items) >= 40) {
            push @items, {
                name        => "Next Page (" . ($page + 1) . ") ->",
                type        => 'link',
                url         => \&menuAminetDir,
                passthrough => [ { path => $path, page => $page + 1 } ],
            };
        }
        $cb->({ items => \@items });
    });
}

sub menuAminetSearch {
    my ($client, $cb, $args) = @_;
    my $q = uri_escape($args->{search} || '');
    my $u = "https://aminet.net/search?name=$q&q_desc=OR&desc=$q&path[]=mods";
    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items = _parseAminetSearchRows($html);
        $cb->({ items => \@items });
    });
}

sub _parseAminetSearchRows {
    my ($html) = @_;
    return () unless $html;
    my @items;
    while ($html =~ /<tr\s+class=["'](?:lightrow|darkrow)["'][^>]*>(.*?)<\/tr>/gis) {
        my $row = $1;
        if ($row =~ /href=["'](\/mods\/([^"']+))["']/i) {
            my $rel  = $1;
            my $sub  = $2;
            my @tds  = ($row =~ /<td[^>]*>(.*?)<\/td>/gis);
            my $size = @tds >= 5 ? stripTags($tds[4]) : '';
            my $desc = @tds >= 8 ? stripTags($tds[7]) : '';
            my $ext  = ($sub =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'lha';
            push @items, makeTrackItem({
                title  => length($desc) ? "$sub - $desc" : $sub,
                artist => 'Aminet',
                album  => 'Aminet Mods',
                url    => "https://aminet.net$rel",
                ext    => $ext,
                desc   => $size,
            });
        }
    }
    return @items;
}

# ---------------------------------------------------------------------------
# 11. Scene.org Demoscene Music Archive
# ---------------------------------------------------------------------------

sub menuSceneRoot {
    my ($client, $cb, $args) = @_;
    return menuHttpDirBrowse($client, $cb, $args, {
        base  => 'https://archive.scene.org/pub/music/',
        path  => '',
        album => 'Scene.org Music',
    });
}

# ---------------------------------------------------------------------------
# 12. VGMRips (https://vgmrips.net)
# ---------------------------------------------------------------------------

sub menuVGMRipsRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name      => 'Random VGM Radio (Stream Random Tracks)',
            type      => 'audio',
            url       => 'zxtune://radio/vgmrips/title=VGMRips%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name        => 'Systems',
            type        => 'link',
            url         => \&menuVGMRipsGrouping,
            passthrough => [ { type => 'systems' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Sound Chips',
            type        => 'link',
            url         => \&menuVGMRipsGrouping,
            passthrough => [ { type => 'chips' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Companies',
            type        => 'link',
            url         => \&menuVGMRipsGrouping,
            passthrough => [ { type => 'companies' } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Composers',
            type        => 'link',
            url         => \&menuVGMRipsGrouping,
            passthrough => [ { type => 'composers' } ],
            image       => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuVGMRipsGrouping {
    my ($client, $cb, $args, $pt) = @_;
    my $type = $pt->{type} || 'systems';
    my $u    = "https://vgmrips.net/packs/$type/";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            if ($type eq 'companies') {
                while ($html =~ /<a[^>]+href=["']https?:\/\/vgmrips\.net\/packs\/company\/([^"'\/]+)["'][^>]+title=["']([^"']+)["'][^>]*>/gis) {
                    my ($id, $title) = ($1, decodeEntities($2));
                    next if $seen{$id}++;
                    push @items, {
                        name        => $title,
                        type        => 'link',
                        url         => \&menuVGMRipsPacks,
                        passthrough => [ { path => "/packs/company/$id/developed", page => 0 } ],
                    };
                }
            } elsif ($type eq 'composers') {
                while ($html =~ /<li\s+class=["']composer["'][^>]*>\s*<a\s+href=["']https?:\/\/vgmrips\.net\/packs\/composer\/([^"']+)["'][^>]*>(.*?)<\/a>/gis) {
                    my $id   = $1;
                    my $raw  = $2;
                    $raw =~ s/<span[^>]*>.*?<\/span>//gis;
                    my $name = stripTags($raw);
                    next if !$name || $seen{$id}++;
                    push @items, {
                        name        => $name,
                        type        => 'link',
                        url         => \&menuVGMRipsPacks,
                        passthrough => [ { path => "/packs/composer/$id", page => 0 } ],
                    };
                }
            } elsif ($type eq 'chips') {
                while ($html =~ /<a\s+href=["']https?:\/\/vgmrips\.net\/packs\/chip\/([^"']+)["'][^>]*>([^<]+)<\/a>/gis) {
                    my ($id, $name) = ($1, stripTags($2));
                    next if !$name || $seen{$id}++;
                    push @items, {
                        name        => $name,
                        type        => 'link',
                        url         => \&menuVGMRipsPacks,
                        passthrough => [ { path => "/packs/chip/$id", page => 0 } ],
                    };
                }
            } else {
                while ($html =~ /<a\s+href=["']https?:\/\/vgmrips\.net\/packs\/system\/([^"']+)["'][^>]*>([^<]+)<\/a>/gis) {
                    my ($id, $name) = ($1, stripTags($2));
                    next if !$name || $seen{$id}++;
                    push @items, {
                        name        => $name,
                        type        => 'link',
                        url         => \&menuVGMRipsPacks,
                        passthrough => [ { path => "/packs/system/$id", page => 0 } ],
                    };
                }
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuVGMRipsPacks {
    my ($client, $cb, $args, $pt) = @_;
    my $path = $pt->{path};
    my $page = int($pt->{page} || 0);
    my $u    = "https://vgmrips.net$path?p=$page";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']https?:\/\/vgmrips\.net\/packs\/pack\/([^"']+)["'][^>]*>\s*<img[^>]+src=["']([^"']+)["'][^>]+alt=["']([^"']+)["']/gis) {
                my ($id, $img, $title) = ($1, $2, decodeEntities($3));
                next if $seen{$id}++;
                push @items, {
                    name        => $title,
                    type        => 'link',
                    url         => \&menuVGMRipsPackDetail,
                    image       => $img,
                    passthrough => [ { id => $id, title => $title, image => $img } ],
                };
            }
            if (scalar(@items) >= 20) {
                push @items, {
                    name        => "Next Page (" . ($page + 1) . ") ->",
                    type        => 'link',
                    url         => \&menuVGMRipsPacks,
                    passthrough => [ { path => $path, page => $page + 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuVGMRipsPackDetail {
    my ($client, $cb, $args, $pt) = @_;
    my $id = $pt->{id};
    my $u  = "https://vgmrips.net/packs/pack/$id";

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my ($packTitle, $img, @tracks) = _parseVGMRipsPackPage($html);
        $packTitle ||= $pt->{title} || $id;
        $img       ||= $pt->{image} || ICON_DEFAULT;

        my @items = makeFavoriteToggleItem({
            id          => "vgmrips:$id",
            title       => $packTitle,
            cat         => 'VGMRips',
            handler     => 'vgmrips_pack',
            pt          => { id => $id, title => $packTitle, image => $img },
            icon        => $img,
            justToggled => $pt->{_favJustToggled},
        });
        for my $t (@tracks) {
            push @items, makeTrackItem({
                title    => $t->{title},
                artist   => $packTitle,
                album    => $packTitle,
                url      => $t->{url},
                duration => $t->{duration},
                ext      => 'vgz',
                icon     => $img,
            });
        }
        $cb->({ items => \@items });
    });
}

sub _parseVGMRipsPackPage {
    my ($html) = @_;
    return () unless $html;
    my $packTitle = '';
    if ($html =~ /<section>\s*<h1>(.*?)<\/h1>/is) {
        $packTitle = stripTags($1);
    }
    my $img = '';
    if ($html =~ /<div\s+class=["']image["'][^>]*>.*?<img[^>]+src=["']([^"']+)["']/is) {
        $img = $1;
    }

    my @tracks;
    while ($html =~ /<tr[^>]+data-vgmurl=["']([^"']+)["'][^>]*>(.*?)<\/tr>/gis) {
        my $vgmUrl = $1;
        my $row    = $2;
        my $title  = '';
        if ($row =~ /<td\s+class=["']title["'][^>]*>(.*?)<\/td>/is) {
            $title = stripTags($1);
        }
        if (!length($title)) {
            $title = $vgmUrl;
            $title =~ s#^.*/##;
        }
        my $secs = 0;
        if ($row =~ /(\d+):(\d{2})/) {
            $secs = int($1) * 60 + int($2);
        }
        push @tracks, {
            url      => $vgmUrl,
            title    => $title,
            artist   => $packTitle,
            duration => $secs,
        };
    }
    return ($packTitle, $img, @tracks);
}

# ---------------------------------------------------------------------------
# 13. Khinsider Video Game Music (https://downloads.khinsider.com)
# ---------------------------------------------------------------------------

sub menuKhinsiderRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name      => 'Random Soundtrack Song Radio',
            type      => 'audio',
            url       => 'zxtune://radio/khinsider/title=Khinsider%20Random%20Radio',
            image     => ICON_DEFAULT,
            on_select => 'play',
        },
        {
            name  => 'Top Albums (Top 40 / New 100 / Favorites)',
            type  => 'link',
            url   => \&menuKhinsiderTop,
            image => ICON_DEFAULT,
        },
        {
            name        => 'Platforms',
            type        => 'link',
            url         => \&menuKhinsiderScopes,
            passthrough => [ { path => 'console-list' } ],
            image       => ICON_DEFAULT,
        },
        {
            name  => 'Albums By Letter (A-Z, #)',
            type  => 'link',
            url   => \&menuKhinsiderLetters,
            image => ICON_DEFAULT,
        },
        {
            name        => 'Albums By Year',
            type        => 'link',
            url         => \&menuKhinsiderScopes,
            passthrough => [ { path => 'album-years' } ],
            image       => ICON_DEFAULT,
        },
        {
            name  => 'Search Soundtracks',
            type  => 'search',
            url   => \&menuKhinsiderSearch,
            image => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuKhinsiderTop {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name        => 'Weekly Top 40',
            type        => 'link',
            url         => \&menuKhinsiderAlbums,
            passthrough => [ { scope => 'top40', page => 1 } ],
        },
        {
            name        => 'Top 100 Newly Added',
            type        => 'link',
            url         => \&menuKhinsiderAlbums,
            passthrough => [ { scope => 'top-100-newly-added', page => 1 } ],
        },
        {
            name        => 'Most Favorites',
            type        => 'link',
            url         => \&menuKhinsiderAlbums,
            passthrough => [ { scope => 'most-favorites', page => 1 } ],
        },
    );
    $cb->({ items => \@items });
}

sub menuKhinsiderLetters {
    my ($client, $cb, $args) = @_;
    my @items;
    for my $l ('0-9', 'A' .. 'Z') {
        push @items, {
            name        => ($l eq '0-9') ? '#' : $l,
            type        => 'link',
            url         => \&menuKhinsiderAlbums,
            passthrough => [ { scope => "game-soundtracks/browse/$l", page => 1 } ],
        };
    }
    $cb->({ items => \@items });
}

sub menuKhinsiderScopes {
    my ($client, $cb, $args, $pt) = @_;
    my $path = $pt->{path};
    fetchUrl("https://downloads.khinsider.com/$path", sub {
        my ($html, $err) = @_;
        my @items;
        if ($html && $html =~ /<div\s+id=["']pageContent["'][^>]*>(.*?)<\/div>/is) {
            my $body = $1;
            while ($body =~ /<a\s+href=["']\/?([^"']+)["'][^>]*>([^<]+)<\/a>/gis) {
                my ($scope, $title) = ($1, stripTags($2));
                next unless length($scope) && length($title);
                push @items, {
                    name        => $title,
                    type        => 'link',
                    url         => \&menuKhinsiderAlbums,
                    passthrough => [ { scope => $scope, page => 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuKhinsiderSearch {
    my ($client, $cb, $args) = @_;
    my $q = uri_escape($args->{search} || '');
    return menuKhinsiderAlbums($client, $cb, $args, { scope => "search?search=$q", page => 1 });
}

sub menuKhinsiderAlbums {
    my ($client, $cb, $args, $pt) = @_;
    my $scope = $pt->{scope};
    my $page  = int($pt->{page} || 1);
    my $sep   = ($scope =~ /\?/) ? '&' : '?';
    my $u     = "https://downloads.khinsider.com/$scope" . ($page > 1 ? "${sep}page=$page" : '');

    fetchUrl($u, sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            # If search redirected straight to a single album page with a songlist
            if ($html =~ /<table\s+id=["']songlist["']/i) {
                my ($albumId, $albumTitle, $img, @tracks) = _parseKhinsiderAlbumPage($html);
                if (@tracks && $albumId) {
                    return menuKhinsiderAlbumTracks($client, $cb, $args, { id => $albumId, title => $albumTitle, icon => $img });
                }
            }

            my %seen;
            # First extract rich album rows with cover thumbnails
            while ($html =~ /<tr[^>]*>(?:(?!<\/tr>).)*?<td\s+class=["']albumIcon["'][^>]*>(.*?)<\/tr>/gis) {
                my $row = $1;
                my $img = ICON_DEFAULT;
                if ($row =~ /<img[^>]+src=["']([^"']+)["']/i) {
                    $img = $1;
                    $img =~ s/\/thumbs_small\//\//;
                    $img = "https://downloads.khinsider.com$img" if $img =~ /^\//;
                }
                if ($row =~ /<a\s+href=["']\/game-soundtracks\/album\/([^"'\/]+)["'][^>]*>([^<]+)<\/a>(.*)/is) {
                    my ($id, $title, $rest) = ($1, stripTags($2), $3);
                    next if !$title || $seen{$id}++;
                    my @details;
                    while ($rest =~ /<td[^>]*>(.*?)<\/td>/gis) {
                        my $d = stripTags($1);
                        push @details, $d if length $d;
                    }
                    my $sub = join(' | ', @details);
                    push @items, {
                        name        => length($sub) ? "$title ($sub)" : $title,
                        line1       => $title,
                        line2       => $sub,
                        type        => 'link',
                        url         => \&menuKhinsiderAlbumTracks,
                        image       => $img,
                        passthrough => [ { id => $id, title => $title, icon => $img } ],
                    };
                }
            }
            # Fallback for plain anchor album lists
            while ($html =~ /<a\s+href=["']\/game-soundtracks\/album\/([^"'\/]+)["'][^>]*>([^<]+)<\/a>/gis) {
                my ($id, $title) = ($1, stripTags($2));
                next if !$title || $seen{$id}++;
                push @items, {
                    name        => $title,
                    type        => 'link',
                    url         => \&menuKhinsiderAlbumTracks,
                    image       => ICON_DEFAULT,
                    passthrough => [ { id => $id, title => $title } ],
                };
            }
            if ($html =~ /page=(\d+)/i && scalar(@items) >= 30) {
                push @items, {
                    name        => "Next Page (" . ($page + 1) . ") ->",
                    type        => 'link',
                    url         => \&menuKhinsiderAlbums,
                    passthrough => [ { scope => $scope, page => $page + 1 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuKhinsiderAlbumTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $id = $pt->{id};
    fetchUrl("https://downloads.khinsider.com/game-soundtracks/album/$id", sub {
        my ($html, $err) = @_;
        my ($albumId, $albumTitle, $img, @tracks) = _parseKhinsiderAlbumPage($html, $id, $pt->{title});
        $img ||= $pt->{icon} || ICON_DEFAULT;

        my @items = makeFavoriteToggleItem({
            id          => "khinsider:$albumId",
            title       => $albumTitle,
            cat         => 'Khinsider',
            handler     => 'khinsider_album',
            pt          => { id => $albumId, title => $albumTitle, icon => $img },
            icon        => $img,
            justToggled => $pt->{_favJustToggled},
        });
        my $idx = 1;
        for my $t (@tracks) {
            push @items, makeTrackItem({
                title     => sprintf("%02d. %s", $idx++, $t->{title}),
                artist    => $albumTitle,
                album     => $albumTitle,
                resolve   => 'khinsider',
                res_album => $albumId,
                res_id    => $t->{id},
                duration  => $t->{duration},
                icon      => $img,
                desc      => $t->{size},
            });
        }
        $cb->({ items => \@items });
    });
}

sub _parseKhinsiderAlbumPage {
    my ($html, $fallbackId, $fallbackTitle) = @_;
    return () unless $html;

    my $albumId = $fallbackId || '';
    if ($html =~ /href=["']\/game-soundtracks\/album\/([^"'\/]+)\//i) {
        $albumId = $1;
    }
    my $albumTitle = $fallbackTitle || $albumId;
    if ($html =~ /<div\s+id=["']pageContent["'][^>]*>.*?<h2>(.*?)<\/h2>/is) {
        $albumTitle = stripTags($1) || $albumTitle;
    }
    my $img = '';
    if ($html =~ /<div\s+class=["']albumImage["'][^>]*>\s*<a\s+href=["']([^"']+)["']/is) {
        $img = $1;
        $img = "https://downloads.khinsider.com$img" if $img =~ /^\//;
    }

    my @tracks;
    if ($html =~ /<table\s+id=["']songlist["'][^>]*>(.*?)<\/table>/is) {
        my $tbl = $1;
        my %seenHref;
        while ($tbl =~ /<tr[^>]*>(.*?)<\/tr>/gis) {
            my $row = $1;
            my @links;
            while ($row =~ /<a[^>]+href=["']([^"']*\/game-soundtracks\/album\/[^"'\/]+\/[^"']+)["'][^>]*>(.*?)<\/a>/gis) {
                push @links, [ $1, stripTags($2) ];
            }
            next unless @links;
            my $href = $links[0]->[0];
            $href =~ s/^https?:\/\/[^\/]+//i;
            next if $seenHref{$href}++;

            my $title = '';
            my $dur   = '';
            my @sizes;

            for my $lnk (@links) {
                my $txt = $lnk->[1];
                next unless defined $txt && length $txt;
                if ($txt =~ /^(?:(\d+):)?(\d+):(\d{2})$/) {
                    $dur ||= $txt;
                } elsif ($txt =~ /^\d+(?:[.,]\d+)?\s*[KMGB]{1,2}$/i) {
                    push @sizes, $txt;
                } elsif ($txt !~ /^(?:get_app|play_arrow|download)$/i && !length($title)) {
                    $title = $txt;
                }
            }

            if (!length($title)) {
                my $fallback = $href;
                $fallback =~ s#^.*/##;
                $fallback = uri_unescape(uri_unescape($fallback));
                $fallback =~ s/\.[^.]+$//;
                $title = $fallback;
            }

            my $secs = 0;
            if ($dur =~ /^(?:(\d+):)?(\d+):(\d+)/) {
                $secs = (defined $1 ? int($1) * 3600 : 0) + int($2) * 60 + int($3);
            }

            # Store exact $href path from Khinsider's table so _resolveKhinsiderTrack hits the exact double-encoded track page URL
            push @tracks, {
                id       => $href,
                title    => $title,
                duration => $secs,
                size     => join(' / ', @sizes),
            };
        }
    }
    return ($albumId, $albumTitle, $img, @tracks);
}

# ---------------------------------------------------------------------------
# 14. OverClocked ReMix - OCReMix (https://ocremix.org)
# ---------------------------------------------------------------------------

sub menuOCRemixRoot {
    my ($client, $cb, $args) = @_;
    my @items = (
        {
            name  => 'Systems',
            type  => 'link',
            url   => \&menuOCRemixSystems,
            image => ICON_DEFAULT,
        },
        {
            name        => 'Games (With Chiptunes & Remixes)',
            type        => 'link',
            url         => \&menuOCRemixGames,
            passthrough => [ { path => 'games/', offset => 0 } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Latest Remixes',
            type        => 'link',
            url         => \&menuOCRemixRemixes,
            passthrough => [ { path => 'remixes/', offset => 0 } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Albums',
            type        => 'link',
            url         => \&menuOCRemixAlbums,
            passthrough => [ { path => 'albums/', offset => 0 } ],
            image       => ICON_DEFAULT,
        },
        {
            name        => 'Organizations',
            type        => 'link',
            url         => \&menuOCRemixOrgs,
            passthrough => [ { offset => 0 } ],
            image       => ICON_DEFAULT,
        },
    );
    $cb->({ items => \@items });
}

sub menuOCRemixSystems {
    my ($client, $cb, $args) = @_;
    fetchUrl('https://ocremix.org/systems', sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']\/system\/([^"'\/]+)["'][^>]*>([^<\s][^<]*)<\/a>/gis) {
                my ($id, $name) = ($1, stripTags($2));
                next if !$name || $seen{$id}++;
                push @items, {
                    name        => $name,
                    type        => 'link',
                    url         => \&menuOCRemixGames,
                    passthrough => [ { path => "system/$id/games/", offset => 0 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuOCRemixOrgs {
    my ($client, $cb, $args, $pt) = @_;
    my $offset = int($pt->{offset} || 0);
    fetchUrl("https://ocremix.org/organizations/?sort=gamecountdesc&offset=$offset", sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']\/org\/([^"'\/]+)["'][^>]*>([^<\s][^<]*)<\/a>/gis) {
                my ($id, $name) = ($1, stripTags($2));
                next if !$name || $seen{$id}++;
                push @items, {
                    name        => $name,
                    type        => 'link',
                    url         => \&menuOCRemixGames,
                    passthrough => [ { path => "org/$id/games/", offset => 0 } ],
                };
            }
            if (scalar(@items) >= 25) {
                push @items, {
                    name        => "Next Page (" . ($offset + 50) . ") ->",
                    type        => 'link',
                    url         => \&menuOCRemixOrgs,
                    passthrough => [ { offset => $offset + 50 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuOCRemixGames {
    my ($client, $cb, $args, $pt) = @_;
    my $path   = $pt->{path} || 'games/';
    my $offset = int($pt->{offset} || 0);
    fetchUrl("https://ocremix.org/$path?offset=$offset", sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']\/game\/([^"'\/]+)["'][^>]*>([^<\s][^<]*)<\/a>/gis) {
                my ($id, $name) = ($1, stripTags($2));
                next if !$name || $seen{$id}++;
                push @items, {
                    name        => $name,
                    type        => 'link',
                    url         => \&menuOCRemixGameDetail,
                    passthrough => [ { id => $id, name => $name } ],
                };
            }
            if (scalar(@items) >= 25) {
                push @items, {
                    name        => "Next Page (" . ($offset + 50) . ") ->",
                    type        => 'link',
                    url         => \&menuOCRemixGames,
                    passthrough => [ { path => $path, offset => $offset + 50 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuOCRemixGameDetail {
    my ($client, $cb, $args, $pt) = @_;
    my $id   = $pt->{id};
    my $name = $pt->{name} || "Game #$id";
    fetchUrl("https://ocremix.org/game/$id", sub {
        my ($html, $err) = @_;
        my @items = makeFavoriteToggleItem({
            id          => "ocremix_game:$id",
            title       => "$name (OCReMix Game)",
            cat         => 'OCReMix',
            handler     => 'ocremix_game',
            pt          => { id => $id, name => $name },
            icon        => ICON_DEFAULT,
            justToggled => $pt->{_favJustToggled},
        });
        if ($html && $html =~ /href=["']\/chip\/\d+["'][^>]*>(music\/chiptunes\/[^<]+)<\/a>/is) {
            my $chipPath = stripTags($1);
            my $ext = ($chipPath =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : 'rsn';
            push @items, makeTrackItem({
                title  => "$name - Original Chiptune Archive ($chipPath)",
                artist => $name,
                album  => 'OCReMix Chiptunes',
                url    => "https://ocrmirror.org/files/$chipPath",
                ext    => $ext,
            });
        }
        push @items, {
            name        => "$name - Remixes",
            type        => 'link',
            url         => \&menuOCRemixRemixes,
            passthrough => [ { path => "game/$id/remixes", offset => 0 } ],
        };
        $cb->({ items => \@items });
    });
}

sub menuOCRemixRemixes {
    my ($client, $cb, $args, $pt) = @_;
    my $path   = $pt->{path} || 'remixes/';
    my $offset = int($pt->{offset} || 0);
    fetchUrl("https://ocremix.org/$path?offset=$offset", sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']\/remix\/(OCR\d+)["'][^>]*>([^<]+)<\/a>/gis) {
                my ($id, $title) = ($1, stripTags($2));
                $title =~ s/^"|"$//g;
                next if !$title || $seen{$id}++;
                push @items, makeTrackItem({
                    title   => $title,
                    artist  => 'OverClocked ReMix',
                    album   => "OCReMix ($id)",
                    resolve => 'ocremix',
                    res_id  => $id,
                });
            }
            if (scalar(@items) >= 20) {
                push @items, {
                    name        => "Next Page (" . ($offset + 30) . ") ->",
                    type        => 'link',
                    url         => \&menuOCRemixRemixes,
                    passthrough => [ { path => $path, offset => $offset + 30 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuOCRemixAlbums {
    my ($client, $cb, $args, $pt) = @_;
    my $path   = $pt->{path} || 'albums/';
    my $offset = int($pt->{offset} || 0);
    fetchUrl("https://ocremix.org/$path?offset=$offset", sub {
        my ($html, $err) = @_;
        my @items;
        if ($html) {
            my %seen;
            while ($html =~ /<a\s+href=["']\/album\/([^"'\/]+)["'][^>]*>([^<\s][^<]*)<\/a>/gis) {
                my ($id, $title) = ($1, stripTags($2));
                next if !$title || $seen{$id}++;
                push @items, {
                    name        => $title,
                    type        => 'link',
                    url         => \&menuOCRemixAlbumTracks,
                    passthrough => [ { id => $id, title => $title } ],
                };
            }
            if (scalar(@items) >= 20) {
                push @items, {
                    name        => "Next Page (" . ($offset + 50) . ") ->",
                    type        => 'link',
                    url         => \&menuOCRemixAlbums,
                    passthrough => [ { path => $path, offset => $offset + 50 } ],
                };
            }
        }
        $cb->({ items => \@items });
    });
}

sub menuOCRemixAlbumTracks {
    my ($client, $cb, $args, $pt) = @_;
    my $id    = $pt->{id};
    my $title = $pt->{title} || "Album #$id";
    fetchUrl("https://ocremix.org/album/$id", sub {
        my ($html, $err) = @_;
        if (!$html || $html !~ /href=["'](https?:\/\/bt\.ocremix\.org\/[^"']+\.torrent)["']/i) {
            return $cb->({ items => [ { name => 'No direct/torrent tracklist found for this album', type => 'text' } ] });
        }
        my $torrentUrl = $1;
        fetchUrl($torrentUrl, sub {
            my ($bdata, $terr) = @_;
            my @files = _parseTorrentFiles($bdata);
            my @items = makeFavoriteToggleItem({
                id          => "ocremix_album:$id",
                title       => "$title (OCReMix Album)",
                cat         => 'OCReMix Album',
                handler     => 'ocremix_album',
                pt          => { id => $id, title => $title },
                icon        => ICON_DEFAULT,
                justToggled => $pt->{_favJustToggled},
            });
            for my $f (@files) {
                next unless $f->{path} =~ /\.(mp3|flac|ogg|wav|spc|vgm|vgz|nsf|sid|mod|xm|it|s3m)$/i;
                my $ext = lc($1);
                my $fname = $f->{path};
                $fname =~ s#^.*/##;
                push @items, makeTrackItem({
                    title  => $fname,
                    artist => $title,
                    album  => $title,
                    url    => "https://ocrmirror.org/files/albums/$f->{path}",
                    ext    => $ext,
                    desc   => $f->{size} ? int($f->{size} / (1024 * 1024)) . ' MB' : '',
                });
            }
            $cb->({ items => \@items });
        });
    });
}

sub _parseTorrentFiles {
    my ($data) = @_;
    return () unless defined $data && length $data;
    my @out;
    my $rootName = '';
    if ($data =~ /4:name(\d+):/s) {
        my $len = int($1);
        my $pos = $+[0];
        $rootName = substr($data, $pos, $len);
    }
    while ($data =~ /6:lengthi(\d+)e.*?4:pathl(.*?)ee/gs) {
        my $size     = int($1);
        my $pathList = $2;
        my @parts;
        my $pos = 0;
        while ($pos < length($pathList) && substr($pathList, $pos) =~ /^(\d+):/s) {
            my $plen = int($1);
            $pos += length($1) + 1;
            push @parts, substr($pathList, $pos, $plen);
            $pos += $plen;
        }
        if (@parts) {
            my $rel = length($rootName) ? join('/', $rootName, @parts) : join('/', @parts);
            push @out, { path => $rel, size => $size };
        }
    }
    return @out;
}

# ---------------------------------------------------------------------------
# 15. Local Chiptunes & Multi-Track Archives Browser (With Auto Game Metadata & Cover Art)
# ---------------------------------------------------------------------------

sub _isSkippedLocalFile {
    my ($name) = @_;
    return 1 if !defined($name) || $name =~ /^\./;
    return 1 if $name =~ /\.(?:txt|nfo|diz|doc|pdf|htm|html|xml|json|cue|log|md5|sfv|ini|db|jpg|jpeg|png|gif|bmp|svg|ico|psf\d*lib|usflib|gsflib|2sflib|3sflib|ssflib|dsflib|ncflib|snsflib|m3u|m3u8|pls)$/i;
    return 0;
}

sub menuLocalRoots {
    my ($client, $cb, $args) = @_;
    my @dirs;

    my $savedDir = $prefs->get('local_music_dir') || '';
    if (length($savedDir) && -d $savedDir) {
        push @dirs, $savedDir;
    }

    my $mediaDirs = $serverPrefs->get('mediadirs');
    if (ref($mediaDirs) eq 'ARRAY') {
        for my $md (@$mediaDirs) {
            push @dirs, $md if $md && -d $md && !grep { $_ eq $md } @dirs;
        }
    }
    my $audioDir = $serverPrefs->get('audiodir');
    push @dirs, $audioDir if $audioDir && -d $audioDir && !grep { $_ eq $audioDir } @dirs;

    for my $d ('/var/music', '/media', '/mnt', '/storage') {
        if (-d $d && !grep { $_ eq $d } @dirs) {
            push @dirs, $d;
        }
    }

    my @items;
    for my $d (@dirs) {
        next unless defined $d && -d $d;
        my $isDefault = (length($savedDir) && $d eq $savedDir) ? ' [Default Chiptunes Folder]' : '';
        push @items, {
            name        => "$d$isDefault",
            type        => 'link',
            url         => \&menuLocalDir,
            passthrough => [ { dir => $d } ],
            image       => ICON_DEFAULT,
        };
    }

    if (!@items) {
        push @items, { name => 'No local music directories configured', type => 'text' };
    }
    $cb->({ items => \@items });
}

sub menuSetDefaultLocalDir {
    my ($client, $cb, $args, $pt) = @_;
    my $dir = $pt->{dir} || '';
    if (length($dir) && -d $dir) {
        $prefs->set('local_music_dir', $dir);
        $prefs->savenow();
    }
    return menuLocalDir($client, $cb, $args, { dir => $dir, justSaved => 1 });
}

sub menuLocalDir {
    my ($client, $cb, $args, $pt) = @_;
    my $dir = $pt->{dir};
    my $dh;
    if (!$dir || !-d $dir || !opendir($dh, $dir)) {
        return $cb->({ items => [ { name => "Cannot open directory: " . ($dir || ''), type => 'text' } ] });
    }

    my @entries = grep { !/^\./ } readdir($dh);
    closedir($dh);
    @entries = sort { lc($a) cmp lc($b) } @entries;

    my (@subdirPaths, @files);
    for my $e (@entries) {
        my $fp = File::Spec->catfile($dir, $e);
        if (-d $fp) {
            push @subdirPaths, $fp;
        } elsif (-f $fp && !_isSkippedLocalFile($e)) {
            push @files, $fp;
        }
    }

    # Pre-warm online metadata & cover art for up to 6 uncached game folders/archives in this view
    my @uncachedTargets;
    for my $p (@subdirPaths, @files) {
        last if scalar(@uncachedTargets) >= 6;
        my $bn = basename($p);
        next if $bn =~ /^(?:music|chiptunes?|vgm|spc|nsf|sid|mods?|storage|media|mnt|var|\d{1,3}[\s\.\-_])/i;
        my $m = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($p);
        if (!$m->{isCached}) {
            push @uncachedTargets, $p;
        }
    }

    my $buildAndReturnMenu = sub {
        my @items;
        my $savedDir = $prefs->get('local_music_dir') || '';
        my $dirMeta  = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($dir);
        my $dirCover = ($dirMeta && $dirMeta->{cover}) ? $dirMeta->{cover} : ICON_DEFAULT;

        if ($pt->{justSaved}) {
            push @items, {
                name => "Saved '$dir' as Default Local Chiptunes Folder!",
                type => 'text',
            };
        }

        # Recursive "All Tracks in Folder & Subfolders" option whenever there are subfolders or files
        if (@subdirPaths || @files) {
            push @items, {
                name        => '>> All Tracks in This Folder & Subfolders (Play All) <<',
                type        => 'link',
                url         => \&menuLocalDirRecursive,
                passthrough => [ { dir => $dir } ],
                image       => $dirCover,
            };
        }

        # Option to set current directory as default chiptunes folder with one click
        if ($savedDir ne $dir) {
            push @items, {
                name        => "[Set '" . (basename($dir) || $dir) . "' as Default Chiptunes Folder]",
                type        => 'link',
                url         => \&menuSetDefaultLocalDir,
                passthrough => [ { dir => $dir } ],
                image       => ICON_DEFAULT,
            };
        }

        # Render subfolders with automatic Game Title, Platform/Year & Cover Art
        for my $sd (@subdirPaths) {
            my $e    = basename($sd);
            my $meta = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($sd);
            my $cov  = ($meta && $meta->{cover}) ? $meta->{cover} : ICON_DEFAULT;
            my $info = join(' | ', grep { defined $_ && length $_ } ($meta->{platform}, $meta->{year}, $meta->{artist}));
            my $disp = length($info) ? "[Folder] $meta->{gameTitle} ($info)" : "[Folder] $e";

            push @items, {
                name        => $disp,
                line1       => "[Folder] " . ($meta->{gameTitle} || $e),
                line2       => $info || 'Local Game Folder',
                type        => 'link',
                url         => \&menuLocalDir,
                passthrough => [ { dir => $sd } ],
                image       => $cov,
            };
        }

        my $unpack = $prefs->get('unpack_archives') // 1;
        for my $fp (@files) {
            my $name = basename($fp);
            my $ext  = ($name =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : '';
            my $meta = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($fp);
            my $cov  = ($meta && $meta->{cover}) ? $meta->{cover} : $dirCover;
            my $info = join(' | ', grep { defined $_ && length $_ } ($meta->{platform}, $meta->{year}, $meta->{artist}));

            if ($unpack && isContainerExtension($ext)) {
                my $cleanTitle = $meta->{gameTitle} || $name;
                my $label      = length($info) ? "$cleanTitle [$info]" : "$cleanTitle [Game Archive]";
                push @items, {
                    name        => $label,
                    line1       => $cleanTitle,
                    line2       => length($info) ? $info : "Multi-Track Game Archive ($name)",
                    type        => 'link',
                    url         => \&menuLocalArchive,
                    passthrough => [ { file => $fp } ],
                    image       => $cov,
                };
            } else {
                my $trackTitle = $meta->{trackTitle} || $name;
                my $artist     = $meta->{artist} || $dirMeta->{artist} || $meta->{gameTitle} || basename($dir);
                my $album      = $meta->{gameTitle} || $dirMeta->{gameTitle} || basename($dir);

                my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
                    file   => $fp,
                    title  => $trackTitle,
                    artist => $artist,
                    album  => $album,
                    type   => $meta->{platform} || '',
                    icon   => ($cov ne ICON_DEFAULT) ? $cov : '',
                });
                push @items, {
                    name      => length($info) ? "$trackTitle ($info)" : $trackTitle,
                    line1     => $trackTitle,
                    line2     => join(' | ', grep { defined $_ && length $_ } ($artist, $album, $meta->{platform}, $meta->{year})),
                    type      => 'audio',
                    url       => $zxtUrl,
                    image     => $cov,
                    on_select => 'play',
                    playall   => 1,
                };
            }
        }

        # Always provide a way at the bottom to switch to another root drive / folder
        push @items, {
            name  => '[Browse All Drives / Change Root Folder]',
            type  => 'link',
            url   => \&menuLocalRoots,
            image => ICON_DEFAULT,
        };

        $cb->({ items => \@items });
    };

    if (!@uncachedTargets) {
        return $buildAndReturnMenu->();
    }

    my $remaining = scalar(@uncachedTargets);
    for my $target (@uncachedTargets) {
        Plugins::ZXTune::Metadata->resolveGameMetadata($target, sub {
            $remaining--;
            if ($remaining == 0) {
                $buildAndReturnMenu->();
            }
        });
    }
}

sub _collectFilesRecursive {
    my ($dir, $outRef, $depth) = @_;
    $depth ||= 0;
    return if $depth > 10 || scalar(@$outRef) >= 500;

    my $dh;
    opendir($dh, $dir) or return;
    my @entries = sort { lc($a) cmp lc($b) } grep { !/^\./ } readdir($dh);
    closedir($dh);

    my (@subdirs, @files);
    for my $e (@entries) {
        my $fp = File::Spec->catfile($dir, $e);
        if (-d $fp) {
            push @subdirs, $fp;
        } elsif (-f $fp && !_isSkippedLocalFile($e)) {
            push @files, $fp;
        }
    }

    for my $fp (@files) {
        push @$outRef, $fp;
        last if scalar(@$outRef) >= 500;
    }

    for my $sd (@subdirs) {
        last if scalar(@$outRef) >= 500;
        _collectFilesRecursive($sd, $outRef, $depth + 1);
    }
}

sub menuLocalDirRecursive {
    my ($client, $cb, $args, $pt) = @_;
    my $rootDir = $pt->{dir};
    if (!$rootDir || !-d $rootDir) {
        return $cb->({ items => [ { name => 'Directory not found', type => 'text' } ] });
    }

    my @allFiles;
    _collectFilesRecursive($rootDir, \@allFiles, 0);

    my @items;
    for my $fp (@allFiles) {
        my $name   = basename($fp);
        my $parent = basename(dirname($fp));
        my $meta   = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($fp);
        my $cov    = ($meta && $meta->{cover}) ? $meta->{cover} : ICON_DEFAULT;
        my $title  = $meta->{trackTitle} || $name;
        my $album  = $meta->{gameTitle}  || $parent;
        my $artist = $meta->{artist}     || $album;
        my $info   = join(' | ', grep { defined $_ && length $_ } ($artist, $album, $meta->{platform}, $meta->{year}));

        my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
            file   => $fp,
            title  => $title,
            artist => $artist,
            album  => $album,
            type   => $meta->{platform} || '',
            icon   => ($cov ne ICON_DEFAULT) ? $cov : '',
        });
        push @items, {
            name      => "$album - $title",
            line1     => $title,
            line2     => $info || $parent,
            type      => 'audio',
            url       => $zxtUrl,
            image     => $cov,
            on_select => 'play',
            playall   => 1,
        };
    }

    if (!@items) {
        push @items, { name => 'No chiptune files found in this folder or its subfolders', type => 'text' };
    }

    $cb->({ items => \@items });
}

sub menuLocalArchive {
    my ($client, $cb, $args, $pt) = @_;
    my $file = $pt->{file};

    Plugins::ZXTune::Metadata->resolveGameMetadata($file, sub {
        my ($gameMeta) = @_;
        my $cover     = ($gameMeta && $gameMeta->{cover})     ? $gameMeta->{cover}     : ICON_DEFAULT;
        my $cleanGame = ($gameMeta && $gameMeta->{gameTitle}) ? $gameMeta->{gameTitle} : basename($file);
        my $modules   = Plugins::ZXTune::Metadata->indexFile($file, $cleanGame);

        my @items = makeFavoriteToggleItem({
            id          => "local_archive:$file",
            title       => $cleanGame,
            cat         => ($gameMeta && $gameMeta->{platform}) ? "Local ($gameMeta->{platform})" : 'Local Game',
            handler     => 'local_archive',
            pt          => { file => $file },
            icon        => $cover,
            justToggled => $pt->{_favJustToggled},
        });

        if ($modules && @$modules) {
            for my $m (@$modules) {
                my $mArtist = ($m->{artist} && $m->{artist} ne 'Unknown Composer')
                            ? $m->{artist}
                            : (($gameMeta && $gameMeta->{artist}) || $cleanGame);
                my $mAlbum  = $m->{album} || $cleanGame;

                my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
                    file    => $file,
                    subpath => $m->{subpath},
                    title   => $m->{title},
                    artist  => $mArtist,
                    album   => $mAlbum,
                    type    => $m->{type} || ($gameMeta && $gameMeta->{platform}) || '',
                    icon    => ($cover ne ICON_DEFAULT) ? $cover : '',
                });
                my $desc = join(' | ', grep { defined $_ && length $_ } ($m->{type}, $gameMeta->{platform}, $gameMeta->{year}, $m->{subpath}));
                push @items, {
                    name      => sprintf("%02d. %s - %s%s", $m->{tracknum}, $mArtist, $m->{title}, length($desc) ? " ($desc)" : ""),
                    line1     => sprintf("%02d. %s", $m->{tracknum}, $m->{title}),
                    line2     => join(' | ', grep { defined $_ && length $_ } ($mArtist, $mAlbum, $desc)),
                    type      => 'audio',
                    url       => $zxtUrl,
                    image     => $cover,
                    on_select => 'play',
                    playall   => 1,
                };
            }
        } else {
            my $zxtUrl = Plugins::ZXTune::ProtocolHandler->buildZXTuneUrl('local', {
                file   => $file,
                title  => $cleanGame,
                artist => ($gameMeta && $gameMeta->{artist}) || $cleanGame,
                album  => $cleanGame,
                icon   => ($cover ne ICON_DEFAULT) ? $cover : '',
            });
            push @items, {
                name      => $cleanGame,
                type      => 'audio',
                url       => $zxtUrl,
                image     => $cover,
                on_select => 'play',
                playall   => 1,
            };
        }

        $cb->({ items => \@items });
    });
}

# ---------------------------------------------------------------------------
# 16. Global Search Across Search-Capable Catalogues
# ---------------------------------------------------------------------------

sub menuGlobalSearch {
    my ($client, $cb, $args) = @_;
    my $q = $args->{search} || '';

    my @items = (
        {
            name        => "Search ZX-Art.ee for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuZXArtSearch($c, $callback, $a);
            },
        },
        {
            name        => "Search The Mod Archive for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuModArchiveSearch($c, $callback, $a);
            },
        },
        {
            name        => "Search ZXTunes.com Authors for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuZXTunesSearch($c, $callback, $a);
            },
        },
        {
            name        => "Search Amiga Music Preservation (AMP) for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuAMPSearch($c, $callback, $a);
            },
        },
        {
            name        => "Search Aminet Modules for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuAminetSearch($c, $callback, $a);
            },
        },
        {
            name        => "Search Khinsider Soundtracks for '$q'",
            type        => 'link',
            url         => sub {
                my ($c, $callback, $a) = @_;
                $a->{search} = $q;
                menuKhinsiderSearch($c, $callback, $a);
            },
        },
    );

    $cb->({ items => \@items });
}

1;
