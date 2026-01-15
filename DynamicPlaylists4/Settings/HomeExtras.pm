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

package Plugins::DynamicPlaylists4::Settings::HomeExtras;

use strict;
use warnings;
use utf8;
use base qw(Plugins::DynamicPlaylists4::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.dynamicplaylists4');
my $log = logger('plugin.dynamicplaylists4');

my $plugin;

my @homeExtraItemsPrefs = qw(homeextras_dynamicalbumdiscovery01 homeextras_dynamicalbumdiscovery02 homeextras_dynamicartistdiscovery01);

sub new {
	my $class = shift;
	$plugin = shift;

	if (Plugins::MaterialSkin::Plugin->can('setHomeExtraTitle')) {
		$prefs->setChange(sub {
			my ($pref, $value, $client) = @_;

			my $playlist = Plugins::DynamicPlaylists4::Plugin::getPlayList($client, $value) if $value;

			if ($playlist && (my $name = $playlist->{name})) {
				my $homeExtraId = $pref;
				$homeExtraId =~ s/^homeextras_/DynamicPlaylistsExtras/;
				Plugins::MaterialSkin::Plugin->setHomeExtraTitle($homeExtraId, $name);
			}
		}, @homeExtraItemsPrefs);
	}

	$class->SUPER::new($plugin);
}
sub name {
	return Slim::Web::HTTP::CSRF->protectName('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_HOMEEXTRASMENUS');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/DynamicPlaylists4/settings/homeextras.html');
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

sub prefs {
	return ($prefs, @homeExtraItemsPrefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my ($playLists, $playListItems, $unclassifiedPlaylists, $savedstaticPlaylists) = Plugins::DynamicPlaylists4::Plugin::initPlayLists($client);
	$paramRef->{'pluginDynamicPlaylists4PlayLists'} = $playLists;

	return $class->SUPER::handler($client, $paramRef);
}

1;
