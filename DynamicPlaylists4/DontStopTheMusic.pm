#
# Dynamic Playlists 4
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::DynamicPlaylists4::DontStopTheMusic;

use strict;
use warnings;
use utf8;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Schema;

use Plugins::DynamicPlaylists4::Plugin;
use Slim::Plugin::DontStopTheMusic::Plugin;

my $log = logger('plugin.dynamicplaylists4');
my $prefs = preferences('plugin.dynamicplaylists4');

sub init {
	my ($class, $dstmPlaylists, $playlists) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('dstmPlaylists init = '.Data::Dump::dump($dstmPlaylists)) if $prefs->get('debugverbose');

	for my $playlist (keys %{$playlists}) {
		if ($dstmPlaylists->{$playlist}) {
			Slim::Plugin::DontStopTheMusic::Plugin->registerHandler(string('PLUGIN_DYNAMICPLAYLISTS4_DYNAMICPLAYLIST').': '.$playlists->{$playlist}->{'name'}, sub {
				my ($client, $cb) = @_;
				my $track = Slim::Schema::RemoteTrack->new({
					url => 'dynamicplaylist://'.$playlist,
					title => $playlists->{$playlist}->{name},
					type => 'dynamicplaylist',
				});
				$cb->($client, [$track]);
			});
			main::DEBUGLOG && $log->is_debug && $log->debug('Registered this dpl with DSTM: '.$playlists->{$playlist}->{'name'});
		} else {
			Slim::Plugin::DontStopTheMusic::Plugin->unregisterHandler(string('PLUGIN_DYNAMICPLAYLISTS4_DYNAMICPLAYLIST').': '.$playlists->{$playlist}->{'name'});
			main::DEBUGLOG && $log->is_debug && $log->debug('UNregistered this dpl with DSTM: '.$playlists->{$playlist}->{'name'});
		}
	}
}

1;
