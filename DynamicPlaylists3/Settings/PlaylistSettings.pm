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
use Slim::Utils::Strings qw(string);
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
	my $result = undef;
	my $callHandler = 1;

	my ($playLists, $playListItems, $unclassifiedPlaylists, $savedstaticPlaylists) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
	$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
	my @groupPath = ();
	my @groupResult = ();

	my $categorylangstrings = {
		'songs' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_TRACKS"),
		'artists' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_ARTISTS"),
		'albums' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_ALBUMS"),
		'genres' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_GENRES"),
		'years' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_YEARS"),
		'playlists' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS3_CATNAME_PLAYLISTS")
	};
	$paramRef->{'categorylangstrings'} = $categorylangstrings;

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
		$result = $class->SUPER::handler($client, $paramRef);
		$callHandler = 0;
	}
	if ($paramRef->{'apc_dpl3only'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		foreach my $playlist (keys %{$playLists}) {
			if ($playLists->{$playlist}->{'playlistapcdupe'}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 1);
			} elsif ($playLists->{$playlist}->{'apcplaylist'}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 0);
			}
		}
		($playLists, $playListItems) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
		$result = $class->SUPER::handler($client, $paramRef);
	} elsif ($paramRef->{'apc_apconly'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		foreach my $playlist (keys %{$playLists}) {
			if ($playLists->{$playlist}->{'playlistapcdupe'}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 0);
			} elsif ($playLists->{$playlist}->{'apcplaylist'}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 1);
			}
		}
		($playLists, $playListItems) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
		$result = $class->SUPER::handler($client, $paramRef);
	} elsif ($paramRef->{'apc_both'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
		}
		foreach my $playlist (keys %{$playLists}) {
			if ($playLists->{$playlist}->{'playlistapcdupe'} || $playLists->{$playlist}->{'apcplaylist'}) {
				$prefs->set('playlist_'.$playlist.'_enabled', 1);
			}
		}
		($playLists, $playListItems) = Plugins::DynamicPlaylists3::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists3PlayLists'} = $playLists;
		$result = $class->SUPER::handler($client, $paramRef);
	} elsif ($callHandler) {
		$result = $class->SUPER::handler($client, $paramRef);
	}

	return $result;
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

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	$paramRef->{'apcenabled'} = 'yes' if $apc_enabled;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
