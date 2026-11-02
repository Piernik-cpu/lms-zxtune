package Plugins::ZXTune::Metadata;

use strict;
use warnings;

use File::Spec;
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use URI::Escape qw(uri_escape uri_unescape);

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Formats;

my $log         = logger('plugin.zxtune');
my $prefs       = preferences('plugin.zxtune');
my $serverPrefs = preferences('server');

my $zxtuneBin;
my %INDEX_CACHE;
my %GAME_META_CACHE;
my $GAME_META_LOADED = 0;
my %PENDING_LOOKUPS;

use constant ICON_DEFAULT => 'plugins/ZXTune/html/images/icon.png';

# Map short platform tags & extensions to human-readable Platform Name and Libretro Thumbnail Repo
my %PLATFORM_MAP = (
    nes      => [ 'NES / Famicom',               'Nintendo - Nintendo Entertainment System' ],
    fc       => [ 'NES / Famicom',               'Nintendo - Nintendo Entertainment System' ],
    fds      => [ 'Famicom Disk System',         'Nintendo - Family Computer Disk System' ],
    nsf      => [ 'NES / Famicom',               'Nintendo - Nintendo Entertainment System' ],
    nsfe     => [ 'NES / Famicom',               'Nintendo - Nintendo Entertainment System' ],
    snes     => [ 'Super Nintendo (SNES)',       'Nintendo - Super Nintendo Entertainment System' ],
    sfc      => [ 'Super Nintendo (SNES)',       'Nintendo - Super Nintendo Entertainment System' ],
    spc      => [ 'Super Nintendo (SNES)',       'Nintendo - Super Nintendo Entertainment System' ],
    rsn      => [ 'Super Nintendo (SNES)',       'Nintendo - Super Nintendo Entertainment System' ],
    gb       => [ 'Game Boy',                    'Nintendo - Game Boy' ],
    gbc      => [ 'Game Boy Color',              'Nintendo - Game Boy Color' ],
    gbs      => [ 'Game Boy / GBC',              'Nintendo - Game Boy' ],
    gba      => [ 'Game Boy Advance',            'Nintendo - Game Boy Advance' ],
    gsf      => [ 'Game Boy Advance',            'Nintendo - Game Boy Advance' ],
    minigsf  => [ 'Game Boy Advance',            'Nintendo - Game Boy Advance' ],
    n64      => [ 'Nintendo 64',                 'Nintendo - Nintendo 64' ],
    usf      => [ 'Nintendo 64',                 'Nintendo - Nintendo 64' ],
    miniusf  => [ 'Nintendo 64',                 'Nintendo - Nintendo 64' ],
    nds      => [ 'Nintendo DS',                 'Nintendo - Nintendo DS' ],
    ds       => [ 'Nintendo DS',                 'Nintendo - Nintendo DS' ],
    '2sf'    => [ 'Nintendo DS',                 'Nintendo - Nintendo DS' ],
    mini2sf  => [ 'Nintendo DS',                 'Nintendo - Nintendo DS' ],
    '3ds'    => [ 'Nintendo 3DS',                'Nintendo - Nintendo 3DS' ],
    '3sf'    => [ 'Nintendo 3DS',                'Nintendo - Nintendo 3DS' ],
    mini3sf  => [ 'Nintendo 3DS',                'Nintendo - Nintendo 3DS' ],
    gcn      => [ 'Nintendo GameCube',           'Nintendo - GameCube' ],
    ngc      => [ 'Nintendo GameCube',           'Nintendo - GameCube' ],
    gc       => [ 'Nintendo GameCube',           'Nintendo - GameCube' ],
    wii      => [ 'Nintendo Wii',                'Nintendo - Wii' ],
    wiiu     => [ 'Nintendo Wii U',              'Nintendo - Wii U' ],
    switch   => [ 'Nintendo Switch',             'Nintendo - Switch' ],
    smd      => [ 'Sega Mega Drive / Genesis',   'Sega - Mega Drive - Genesis' ],
    md       => [ 'Sega Mega Drive / Genesis',   'Sega - Mega Drive - Genesis' ],
    gen      => [ 'Sega Genesis / Mega Drive',   'Sega - Mega Drive - Genesis' ],
    genesis  => [ 'Sega Genesis / Mega Drive',   'Sega - Mega Drive - Genesis' ],
    gym      => [ 'Sega Mega Drive / Genesis',   'Sega - Mega Drive - Genesis' ],
    vgm      => [ 'Video Game Music (VGM)',      'Sega - Mega Drive - Genesis' ],
    vgz      => [ 'Video Game Music (VGZ)',      'Sega - Mega Drive - Genesis' ],
    sms      => [ 'Sega Master System',          'Sega - Master System - Mark III' ],
    gg       => [ 'Sega Game Gear',              'Sega - Game Gear' ],
    kss      => [ 'MSX / Sega Master System',    'Microsoft - MSX' ],
    msx      => [ 'MSX / MSX2',                  'Microsoft - MSX' ],
    sat      => [ 'Sega Saturn',                 'Sega - Saturn' ],
    saturn   => [ 'Sega Saturn',                 'Sega - Saturn' ],
    ssf      => [ 'Sega Saturn',                 'Sega - Saturn' ],
    minissf  => [ 'Sega Saturn',                 'Sega - Saturn' ],
    dc       => [ 'Sega Dreamcast',              'Sega - Dreamcast' ],
    dsf      => [ 'Sega Dreamcast',              'Sega - Dreamcast' ],
    minidsf  => [ 'Sega Dreamcast',              'Sega - Dreamcast' ],
    pce      => [ 'PC Engine / TurboGrafx-16',   'NEC - PC Engine - TurboGrafx 16' ],
    tg16     => [ 'TurboGrafx-16 / PC Engine',   'NEC - PC Engine - TurboGrafx 16' ],
    hes      => [ 'PC Engine / TurboGrafx-16',   'NEC - PC Engine - TurboGrafx 16' ],
    ps1      => [ 'Sony PlayStation',            'Sony - PlayStation' ],
    psx      => [ 'Sony PlayStation',            'Sony - PlayStation' ],
    psf      => [ 'Sony PlayStation',            'Sony - PlayStation' ],
    minipsf  => [ 'Sony PlayStation',            'Sony - PlayStation' ],
    ps2      => [ 'Sony PlayStation 2',          'Sony - PlayStation 2' ],
    psf2     => [ 'Sony PlayStation 2',          'Sony - PlayStation 2' ],
    minipsf2 => [ 'Sony PlayStation 2',          'Sony - PlayStation 2' ],
    ps3      => [ 'Sony PlayStation 3',          'Sony - PlayStation 3' ],
    psf3     => [ 'Sony PlayStation 3',          'Sony - PlayStation 3' ],
    psp      => [ 'Sony PlayStation Portable',   'Sony - PlayStation Portable' ],
    vita     => [ 'Sony PlayStation Vita',       'Sony - PlayStation Vita' ],
    c64      => [ 'Commodore 64',                'Commodore - 64' ],
    sid      => [ 'Commodore 64 (SID)',          'Commodore - 64' ],
    psid     => [ 'Commodore 64 (SID)',          'Commodore - 64' ],
    rsid     => [ 'Commodore 64 (SID)',          'Commodore - 64' ],
    amiga    => [ 'Commodore Amiga',             'Commodore - Amiga' ],
    lha      => [ 'Commodore Amiga',             'Commodore - Amiga' ],
    atari    => [ 'Atari XL/XE / ST',            'Atari - 8-bit' ],
    sap      => [ 'Atari XL/XE (SAP)',           'Atari - 8-bit' ],
    sndh     => [ 'Atari ST (SNDH)',             'Atari - ST' ],
    ym       => [ 'Atari ST / ZX Spectrum (YM)', 'Atari - ST' ],
    zx       => [ 'ZX Spectrum',                 'Sinclair - ZX Spectrum' ],
    ay       => [ 'ZX Spectrum / Amstrad (AY)',  'Sinclair - ZX Spectrum' ],
    pt3      => [ 'ZX Spectrum (ProTracker 3)',  'Sinclair - ZX Spectrum' ],
    pt2      => [ 'ZX Spectrum (ProTracker 2)',  'Sinclair - ZX Spectrum' ],
    stc      => [ 'ZX Spectrum (Sound Tracker)', 'Sinclair - ZX Spectrum' ],
    vtx      => [ 'ZX Spectrum (Vortex)',        'Sinclair - ZX Spectrum' ],
    psg      => [ 'ZX Spectrum (PSG)',           'Sinclair - ZX Spectrum' ],
    s98      => [ 'NEC PC-88 / PC-98',           'NEC - PC-98' ],
    pc98     => [ 'NEC PC-98',                   'NEC - PC-98' ],
    pc88     => [ 'NEC PC-88',                   'NEC - PC-88' ],
    x68k     => [ 'Sharp X68000',                'Sharp - X68000' ],
    neogeo   => [ 'SNK Neo Geo',                 'SNK - Neo Geo' ],
    ngcd     => [ 'SNK Neo Geo CD',              'SNK - Neo Geo CD' ],
    '3do'    => [ '3DO Interactive Multiplayer', 'The 3DO Company - 3DO' ],
    xbox     => [ 'Microsoft Xbox',              'Microsoft - Xbox' ],
    x360     => [ 'Microsoft Xbox 360',          'Microsoft - Xbox 360' ],
    pc       => [ 'PC / DOS / Windows',          'DOS' ],
    dos      => [ 'PC / MS-DOS',                 'DOS' ],
);

sub init {
    my ($class, $pluginDir) = @_;

    my @binDirs = (
        File::Spec->catdir($pluginDir, 'Bin', 'x86_64-linux'),
        File::Spec->catdir($pluginDir, 'Bin', 'i386-linux'),
    );

    for my $dir (@binDirs) {
        next unless -d $dir;
        Slim::Utils::Misc::addFindBinPaths($dir);
        for my $exe ('zxtune123', 'zxtune-play') {
            my $p = File::Spec->catfile($dir, $exe);
            if (-f $p && !-x $p) {
                chmod 0755, $p;
            }
        }
    }

    $zxtuneBin = File::Spec->catfile($pluginDir, 'Bin', 'x86_64-linux', 'zxtune123');
    if (!-f $zxtuneBin) {
        $zxtuneBin = Slim::Utils::Misc::findbin('zxtune123');
    }

    # Register format tag reader for local library scanning
    $Slim::Formats::tagClasses{'zxt'} = __PACKAGE__;

    # Register raw HTTP handler to serve local cover art images from disk
    if (main::WEBUI) {
        eval {
            require Slim::Web::Pages;
            Slim::Web::Pages->addRawFunction('plugins/ZXTune/cover', \&handleCoverArtRequest);
        };
    }

    _loadGameMetaCache();
}

sub getBinaryPath {
    return $zxtuneBin;
}

# ---------------------------------------------------------------------------
# Persistent Disk Cache for Local Game Metadata & Cover Art
# ---------------------------------------------------------------------------

sub _getMetaCacheFile {
    my $base = $serverPrefs->get('cachedir') || '/tmp';
    my $dir  = File::Spec->catdir($base, 'zxtune_cache');
    if (!-d $dir) {
        eval { make_path($dir) };
    }
    return File::Spec->catfile(-d $dir ? $dir : '/tmp', 'local_game_meta.tsv');
}

sub _loadGameMetaCache {
    return if $GAME_META_LOADED;
    $GAME_META_LOADED = 1;
    my $f = _getMetaCacheFile();
    return unless -s $f && open(my $fh, '<', $f);
    while (my $line = <$fh>) {
        $line =~ s/[\r\n]+$//;
        next unless length $line;
        my ($key, $gameTitle, $artist, $platform, $year, $cover, $ts) = split(/\t/, $line, 7);
        next unless defined $key && length $key;
        $GAME_META_CACHE{$key} = {
            gameTitle => $gameTitle || '',
            artist    => $artist    || '',
            platform  => $platform  || '',
            year      => $year      || '',
            cover     => $cover     || '',
            ts        => int($ts    || time()),
        };
    }
    close($fh);
}

sub _saveGameMetaEntry {
    my ($key, $entry) = @_;
    return unless defined $key && length $key && ref($entry) eq 'HASH';
    _loadGameMetaCache();
    $entry->{ts} ||= time();
    $GAME_META_CACHE{$key} = $entry;

    my $f = _getMetaCacheFile();
    if (open(my $fh, '>', $f)) {
        for my $k (sort keys %GAME_META_CACHE) {
            my $e = $GAME_META_CACHE{$k};
            my @cols = map {
                my $v = $_ // '';
                $v =~ s/[\t\r\n]+/ /g;
                $v;
            } ($k, $e->{gameTitle}, $e->{artist}, $e->{platform}, $e->{year}, $e->{cover}, $e->{ts});
            print $fh join("\t", @cols) . "\n";
        }
        close($fh);
    }
}

# ---------------------------------------------------------------------------
# Local Cover Art HTTP Endpoint (/plugins/ZXTune/cover?file=...)
# ---------------------------------------------------------------------------

sub handleCoverArtRequest {
    my ($client, $params, $prepareResponseForSending, $httpClient, $response) = @_;

    my $filePath = $params->{file} || '';
    if (!$filePath && $response && $response->request && $response->request->uri) {
        my $uri = $response->request->uri->as_string;
        if ($uri =~ /[?&]file=([^&]+)/) {
            $filePath = uri_unescape($1);
        }
    }
    $filePath = uri_unescape($filePath) if $filePath =~ /%[0-9A-Fa-f]{2}/;

    if ($filePath && -f $filePath && $filePath =~ /\.(png|jpg|jpeg|gif|bmp|webp)$/i) {
        my $ext = lc($1);
        my $ct  = ($ext eq 'png')  ? 'image/png'
                : ($ext eq 'gif')  ? 'image/gif'
                : ($ext eq 'bmp')  ? 'image/bmp'
                : ($ext eq 'webp') ? 'image/webp'
                :                    'image/jpeg';

        if (open(my $fh, '<', $filePath)) {
            binmode($fh);
            local $/;
            my $data = <$fh>;
            close($fh);

            $response->code(200);
            $response->header('Content-Type'   => $ct);
            $response->header('Content-Length' => length($data));
            $response->header('Cache-Control'  => 'public, max-age=86400');
            return \$data;
        }
    }

    $response->code(404);
    $response->header('Content-Type' => 'text/plain');
    my $msg = 'Cover art not found';
    return \$msg;
}

sub findLocalCoverArt {
    my ($class, $path) = @_;
    return undef unless defined $path && length $path;

    my $dir      = (-d $path) ? $path : dirname($path);
    my $baseName = (-f $path) ? basename($path) : '';
    $baseName =~ s/\.[^.]+$//;

    # Clean baseName without tags as well
    my $cleanBase = $baseName;
    $cleanBase =~ s/\s*[\(\[][^\)\]]*[\)\]]//g;
    $cleanBase =~ s/^\s+|\s+$//g;

    my @candidateFiles;
    if (-d $dir) {
        for my $ext ('png', 'jpg', 'jpeg', 'gif') {
            if (length $baseName) {
                push @candidateFiles, File::Spec->catfile($dir, "$baseName.$ext");
            }
            if (length $cleanBase && $cleanBase ne $baseName) {
                push @candidateFiles, File::Spec->catfile($dir, "$cleanBase.$ext");
            }
            for my $cname ('cover', 'folder', 'front', 'box', 'title', 'artwork', 'album') {
                push @candidateFiles, File::Spec->catfile($dir, "$cname.$ext");
            }
        }
        for my $cand (@candidateFiles) {
            if (-f $cand && -s $cand) {
                return 'plugins/ZXTune/cover?file=' . uri_escape($cand);
            }
        }

        # If this is a dedicated game subfolder, check if there is any image file in it
        if (-d $path && opendir(my $dh, $path)) {
            my @imgs = sort grep { /\.(?:png|jpg|jpeg|gif)$/i && !/^\./ } readdir($dh);
            closedir($dh);
            if (@imgs) {
                my $firstImg = File::Spec->catfile($path, $imgs[0]);
                if (-f $firstImg && -s $firstImg) {
                    return 'plugins/ZXTune/cover?file=' . uri_escape($firstImg);
                }
            }
        }
    }

    return undef;
}

# ---------------------------------------------------------------------------
# Smart Game Filename / Folder Metadata Parser (TOSEC / JoshW / No-Intro)
# ---------------------------------------------------------------------------

sub parseGameNameAndMeta {
    my ($class, $path) = @_;
    return {} unless defined $path && length $path;

    my $isDir    = (-d $path) ? 1 : 0;
    my $name     = basename($path);
    my $parent   = basename(dirname($path));
    my $ext      = (!$isDir && $name =~ /\.([a-zA-Z0-9]+)$/) ? lc($1) : '';

    my $rawTitle = $name;
    $rawTitle =~ s/\.[^.]+$// unless $isDir;

    # If the file is an individual numbered track (e.g. "01 - Introduction.spc" or "05_Stage1.vgz")
    # inside a game folder, derive the game metadata from the parent folder name!
    my $trackTitle = '';
    if (!$isDir && $rawTitle =~ /^(?:\d{1,3}[\s\.\-_]+)+(.+)$/ && length($parent) && $parent !~ /^(?:music|chiptunes?|vgm|spc|nsf|sid|mods?|storage|media|mnt|var)$/i) {
        $trackTitle = $1;
        $rawTitle   = $parent;
    }

    my $year     = '';
    my $platform = '';
    my $libretro = '';
    my @companies;

    # 1. Extract bracketed tags [SNES], [1992], etc.
    while ($rawTitle =~ /\[([^\]]+)\]/g) {
        my $tag = $1;
        $tag =~ s/^\s+|\s+$//g;
        if ($tag =~ /^((?:19|20)\d{2})(?:-\d{2}(?:-\d{2})?)?$/) {
            $year ||= $1;
        } elsif ($PLATFORM_MAP{lc($tag)}) {
            $platform ||= $PLATFORM_MAP{lc($tag)}->[0];
            $libretro ||= $PLATFORM_MAP{lc($tag)}->[1];
        }
    }

    # 2. Extract parenthesized tags (1991-06-23)(Sega)(Ancient)
    while ($rawTitle =~ /\(([^\)]+)\)/g) {
        my $tag = $1;
        $tag =~ s/^\s+|\s+$//g;
        next if $tag =~ /^(?:!|-|v\d[\d\.]*|rev\s*\w+|beta|proto|demo|sample|usa|jpn|jap|eur|world|pal|ntsc|en|ja|de|fr|es|it|unl|hack|translated|alt|ost|soundtrack)$/i;
        if ($tag =~ /^((?:19|20)\d{2})(?:-\d{2}(?:-\d{2})?)?$/) {
            $year ||= $1;
        } elsif ($PLATFORM_MAP{lc($tag)}) {
            $platform ||= $PLATFORM_MAP{lc($tag)}->[0];
            $libretro ||= $PLATFORM_MAP{lc($tag)}->[1];
        } elsif (length($tag) >= 2 && $tag !~ /^\d+$/) {
            push @companies, $tag unless grep { lc($_) eq lc($tag) } @companies;
        }
    }

    # 3. Check parent folder or extension for platform if not yet identified
    if (!$platform && length($parent) && $PLATFORM_MAP{lc($parent)}) {
        $platform = $PLATFORM_MAP{lc($parent)}->[0];
        $libretro = $PLATFORM_MAP{lc($parent)}->[1];
    }
    if (!$platform && length($ext) && $PLATFORM_MAP{$ext}) {
        $platform = $PLATFORM_MAP{$ext}->[0];
        $libretro = $PLATFORM_MAP{$ext}->[1];
    }

    # 4. Clean game title
    my $gameTitle = $rawTitle;
    $gameTitle =~ s/\s*[\(\[][^\)\]]*[\)\]]//g;
    $gameTitle =~ s/_/ /g;
    $gameTitle =~ s/\s{2,}/ /g;
    $gameTitle =~ s/^\s+|\s+$//g;
    $gameTitle = $rawTitle if !length($gameTitle);

    my $company = join(' / ', @companies);

    return {
        gameTitle      => $gameTitle,
        trackTitle     => $trackTitle || $gameTitle,
        artist         => $company,
        platform       => $platform,
        libretroSystem => $libretro,
        year           => $year,
    };
}

# Synchronous helper: returns best currently known metadata & cover art (local or cached online)
sub getCachedOrLocalGameMeta {
    my ($class, $path) = @_;
    return {} unless defined $path && length $path;

    _loadGameMetaCache();
    my $parsed   = $class->parseGameNameAndMeta($path);
    my $localCov = $class->findLocalCoverArt($path);
    my $cacheKey = lc($parsed->{gameTitle} || '');

    my $cached = (length $cacheKey && exists $GAME_META_CACHE{$cacheKey}) ? $GAME_META_CACHE{$cacheKey} : undef;

    my $gameTitle = ($cached && length($cached->{gameTitle})) ? $cached->{gameTitle} : ($parsed->{gameTitle} || basename($path));
    my $artist    = $parsed->{artist}   || ($cached && $cached->{artist})   || '';
    my $platform  = $parsed->{platform} || ($cached && $cached->{platform}) || '';
    my $year      = $parsed->{year}     || ($cached && $cached->{year})     || '';
    my $cover     = $localCov           || ($cached && length($cached->{cover}) && $cached->{cover} ne 'NONE' ? $cached->{cover} : '') || '';

    return {
        gameTitle      => $gameTitle,
        trackTitle     => $parsed->{trackTitle} || $gameTitle,
        artist         => $artist,
        platform       => $platform,
        libretroSystem => $parsed->{libretroSystem} || '',
        year           => $year,
        cover          => $cover,
        isCached       => ($localCov || $cached) ? 1 : 0,
    };
}

# Asynchronous resolver: resolves local cover art / tags first, then queries Khinsider & Libretro Thumbnails
sub resolveGameMetadata {
    my ($class, $path, $cb) = @_;
    my $meta = $class->getCachedOrLocalGameMeta($path);

    my $onlineEnabled = $prefs->get('auto_online_cover') // 1;
    if ($meta->{cover} || $meta->{isCached} || !$onlineEnabled || !length($meta->{gameTitle})) {
        $meta->{cover} ||= ICON_DEFAULT;
        return $cb->($meta);
    }

    my $gameTitle = $meta->{gameTitle};
    my $cacheKey  = lc($gameTitle);

    # Avoid duplicate concurrent HTTP requests for the same game title
    if ($PENDING_LOOKUPS{$cacheKey}) {
        push @{$PENDING_LOOKUPS{$cacheKey}}, $cb;
        return;
    }
    $PENDING_LOOKUPS{$cacheKey} = [ $cb ];

    my $finish = sub {
        my ($finalMeta) = @_;
        _saveGameMetaEntry($cacheKey, {
            gameTitle => $finalMeta->{gameTitle} || $gameTitle,
            artist    => $finalMeta->{artist}    || '',
            platform  => $finalMeta->{platform}  || '',
            year      => $finalMeta->{year}      || '',
            cover     => $finalMeta->{cover}     || 'NONE',
        });
        $finalMeta->{cover} = ICON_DEFAULT if !$finalMeta->{cover} || $finalMeta->{cover} eq 'NONE';
        my $waiters = delete $PENDING_LOOKUPS{$cacheKey} || [];
        for my $w (@$waiters) {
            eval { $w->($finalMeta) };
        }
    };

    # Query Khinsider search for game cover art, platform, and year
    my $searchQ = $gameTitle;
    $searchQ =~ s/\s*-\s*.*$// if length($searchQ) > 28; # broaden overly specific subtitles if very long
    my $khUrl = 'https://downloads.khinsider.com/search?search=' . uri_escape($gameTitle);

    my $http = Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $res  = shift;
            my $html = $res ? $res->content : '';
            if ($html) {
                # Match rows with albumIcon thumbnail in Khinsider search results
                if ($html =~ /<td\s+class=["']albumIcon["'][^>]*>.*?<img[^>]+src=["']([^"']+)["'][^>]*>.*?<a\s+href=["']\/game-soundtracks\/album\/[^"']+["'][^>]*>([^<]+)<\/a>(.*?)<\/tr>/is) {
                    my ($thumbUrl, $foundTitle, $restRow) = ($1, $2, $3);
                    $thumbUrl =~ s/\/thumbs_small\//\//;
                    $thumbUrl = "https://downloads.khinsider.com$thumbUrl" if $thumbUrl =~ /^\//;
                    $meta->{cover} = $thumbUrl if $thumbUrl =~ /^https?:\/\//i;

                    my @tds;
                    while ($restRow =~ /<td[^>]*>(.*?)<\/td>/gis) {
                        my $txt = $1;
                        $txt =~ s/<[^>]*>//g;
                        $txt =~ s/^\s+|\s+$//g;
                        push @tds, $txt if length $txt;
                    }
                    if (@tds >= 1 && !$meta->{platform}) {
                        $meta->{platform} = $tds[0];
                    }
                    for my $td (@tds) {
                        if ($td =~ /^((?:19|20)\d{2})$/ && !$meta->{year}) {
                            $meta->{year} = $1;
                        }
                    }
                    return $finish->($meta) if $meta->{cover};
                }
                # If Khinsider redirected directly to an album page
                if ($html =~ /<div\s+class=["']albumImage["'][^>]*>\s*<a\s+href=["']([^"']+)["']/is) {
                    my $img = $1;
                    $img = "https://downloads.khinsider.com$img" if $img =~ /^\//;
                    $meta->{cover} = $img if $img =~ /^https?:\/\//i;
                    return $finish->($meta) if $meta->{cover};
                }
            }

            # Fallback: Libretro Thumbnails Boxart URL if platform is mapped
            if ($meta->{libretroSystem}) {
                my $safeName = $gameTitle;
                $safeName =~ s/[&*\/:`<>?\\|]/_/g;
                my $libUrl = 'https://thumbnails.libretro.com/'
                    . uri_escape($meta->{libretroSystem})
                    . '/Named_Boxarts/'
                    . uri_escape($safeName) . '.png';
                $meta->{cover} = $libUrl;
            }
            $finish->($meta);
        },
        sub {
            if ($meta->{libretroSystem}) {
                my $safeName = $gameTitle;
                $safeName =~ s/[&*\/:`<>?\\|]/_/g;
                $meta->{cover} = 'https://thumbnails.libretro.com/'
                    . uri_escape($meta->{libretroSystem})
                    . '/Named_Boxarts/'
                    . uri_escape($safeName) . '.png';
            }
            $finish->($meta);
        },
        {
            timeout => 6,
            cache   => 1,
        }
    );
    $http->get($khUrl, 'User-Agent' => 'ZXTune/5112 LMS/1.0');
}

# ---------------------------------------------------------------------------
# zxtune123 Module & Container Indexing
# ---------------------------------------------------------------------------

# Run zxtune123 --index on a file or archive and return arrayref of module hashrefs
sub indexFile {
    my ($class, $filePath, $fallbackName) = @_;
    return [] unless $filePath && -f $filePath && $zxtuneBin && -x $zxtuneBin;

    # Standard single-track audio files do not need zxtune123 container indexing
    if ($filePath =~ /\.(?:mp3|flac|ogg|wav|m4a)$/i) {
        return [];
    }

    my $mtime = (stat($filePath))[9] || 0;
    my $cacheKey = "$filePath|$mtime|" . ($fallbackName || '');
    if (exists $INDEX_CACHE{$cacheKey}) {
        return $INDEX_CACHE{$cacheKey};
    }

    # Limit cache growth
    if (scalar(keys %INDEX_CACHE) > 250) {
        %INDEX_CACHE = ();
    }

    my $tmpDir   = (-d '/dev/shm' && -w '/dev/shm') ? '/dev/shm' : '/tmp';
    my $idxFile  = File::Spec->catfile($tmpDir, "zxtune_idx_$$\_" . int(rand(100000)) . ".txt");
    my $csvTpl   = '[Subpath]|~|[Type]|~|[Container]|~|[Title]|~|[Author]|~|[Program]|~|[Computer]|~|[Date]|~|[Comment]|~|[Size]|~|[CRC]';
    my $confFile = '/tmp/zxtune_lms.conf';

    my @cmd = ($zxtuneBin, '--silent');
    if (-r $confFile) {
        push @cmd, ('--config', $confFile);
    }
    push @cmd, (
        '--core-options', 'zip.max_depacked_size_mb=512',
        '--providers-options', 'file.overwrite=1,file.sanitize_names=0',
        '--index', "filename=$idxFile,csv=$csvTpl",
        $filePath
    );

    system(@cmd);

    my $parsedGame = $class->parseGameNameAndMeta($fallbackName ? $fallbackName : $filePath);
    my $baseName   = $parsedGame->{gameTitle} || $fallbackName || basename($filePath);
    $baseName =~ s/\.[^.]+$//;

    my @modules;
    if (-s $idxFile && open(my $fh, '<', $idxFile)) {
        my $trackNum = 1;
        while (my $line = <$fh>) {
            $line =~ s/[\r\n]+$//;
            next unless length $line;
            # Skip the template header line written by zxtune123 CsvOutput
            next if $line =~ /^\[Subpath\]/i || $line eq $csvTpl;

            my ($subpath, $type, $container, $title, $author, $program, $computer, $date, $comment, $size, $crc)
                = split(/\|\~\|/, $line, 11);

            $subpath   //= '';
            $type      //= '';
            $container //= '';
            $title     //= '';
            $author    //= '';
            $program   //= '';
            $computer  //= '';
            $date      //= '';
            $comment   //= '';
            $size      //= 0;
            $crc       //= '';

            # Skip non-playable companion library/text files inside archives
            next if $subpath =~ /\.(?:psf\d*lib|usflib|gsflib|2sflib|3sflib|ssflib|dsflib|ncflib|snsflib|txt|nfo|diz|jpg|jpeg|png|gif|m3u|m3u8|pls|cue|log)$/i;

            # If baseName looks like a 40-char SHA1 cache hash and subpath has a filename, extract it
            my $displayBase = $baseName;
            if ($displayBase =~ /^[0-9a-f]{40}$/i && length($subpath)) {
                my $firstPart = $subpath;
                $firstPart =~ s/\/.*$//;
                $firstPart =~ s/\.[^.]+$//;
                $displayBase = $firstPart if length($firstPart) && $firstPart !~ /^#\d+$/;
            }

            if (!length($title)) {
                if (length($subpath)) {
                    my $spName = $subpath;
                    $spName =~ s#^.*/##;
                    $spName =~ s/\.(?:spc|vgm|vgz|nsf|nsfe|gbs|hes|kss|sid|sap|ay|pt3|stc|mod|xm|it|s3m|minipsf\d*|miniusf|minigsf|mini2sf|mini3sf|minissf|minidsf|s98|gym)$//i;
                    $spName =~ s/_/ /g;
                    if ($spName =~ /^#\d+$/) {
                        $title = "$displayBase ($spName)";
                    } else {
                        $title = $spName;
                    }
                } else {
                    $title = $parsedGame->{trackTitle} || $displayBase;
                }
            } elsif (length($subpath) && $subpath =~ /(#\d+)$/) {
                my $subNum = $1;
                if ($title eq $displayBase || $title eq $program) {
                    $title = "$title ($subNum)";
                }
            }

            my $resolvedArtist = length($author) ? $author : ($parsedGame->{artist} || $displayBase || 'Unknown Composer');
            my $resolvedAlbum  = (length($program) && $program !~ /^(?:unknown|none)$/i) ? $program : $displayBase;

            push @modules, {
                tracknum  => $trackNum++,
                file      => $filePath,
                subpath   => $subpath,
                type      => $type,
                container => $container,
                title     => $title,
                artist    => $resolvedArtist,
                album     => $resolvedAlbum,
                program   => $program || $parsedGame->{platform} || '',
                computer  => $computer || $parsedGame->{platform} || '',
                date      => $date || $parsedGame->{year} || '',
                comment   => $comment,
                size      => int($size || 0),
                crc       => $crc,
            };
        }
        close($fh);
    }
    unlink($idxFile) if -e $idxFile;

    $INDEX_CACHE{$cacheKey} = \@modules;
    return \@modules;
}

# Probe exact duration in seconds for a module or subsong without rendering the entire song
sub probeDuration {
    my ($class, $filePath, $subPath) = @_;
    my $defDur = int($prefs->get('default_duration') || 180);
    return $defDur unless $filePath && -f $filePath && $zxtuneBin && -x $zxtuneBin;

    $subPath = '' if defined $subPath && $subPath =~ /^\[Subpath\]$/i;
    my $spec = (defined $subPath && length $subPath) ? "$filePath?$subPath" : $filePath;
    my $secs = 0;

    my @cmd = (
        $zxtuneBin,
        '--quiet',
        '--core-options', 'zip.max_depacked_size_mb=512',
        '--null',
        $spec
    );

    my $pid = open(my $pipe, '-|', @cmd);
    if ($pid) {
        while (my $line = <$pipe>) {
            # Format: Time: M:SS.mmm	Loop duration: ...
            if ($line =~ /Time:\s*(?:(\d+):)?(\d+):(\d+)\.(\d+)/) {
                my $hr  = defined $1 ? int($1) : 0;
                my $min = int($2);
                my $sec = int($3);
                my $ms  = int($4);
                $secs = $hr * 3600 + $min * 60 + $sec + ($ms >= 500 ? 1 : 0);
                # Terminate zxtune123 immediately so we don't wait for null rendering of the whole track
                kill('TERM', $pid);
                kill('KILL', $pid);
                last;
            }
        }
        close($pipe);
    }

    return ($secs && $secs > 0) ? $secs : $defDur;
}

# LMS Slim::Formats tag reader interface for local library scanning
sub getTag {
    my ($class, $file) = @_;
    return {} unless $file && -f $file;

    my $gameMeta = $class->getCachedOrLocalGameMeta($file);
    my $modules  = $class->indexFile($file);
    my $first    = ($modules && @$modules) ? $modules->[0] : undef;

    my $title  = ($first && length($first->{title}))  ? $first->{title}  : ($gameMeta->{trackTitle} || $gameMeta->{gameTitle});
    my $artist = ($first && length($first->{artist})) ? $first->{artist} : ($gameMeta->{artist} || 'Unknown Composer');
    my $album  = ($first && length($first->{album}))  ? $first->{album}  : ($gameMeta->{gameTitle} || basename(dirname($file)));
    my $type   = ($first && length($first->{type}))   ? $first->{type}   : ($gameMeta->{platform} || 'ZXTune');
    my $sub    = ($first && defined $first->{subpath}) ? $first->{subpath} : '';
    my $secs   = $class->probeDuration($file, $sub);
    my $srate  = int($prefs->get('samplerate') || 48000);
    my $fsize  = -s $file || 0;

    my $tags = {
        TITLE        => $title,
        ARTIST       => $artist,
        ALBUM        => $album,
        COMMENT      => $first ? join(' | ', grep { defined $_ && length $_ } ($first->{type}, $first->{program}, $first->{computer}, $first->{comment})) : $type,
        TRACKNUM     => 1,
        SECS         => $secs,
        DURATION     => $secs,
        SAMPLERATE   => $srate,
        SAMPLESIZE   => 16,
        CHANNELS     => 2,
        LOSSLESS     => 1,
        BITRATE      => $srate * 2 * 16,
        FILESIZE     => $fsize,
        SIZE         => $fsize,
        CONTENT_TYPE => 'zxt',
    };

    my $yr = ($first && $first->{date}) ? $first->{date} : ($gameMeta->{year} || '');
    if ($yr && $yr =~ /(\d{4})/) {
        $tags->{YEAR} = int($1);
    }

    return $tags;
}

1;
