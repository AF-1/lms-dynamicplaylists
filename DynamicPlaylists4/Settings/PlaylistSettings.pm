#
# Dynamic Playlists 4
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::DynamicPlaylists4::Settings::PlaylistSettings;

use strict;
use warnings;
use utf8;
use base qw(Plugins::DynamicPlaylists4::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Basename;

my $prefs = preferences('plugin.dynamicplaylists4');
my $log = logger('plugin.dynamicplaylists4');

sub new {
	my ($class, $plugin) = @_;
	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_DYNAMICPLAYLISTS4_PLAYLISTSETTINGS';
}

sub page {
	return 'plugins/DynamicPlaylists4/settings/playlists.html';
}

sub currentPage {
	return name();
}

sub pages {
	return [{ 'name' => name(), 'page' => page() }];
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result;
	my $callHandler = 1;

	my ($playLists, $playListMenuItems, $unclassifiedPlaylists, $savedstaticPlaylists) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
	$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;
	my (@groupPath, @groupResult);

	my $categorylangstrings = {
		'songs' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_TRACKS"),
		'artists' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_ARTISTS"),
		'albums' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_ALBUMS"),
		'works' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_WORKS"),
		'genres' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_GENRES"),
		'years' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_YEARS"),
		'playlists' => string("SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_PLAYLISTS")
	};
	$paramRef->{'categorylangstrings'} = $categorylangstrings;

	$paramRef->{'savedstaticPlaylists'} = $savedstaticPlaylists;
	$paramRef->{'unclassifiedPlaylists'} = $unclassifiedPlaylists->{'unclassifiedPlaylists'};
	$paramRef->{'unclassifiedContextMenuPlaylists'} = $unclassifiedPlaylists->{'unclassifiedContextMenuPlaylists'};
	$paramRef->{'pluginDynamicPlaylists4Groups'} = Plugins::DynamicPlaylists4::Plugin::getPlayListGroups(\@groupPath, $playListMenuItems, \@groupResult);

	my @playlistCategories = ('songs', 'artists', 'albums', 'genres', 'years', 'playlists');
	splice @playlistCategories, 3, 0, 'works' if (Slim::Utils::Versions->compareVersions($::VERSION, '9.0') >= 0);
	$paramRef->{'playlistcategories'} = \@playlistCategories;

	if ($paramRef->{'saveSettings'}) {
		foreach my $playlist (keys %{$playLists}) {
			my $playlistid = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'}."_enabled";
			$prefs->set('playlist_'.$playlist.'_enabled', $paramRef->{$playlistid} ? 1 : 0);

			# favs
			my $playlistfavouriteid = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'}."_isfav";
			if ($paramRef->{$playlistfavouriteid}) {
				$prefs->set('playlist_'.$playlist.'_favourite', 1);
			} else {
				$prefs->remove('playlist_'.$playlist.'_favourite');
			}

			# dstm
			my $playlistdstm = "playlist_".$playLists->{$playlist}{'dynamicplaylistid'}."_dstm";
			if ($paramRef->{$playlistid} && $paramRef->{$playlistdstm}) {
				$prefs->set('playlist_'.$playlist.'_dstmenabled', 1);
			} else {
				$prefs->remove('playlist_'.$playlist.'_dstmenabled');
			}
		}

		savePlayListGroups($playListMenuItems, $paramRef, '');
		($playLists, $playListMenuItems) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;
		$paramRef->{'pluginDynamicPlaylists4Groups'} = Plugins::DynamicPlaylists4::Plugin::getPlayListGroups(\@groupPath, $playListMenuItems, \@groupResult);
		$result = $class->SUPER::handler($client, $paramRef);
		$callHandler = 0;
	}
	if ($paramRef->{'apc_dplonly'}) {
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
		($playLists, $playListMenuItems) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;
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
		($playLists, $playListMenuItems) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;
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
		($playLists, $playListMenuItems) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
		$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;
		$result = $class->SUPER::handler($client, $paramRef);
	} elsif ($callHandler) {
		$result = $class->SUPER::handler($client, $paramRef);
	}

	return $result;
}

sub savePlayListGroups {
	my ($items, $paramRef, $path) = @_;

	foreach my $itemKey (keys %{$items}) {
		my $item = $items->{$itemKey};
		if (!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path)."_".escape($item->{'name'});
			$prefs->set('playlist_group_'.$groupid.'_enabled', $paramRef->{'playlist_'.$groupid.'_enabled'} ? 1 : 0);
			if ($item->{'childs'}) {
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
