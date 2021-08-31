# 				DynamicPlayList plugin
#
# (c) 2021 AF
#
# Based on the DynamicPlayList plugin by (c) 2006 Erland Isaksson
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

package Plugins::DynamicPlayList::ProtocolHandler;

use strict;
use base qw(FileHandle);

sub overridePlayback {
	my ($class, $client, $url) = @_;

	if ($url !~ m|^dynamicplaylist://(.*)$|) {
		return undef;
	}

	$client->execute(["dynamicplaylist", "playlist", "play", "playlistid:$1"]);
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
	return Plugins::DynamicPlayList::Plugin->_pluginDataFor('icon');
}

1;
