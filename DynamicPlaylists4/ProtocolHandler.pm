#
# Dynamic Playlists 4
#
# (c) 2021 AF
#
# Some code based on the DynamicPlayList plugin by (c) 2006 Erland Isaksson
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

package Plugins::DynamicPlaylists4::ProtocolHandler;

use strict;
use warnings;
use utf8;
use base qw(FileHandle);
use Slim::Utils::Log;
use URI;

my $log = logger('plugin.dynamicplaylists4');

sub overridePlayback {
	my ($class, $client, $url) = @_;

	my $uri = URI->new($url);
	return undef unless $uri->scheme eq 'dynamicplaylist';

	if ( Slim::Player::Source::streamingSongIndex($client) ) {
		# don't start immediately if we're part of a playlist and previous track isn't done playing
		return undef if $client->controller()->playingSongDuration()
	}

	my ($playlistID, $query) = $url =~ m{^dynamicplaylist://([^?]+)(?:\?(.*))?$};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistID = '.Data::Dump::dump($playlistID));
	return undef unless defined $playlistID;

	my $command = ["dynamicplaylist", "playlist", "play", "playlistid:".$playlistID];

	if ($query) {
		my $cnt = 1;
		while (my ($value) = $query =~ /p${cnt}=([^&]*)/) {
			push @{$command}, "dynamicplaylist_parameter_${cnt}:$value";
			$cnt++;
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('client command = '.Data::Dump::dump($command));
	$client->execute($command);
	return 1;
}

sub canDirectStream {
	return 0;
}

sub isAudioURL {
	return 1;
}

sub isRemote {
	return 0;
}

sub contentType {
	return 'dynamicplaylist';
}

sub getIcon {
	return Plugins::DynamicPlaylists4::Plugin->_pluginDataFor('icon');
}

sub getMetadataFor {
	my ($class, $client, $url) = @_;
	return unless $client && $url;
	return {
		cover => $class->getIcon(),
	};
}

1;
