# 				DynamicPlaylists3 plugin
#
# (c) 2021-2022 AF
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

package Plugins::DynamicPlaylists3::Settings::PlaylistSettings;

use strict;
use base qw(Plugins::DynamicPlaylists3::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Data::Dumper;

my $prefs = preferences('plugin.dynamicplaylists3');
my $log = logger('plugin.dynamicplaylists3');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_DYNAMICPLAYLISTS3_PLAYLISTSETTINGS';
}

sub page {
	return 'plugins/DynamicPlaylists3/settings/playlists.html';
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my ($playLists, $playListItems, $unclassifiedPlaylists, $savedstaticPlaylists) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
	$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
	my @groupPath = ();
	my @groupResult = ();

	$paramRef->{'savedstaticPlaylists'} = $savedstaticPlaylists;
	$paramRef->{'unclassifiedPlaylists'} = $unclassifiedPlaylists->{'unclassifiedPlaylists'};
	$paramRef->{'unclassifiedContextMenuPlaylists'} = $unclassifiedPlaylists->{'unclassifiedContextMenuPlaylists'};
	$paramRef->{'pluginDynamicPlaylists3Groups'} = Plugins::DynamicPlaylists3::Plugin::getPlayListGroups(\@groupPath, $playListItems, \@groupResult);

	if ($paramRef->{'saveSettings'}) {
		my $first = 1;
		my $sql = '';
		foreach my $playlist (keys %{$playLists}) {
			my $playlistid = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'};
			if ($paramRef->{$playlistid}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 1);
			} else {
				$prefs->set('playlist_'.$playlist.'_enabled', 0);
			}
		}

		savePlayListGroups($playListItems, $paramRef, '');
		($playLists, $playListItems) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
		my @groupPath = ();
		my @groupResult = ();
		$paramRef->{'pluginDynamicPlaylists3Groups'} = Plugins::DynamicPlaylists3::Plugin::getPlayListGroups(\@groupPath, $playListItems, \@groupResult);
		}

	return $class->SUPER::handler($client, $paramRef);
}

sub savePlayListGroups {
	my $items = shift;
	my $paramRef = shift;
	my $path = shift;

	foreach my $itemKey (keys %{$items}) {
		my $item = $items->{$itemKey};
		if(!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path)."_".escape($item->{'name'});
			my $playlistid = "playlist_".$groupid;
			if($paramRef->{$playlistid}) {
				$prefs->set('playlist_group_'.$groupid.'_enabled', 1);
			} else {
				$prefs->set('playlist_group_'.$groupid.'_enabled', 0);
			}
			if (defined($item->{'childs'})) {
				savePlayListGroups($item->{'childs'}, $paramRef, $path."_".$item->{'name'});
			}
		}
	}
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
