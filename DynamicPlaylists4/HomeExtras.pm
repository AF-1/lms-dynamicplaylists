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

package Plugins::DynamicPlaylists4::HomeExtras;
use strict;
use warnings;
use utf8;
use Plugins::DynamicPlaylists4::Plugin;

Plugins::DynamicPlaylists4::HomeExtraDynamicAlbumDiscovery01->initPlugin();
Plugins::DynamicPlaylists4::HomeExtraDynamicAlbumDiscovery02->initPlugin();
Plugins::DynamicPlaylists4::HomeExtraDynamicArtistDiscovery01->initPlugin();
Plugins::DynamicPlaylists4::HomeExtraDynamicPlaylistDiscovery01->initPlugin();

1;

package Plugins::DynamicPlaylists4::HomeExtraBase;
use strict;
use warnings;
use utf8;
use base qw(Plugins::MaterialSkin::HomeExtraBase);

use Slim::Utils::Prefs;
use Plugins::DynamicPlaylists4::Plugin;

sub initPlugin {
	my ($class, %args) = @_;

	my $tag = $args{tag};
	my $prefs = preferences('plugin.dynamicplaylists4');
	my $title = $args{title};

	if (my $playlistId = $prefs->get("homeextras_$tag")) {
		my $playlist = Plugins::DynamicPlaylists4::Plugin::getPlayList(undef, $playlistId);
		if ($playlist && (my $name = $playlist->{name})) {
			$title = $name;
		}
	}

	$class->SUPER::initPlugin(
		feed => sub { handleFeed($tag, @_) },
		tag => "DynamicPlaylistsExtras${tag}",
		extra => {
			title => $title,
			subtitle => $args{subtitle},
			icon => $args{icon} || Plugins::DynamicPlaylists4::Plugin->_pluginDataFor('icon'),
			needsPlayer => 1,
		}
	);
}

sub handleFeed {
	my ($tag, $client, $cb, $args) = @_;

	$args->{params}->{menu} = "home_heroes_${tag}";
	$args->{params}->{tag} = $tag;

	Plugins::DynamicPlaylists4::Plugin::getHomeExtraMenuItems($client, $cb, $args);
}

package Plugins::DynamicPlaylists4::HomeExtraDynamicAlbumDiscovery01;
use base qw(Plugins::DynamicPlaylists4::HomeExtraBase);
sub initPlugin {
	my ($class, %args) = @_;

	$class->SUPER::initPlugin(
		title => 'SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_HOMEEXTRASMENUS_ALBUMS01',
		tag => 'dynamicalbumdiscovery01'
	);
}
1;

package Plugins::DynamicPlaylists4::HomeExtraDynamicAlbumDiscovery02;
use base qw(Plugins::DynamicPlaylists4::HomeExtraBase);
sub initPlugin {
	my ($class, %args) = @_;

	$class->SUPER::initPlugin(
		title => 'SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_HOMEEXTRASMENUS_ALBUMS02',
		tag => 'dynamicalbumdiscovery02'
	);
}
1;

package Plugins::DynamicPlaylists4::HomeExtraDynamicArtistDiscovery01;
use base qw(Plugins::DynamicPlaylists4::HomeExtraBase);
sub initPlugin {
	my ($class, %args) = @_;

	$class->SUPER::initPlugin(
		title => 'SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_HOMEEXTRASMENUS_ARTISTS01',
		tag => 'dynamicartistdiscovery01'
	);
}
1;

package Plugins::DynamicPlaylists4::HomeExtraDynamicPlaylistDiscovery01;
use base qw(Plugins::DynamicPlaylists4::HomeExtraBase);
sub initPlugin {
	my ($class, %args) = @_;

	$class->SUPER::initPlugin(
		title => 'SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_HOMEEXTRASMENUS_PLAYLISTS01',
		tag => 'dynamicplaylistdiscovery01'
	);
}
1;
