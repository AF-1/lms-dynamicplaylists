#
# Dynamic Playlists 3
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

package Plugins::DynamicPlaylists3::Settings::BaseSettings;

use strict;
use warnings;
use utf8;
use base qw(Slim::Web::Settings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.dynamicplaylists3');
my $log = logger('plugin.dynamicplaylists3');

my $plugin;
my %subPages = ();

sub new {
	my $class = shift;
	$plugin = shift;
	my $default = shift;

	if (!defined($default) || !$default) {
		if ($class->can('page') && $class->can('handler')) {
			Slim::Web::Pages->addPageFunction($class->page, $class);
		}
	} else {
		$class->SUPER::new();
	}
	$subPages{$class->name()} = $class;
}

sub handler {
	my ($class, $client, $params) = @_;

	my %currentSubPages = ();
	for my $key (keys %subPages) {
		my $pages = $subPages{$key}->pages($client, $params);
		for my $page (@{$pages}) {
			$currentSubPages{$page->{'name'}} = $page->{'page'};
		}
	}
	$params->{'subpages'} = \%currentSubPages;
	$params->{'subpage'} = $class->currentPage($client, $params);
	return $class->SUPER::handler($client, $params);
}

1;
