#
# Dynamic Playlists 4
#
# (c) 2021-2022 AF
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

package Plugins::DynamicPlaylists4::PlaylistProtocolHandler;

use strict;
use warnings;
use utf8;
use base qw(FileHandle);
use Data::Dumper;
use Slim::Utils::Log;

my $log = logger('plugin.dynamicplaylists4');

sub overridePlayback {
	my ($class, $client, $url) = @_;

	if ($url !~ m|^dynamicplaylistaddonly://(.*)$|) {
		return undef;
	}

	my ($hasParams) = $url =~ /p1=/;
	my $playlistID = '';

	if ($hasParams) {
		($playlistID) = $url =~ /^dynamicplaylistaddonly:\/\/(.*?)\?/;
	} else {
		$playlistID= $1;
	}

	my $command = ["dynamicplaylist", "playlist", "add", "playlistid:".$playlistID];

	my $cnt = 1;
	while ($hasParams) {
		my ($thisParam) = $url =~ /p${cnt}=(.*?)(&|$)/;
		($hasParams) = $url =~ /p${cnt}=/;

		if ($hasParams) {
			push @{$command}, "dynamicplaylist_parameter_".$cnt.":".$thisParam;
		}

		if (!$hasParams) {last;}
		$cnt++;
	}

	$log->debug('fav list client command = '.Dumper($command));
	$client->execute(['playlist', 'clear']);
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

1;
