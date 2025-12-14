#
# Dynamic Playlists 4
#
# (c) 2021 AF
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
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
				dontStopTheMusic($playlist, $playlists->{$playlist}->{'name'}, @_);
			});
			main::DEBUGLOG && $log->is_debug && $log->debug('Registered this dpl with DSTM: '.$playlists->{$playlist}->{'name'});
		} else {
			Slim::Plugin::DontStopTheMusic::Plugin->unregisterHandler(string('PLUGIN_DYNAMICPLAYLISTS4_DYNAMICPLAYLIST').': '.$playlists->{$playlist}->{'name'});
			main::DEBUGLOG && $log->is_debug && $log->debug('UNregistered this dpl with DSTM: '.$playlists->{$playlist}->{'name'});
		}
	}
}

sub dontStopTheMusic {
	my ($mixtype, $dplName, $client, $cb) = @_;
	return unless $client;
	main::DEBUGLOG && $log->is_debug && $log->debug('DSTM mixtype = '.$mixtype);

	my $request = $client->execute(['playlist', 'add', 'dynamicplaylist://'.$mixtype, $dplName]);
	$request->source('PLUGIN_DYNAMICPLAYLISTS4');
	$cb->($client, []);
}

1;
