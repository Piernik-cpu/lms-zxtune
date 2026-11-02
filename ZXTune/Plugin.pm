package Plugins::ZXTune::Plugin;

# Logitech Media Server / Lyrion Music Server (Daphile) Plugin for ZXTune
# Full port of ZXTune (r5112) chiptune & videogame music player + 14 online catalogues

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(dirname);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

use Plugins::ZXTune::Settings;
use Plugins::ZXTune::Metadata;
use Plugins::ZXTune::ProtocolHandler;
use Plugins::ZXTune::Catalogs;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.zxtune',
    defaultLevel => 'INFO',
    description  => 'PLUGIN_ZXTUNE',
});

my $prefs = preferences('plugin.zxtune');

sub initPlugin {
    my $class = shift;

    my $pluginDir = dirname(__FILE__);

    # Ensure bundled helper binaries exist in LMS FindBin search paths and are executable
    my @binDirs = (
        catdir($pluginDir, 'Bin', 'x86_64-linux'),
        catdir($pluginDir, 'Bin', 'i386-linux'),
        catdir($pluginDir, 'Bin'),
    );

    for my $bdir (@binDirs) {
        if (-d $bdir) {
            eval { Slim::Utils::Misc::addFindBinPaths($bdir); };
            for my $bin ('zxtune123', 'zxtune-play') {
                my $full = catfile($bdir, $bin);
                if (-f $full && !-x $full) {
                    chmod(0755, $full);
                }
            }
        }
    }

    # Initialize Settings and generate /tmp/zxtune_lms.conf for zxtune123
    Plugins::ZXTune::Settings->init();
    if (main::WEBUI) {
        Plugins::ZXTune::Settings->new();
    }

    # Initialize local file format & container metadata scanner
    Plugins::ZXTune::Metadata->init($pluginDir);

    # Initialize zxtune:// protocol handler for remote catalogues, local subsongs & radio
    Plugins::ZXTune::ProtocolHandler->init();

    # Initialize OPML-based menu under Radio / My Apps
    $class->SUPER::initPlugin(
        feed   => \&handleFeed,
        tag    => 'zxtune',
        menu   => 'radios',
        is_app => $class->can('nonSNApps') ? 1 : undef,
        weight => 10,
    );

    $log->info("ZXTune plugin (v1.0.5130) initialized successfully from $pluginDir");
}

sub shutdownPlugin {
    my $class = shift;
    $log->info("ZXTune plugin shutting down");
}

sub getDisplayName {
    return 'PLUGIN_ZXTUNE';
}

sub playerMenu {
    my $class = shift;
    return $class->can('nonSNApps') ? undef : 'RADIO';
}

sub handleFeed {
    my ($client, $cb, $args) = @_;
    Plugins::ZXTune::Catalogs->getMainMenu($client, $cb, $args);
}

1;
