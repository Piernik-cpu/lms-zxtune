package Plugins::ZXTune::ProtocolHandler;

use strict;
use warnings;
use base qw(Slim::Player::Protocols::File);

use File::Spec;
use File::Path qw(make_path);
use Digest::SHA qw(sha1_hex);
use URI::Escape qw(uri_escape uri_unescape);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Networking::SimpleAsyncHTTP;

use Plugins::ZXTune::Metadata;

my $log         = logger('plugin.zxtune');
my $prefs       = preferences('plugin.zxtune');
my $serverPrefs = preferences('server');

my %META_CACHE;

sub init {
    Slim::Player::ProtocolHandlers->registerHandler(
        zxtune => __PACKAGE__
    );
}

# Return 0 so Slim::Player::Song::open uses the local transcoding pipeline (zxtune-play)
# after getNextTrack has downloaded any remote track to the local cache.
sub isRemote { 0 }

sub canDirectStream { 0 }

sub canSeek {
    my ($class, $client, $song) = @_;
    my $url = $song ? $song->track()->url() : '';
    return ($url =~ /^zxtune:\/\/radio\b/i) ? 0 : 1;
}

sub getSeekData {
    my ($class, $client, $song, $newtime) = @_;
    return { timeOffset => $newtime };
}

sub contentType { 'zxt' }

sub getFormatForURL { 'zxt' }

sub isAudioURL { 1 }

sub isRepeatingStream {
    my ($class, $song) = @_;
    my $url = ref($song) && $song->can('track') ? $song->track()->url() : ($song || '');
    return ($url =~ /^zxtune:\/\/radio\b/i) ? 1 : 0;
}

sub parseZXTuneUrl {
    my ($class, $url) = @_;
    return {} unless defined $url && $url =~ /^zxtune:\/\/(.*)$/i;
    my $rest = $1;
    my ($action, $query) = ('', '');
    if ($rest =~ /^([^?\/]*)\?(.*)$/) {
        $action = lc($1 || '');
        $query  = $2 // '';
    } elsif ($rest =~ /^([^\/]+)\/(.*)$/) {
        $action = lc($1 || '');
        $query  = $2 // '';
    } else {
        $action = lc($rest);
    }

    my %params = ( _action => $action );
    for my $pair (split(/[&;,~]/, $query)) {
        my ($k, $v) = split(/=/, $pair, 2);
        next unless defined $k && length $k;
        $params{uri_unescape($k)} = defined $v ? uri_unescape($v) : '';
    }
    return \%params;
}

# Build a shell-safe zxtune:// URL containing no '?', '&', ';', quotes, or spaces
sub buildZXTuneUrl {
    my ($class, $action, $params) = @_;
    my @pairs;
    for my $k (sort keys %{$params || {}}) {
        next if $k =~ /^_/;
        my $v = $params->{$k};
        next unless defined $v && length $v;
        my $ek = uri_escape($k, "^A-Za-z0-9\\-\\._");
        my $ev = uri_escape($v, "^A-Za-z0-9\\-\\._");
        push @pairs, "$ek=$ev";
    }
    return "zxtune://$action" . (@pairs ? '/' . join(',', @pairs) : '');
}

sub getCacheDir {
    my $base = $serverPrefs->get('cachedir') || '/tmp';
    my $dir  = File::Spec->catdir($base, 'zxtune_cache');
    if (!-d $dir) {
        eval { make_path($dir) };
    }
    return -d $dir ? $dir : '/tmp';
}

sub pruneCacheIfNeeded {
    my $dir      = getCacheDir();
    my $maxMb    = int($prefs->get('cache_max_mb') || 256);
    my $maxBytes = $maxMb * 1024 * 1024;

    opendir(my $dh, $dir) or return;
    my @files;
    my $total = 0;
    while (my $e = readdir($dh)) {
        next if $e =~ /^\./ || $e eq 'local_game_meta.tsv';
        my $fp = File::Spec->catfile($dir, $e);
        next unless -f $fp;
        my @st = stat($fp);
        my $sz = $st[7] || 0;
        my $mt = $st[9] || 0;
        $total += $sz;
        push @files, [ $fp, $sz, $mt ];
    }
    closedir($dh);

    return if $total <= $maxBytes;

    @files = sort { $a->[2] <=> $b->[2] } @files;
    for my $f (@files) {
        unlink($f->[0]);
        $total -= $f->[1];
        last if $total <= ($maxBytes * 0.8);
    }
}

sub _isHtmlErrorFile {
    my ($fp) = @_;
    return 1 unless $fp && -s $fp && (-s $fp) > 16;
    if (open(my $fh, '<', $fp)) {
        binmode($fh);
        my $head = '';
        read($fh, $head, 256);
        close($fh);
        return 1 if $head =~ /^\s*<(?:!DOCTYPE\s+html|html|head|body)\b/i;
    }
    return 0;
}

sub scanUrl {
    my ($class, $url, $args) = @_;
    my $cb     = $args->{cb};
    my $params = $class->parseZXTuneUrl($url);

    if ($params->{_action} eq 'local' && $params->{file} && -f $params->{file}) {
        my $secs = int($params->{duration} || 0);
        if (!$secs) {
            $secs = Plugins::ZXTune::Metadata->probeDuration($params->{file}, $params->{subpath});
        }
        if (my $track = Slim::Schema->objectForUrl({ url => $url, create => 1, readTags => 0 })) {
            $track->title($params->{title}) if $params->{title};
            $track->secs($secs) if $secs;
            $track->content_type('zxt');
            $track->update();
            $cb->($track) if $cb;
            return;
        }
    }

    $args->{cb}->($args->{song}->currentTrack()) if $args->{cb} && $args->{song};
}

sub getNextTrack {
    my ($class, $song, $successCb, $errorCb) = @_;
    my $url    = $song->currentTrack()->url();
    my $params = $class->parseZXTuneUrl($url);
    my $action = $params->{_action} || '';

    # 1. Local file or local container subsong
    if ($action eq 'local') {
        my $file    = $params->{file} || '';
        my $subpath = $params->{subpath} // '';
        $subpath = '' if $subpath =~ /^\[Subpath\]$/i;
        if (!-f $file) {
            $log->error("Local file not found: $file");
            return $errorCb->('File not found', $url);
        }
        my $secs = int($params->{duration} || 0);
        if (!$secs) {
            $secs = Plugins::ZXTune::Metadata->probeDuration($file, $subpath);
        }
        $song->duration($secs) if $secs;

        my $gameMeta = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($file);
        my $title    = $params->{title}  || $gameMeta->{trackTitle} || $gameMeta->{gameTitle} || 'Unknown Track';
        my $artist   = ($params->{artist} && $params->{artist} ne 'Unknown Composer')
                     ? $params->{artist}
                     : ($gameMeta->{artist} || $gameMeta->{gameTitle} || 'Unknown Composer');
        my $album    = $params->{album}  || $gameMeta->{gameTitle}  || 'ZXTune';
        if ($gameMeta->{platform} || $gameMeta->{year}) {
            my $suffix = join(', ', grep { defined $_ && length $_ } ($gameMeta->{platform}, $gameMeta->{year}));
            if (length($suffix) && index($album, $suffix) < 0) {
                $album = "$album [$suffix]";
            }
        }
        my $cover = ($params->{icon} && $params->{icon} ne 'plugins/ZXTune/html/images/icon.png')
                  ? $params->{icon}
                  : ($gameMeta->{cover} || 'plugins/ZXTune/html/images/icon.png');

        $META_CACHE{$url} = {
            title    => $title,
            artist   => $artist,
            album    => $album,
            duration => $secs,
            type     => $params->{type} || $gameMeta->{platform} || 'ZXTune',
            cover    => $cover,
        };

        # If cover art is not yet resolved for this local game, resolve it in the background and refresh UI
        if (!$gameMeta->{isCached} && $file !~ /zxtune_cache/) {
            Plugins::ZXTune::Metadata->resolveGameMetadata($file, sub {
                my ($resolved) = @_;
                return unless $resolved && $resolved->{cover};
                if (my $entry = $META_CACHE{$url}) {
                    $entry->{cover}  = $resolved->{cover};
                    $entry->{artist} = $resolved->{artist} if $resolved->{artist} && $entry->{artist} eq 'Unknown Composer';
                    if (my $client = $song->master()) {
                        $client->currentPlaylistUpdateTime(Time::HiRes::time());
                        Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
                    }
                }
            });
        }

        $song->streamUrl($url);
        return $successCb->();
    }

    # 2. Continuous Random Radio Stream
    if ($action =~ /^radio(?:\/(.+))?$/) {
        my $radioSource = $1 || $params->{source} || 'all';
        require Plugins::ZXTune::Catalogs;
        Plugins::ZXTune::Catalogs->fetchRandomRadioTrack($radioSource, sub {
            my ($trackInfo, $err) = @_;
            if (!$trackInfo || $err) {
                $log->warn("Radio fetch failed ($radioSource): " . ($err || 'no track'));
                return $errorCb->($err || 'Radio stream unavailable', $url);
            }
            $class->_resolveAndCacheTrack($song, $url, $trackInfo, $successCb, $errorCb);
        });
        return;
    }

    # 3. Remote Catalogue Track
    $class->_resolveAndCacheTrack($song, $url, $params, $successCb, $errorCb);
}

sub _resolveAndCacheTrack {
    my ($class, $song, $origUrl, $params, $successCb, $errorCb) = @_;

    # Check if dynamic URL resolution is needed first (e.g. Khinsider track page or OCReMix remix page)
    if ($params->{resolve} && !$params->{url}) {
        require Plugins::ZXTune::Catalogs;
        Plugins::ZXTune::Catalogs->resolveTrackDownload($params, sub {
            my ($resolvedUrl, $extraMeta) = @_;
            if (!$resolvedUrl) {
                return $errorCb->('Failed to resolve download URL', $origUrl);
            }
            $params->{url} = $resolvedUrl;
            if ($extraMeta && ref($extraMeta) eq 'HASH') {
                for my $k (keys %$extraMeta) {
                    $params->{$k} ||= $extraMeta->{$k};
                }
            }
            $class->_downloadToCache($song, $origUrl, $params, $successCb, $errorCb);
        });
        return;
    }

    $class->_downloadToCache($song, $origUrl, $params, $successCb, $errorCb);
}

# Shared helper used by both ProtocolHandler and Catalogs::menuRemoteArchive
sub downloadUrlToCache {
    my ($class, $rawUrls, $extHint, $cb) = @_;
    my @urls = grep { defined $_ && /^https?:\/\//i } (ref($rawUrls) eq 'ARRAY' ? @$rawUrls : split(/\|/, $rawUrls // ''));
    for my $u (@urls) {
        $u =~ s/^\s+|\s+$//g;
        $u =~ s/\s+/%20/g;
    }

    if (!@urls) {
        return $cb->(undef, 'No valid download URL');
    }

    my $ext = $extHint || '';
    if (!$ext && $urls[0] =~ /\.([a-zA-Z0-9]{2,8})(?:$|\?|#)/) {
        $ext = lc($1);
    }
    $ext = 'dat' if !$ext || $ext =~ /^(php|html|htm|asp)$/i;

    my $cacheHash = sha1_hex($urls[0]);
    my $cacheFile = File::Spec->catfile(getCacheDir(), "$cacheHash.$ext");

    if (-s $cacheFile && !_isHtmlErrorFile($cacheFile)) {
        return $cb->($cacheFile, undef);
    } elsif (-e $cacheFile) {
        unlink($cacheFile);
    }

    my $tryCurlFallback = sub {
        for my $u (@urls) {
            my $rc = system('curl', '-f', '-s', '-L', '-k', '--max-time', '60', '-A', 'ZXTune/5112 LMS/1.0', '-o', $cacheFile, $u);
            if ($rc != 0 || _isHtmlErrorFile($cacheFile)) {
                unlink($cacheFile) if -e $cacheFile;
                system('wget', '-q', '--no-check-certificate', '-T', '60', '-U', 'ZXTune/5112 LMS/1.0', '-O', $cacheFile, $u);
            }
            if (-s $cacheFile && !_isHtmlErrorFile($cacheFile)) {
                pruneCacheIfNeeded();
                return $cb->($cacheFile, undef);
            }
            unlink($cacheFile) if -e $cacheFile;
        }
        return $cb->(undef, 'Failed to download module from all mirrors');
    };

    my $tryDownload;
    $tryDownload = sub {
        my $idx = shift;
        if ($idx >= scalar(@urls)) {
            return $tryCurlFallback->();
        }
        my $targetUrl = $urls[$idx];
        $log->info("Downloading ZXTune module: $targetUrl");

        my $http = Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $response = shift;
                my $code     = $response && $response->can('code') ? ($response->code || 200) : 200;
                my $content  = $response ? $response->contentRef : undef;
                if ($code =~ /^2\d\d$/ && $content && length($$content) > 16 && $$content !~ /^\s*<(?:!DOCTYPE\s+html|html|head|body)\b/i) {
                    if (open(my $fh, '>', $cacheFile)) {
                        binmode($fh);
                        print $fh $$content;
                        close($fh);
                        pruneCacheIfNeeded();
                        return $cb->($cacheFile, undef);
                    }
                }
                $tryDownload->($idx + 1);
            },
            sub {
                my ($http, $err) = @_;
                $log->warn("Mirror failed ($targetUrl): $err");
                $tryDownload->($idx + 1);
            },
            {
                timeout => 30,
                cache   => 0,
            }
        );
        $http->get($targetUrl, 'User-Agent' => 'ZXTune/5112 LMS/1.0');
    };

    $tryDownload->(0);
}

sub _downloadToCache {
    my ($class, $song, $origUrl, $params, $successCb, $errorCb) = @_;

    $class->downloadUrlToCache($params->{url}, $params->{ext}, sub {
        my ($cacheFile, $err) = @_;
        if (!$cacheFile || $err) {
            return $errorCb->($err || 'Download failed', $origUrl);
        }
        $class->_finalizeCachedTrack($song, $origUrl, $cacheFile, $params, $successCb);
    });
}

sub _finalizeCachedTrack {
    my ($class, $song, $origUrl, $cacheFile, $params, $successCb) = @_;

    my $subpath = $params->{subpath} // '';
    $subpath = '' if $subpath =~ /^\[Subpath\]$/i;
    my $isStandardAudio = ($cacheFile =~ /\.(?:mp3|flac|ogg|wav|m4a)$/i) ? 1 : 0;

    my $picked;
    if (!$isStandardAudio) {
        my $modules = Plugins::ZXTune::Metadata->indexFile($cacheFile, $params->{title});
        if ($modules && @$modules) {
            if (length $subpath) {
                ($picked) = grep { $_->{subpath} eq $subpath } @$modules;
            }
            $picked ||= $modules->[0];
            $subpath = $picked->{subpath} // '' if !length($subpath);
        }
    }

    my $title  = $params->{title}  || ($picked && $picked->{title})  || 'Unknown Track';
    my $artist = $params->{artist} || ($picked && $picked->{artist}) || 'Unknown Composer';
    my $album  = $params->{album}  || ($picked && $picked->{album})  || 'ZXTune Online';
    my $type   = ($picked && $picked->{type}) ? "ZXTune ($picked->{type})" : 'ZXTune';
    my $secs   = int($params->{duration} || 0);
    if (!$secs) {
        $secs = Plugins::ZXTune::Metadata->probeDuration($cacheFile, $subpath);
    }

    $song->duration($secs) if $secs;

    $META_CACHE{$origUrl} = {
        title    => $title,
        artist   => $artist,
        album    => $album,
        duration => $secs,
        type     => $type,
        cover    => $params->{icon} || 'plugins/ZXTune/html/images/icon.png',
    };

    my $localStreamUrl = $class->buildZXTuneUrl('local', {
        file     => $cacheFile,
        subpath  => $subpath,
        title    => $title,
        artist   => $artist,
        album    => $album,
        duration => $secs,
        icon     => $params->{icon} || '',
    });

    $META_CACHE{$localStreamUrl} = $META_CACHE{$origUrl};
    $song->streamUrl($localStreamUrl);

    if (my $client = $song->master()) {
        Slim::Music::Info::setCurrentTitle($origUrl, "$artist - $title");
        $client->currentPlaylistUpdateTime(Time::HiRes::time());
        Slim::Control::Request::notifyFromArray($client, ['newmetadata']);
    }

    $successCb->();
}

sub getMetadataFor {
    my ($class, $client, $url) = @_;
    return {} unless $url;

    if (my $cached = $META_CACHE{$url}) {
        my $srate = int($prefs->get('samplerate') || 48000);
        return {
            title    => $cached->{title},
            artist   => $cached->{artist},
            album    => $cached->{album},
            duration => $cached->{duration},
            secs     => $cached->{duration},
            cover    => $cached->{cover} || 'plugins/ZXTune/html/images/icon.png',
            icon     => $cached->{cover} || 'plugins/ZXTune/html/images/icon.png',
            type     => $cached->{type}  || 'ZXTune Chiptune',
            bitrate  => int(($srate * 32) / 1000) . 'kbps PCM/FLAC',
            lossless => 1,
        };
    }

    my $params = $class->parseZXTuneUrl($url);
    my $title  = $params->{title}  || 'ZXTune Stream';
    my $artist = $params->{artist} || 'ZXTune';
    my $album  = $params->{album}  || 'ZXTune';
    my $secs   = int($params->{duration} || 0);
    my $icon   = $params->{icon}   || 'plugins/ZXTune/html/images/icon.png';

    if ($params->{_action} eq 'local' && $params->{file}) {
        my $gameMeta = Plugins::ZXTune::Metadata->getCachedOrLocalGameMeta($params->{file});
        if ($gameMeta->{cover} && $icon eq 'plugins/ZXTune/html/images/icon.png') {
            $icon = $gameMeta->{cover};
        }
        if ($gameMeta->{artist} && ($artist eq 'ZXTune' || $artist eq 'Unknown Composer')) {
            $artist = $gameMeta->{artist};
        }
        if ($gameMeta->{gameTitle} && $album eq 'ZXTune') {
            $album = $gameMeta->{gameTitle};
        }
    }

    return {
        title    => $title,
        artist   => $artist,
        album    => $album,
        duration => $secs || undef,
        secs     => $secs || undef,
        cover    => $icon,
        icon     => $icon,
        type     => 'ZXTune Chiptune',
        lossless => 1,
    };
}

1;
