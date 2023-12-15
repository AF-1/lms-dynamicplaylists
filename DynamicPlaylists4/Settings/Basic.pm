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

package Plugins::DynamicPlaylists4::Settings::Basic;

use strict;
use warnings;
use utf8;
use base qw(Plugins::DynamicPlaylists4::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.dynamicplaylists4');
my $log = logger('plugin.dynamicplaylists4');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_DYNAMICPLAYLISTS4';
}

sub page {
	return 'plugins/DynamicPlaylists4/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_DYNAMICPLAYLISTS4_SETTINGS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_DYNAMICPLAYLISTS4_SETTINGS'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs, qw(max_number_of_unplayed_tracks min_number_of_unplayed_tracks number_of_played_tracks_to_keep pluginshufflemode includesavedplaylists randomsavedplaylists groupunclassifiedcustomplaylists flatlist structured_savedplaylists rememberactiveplaylist song_adding_check_delay song_min_duration toprated_min_rating customdirparentfolderpath period_playedlongago minartisttracks minalbumtracks dstmstartindex paramsdplsaveenabled showtimeperchar enablestaticplsaving enabledplqueueing));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
	my $callHandler = 1;
	if ($paramRef->{'saveSettings'}) {
		if ($paramRef->{'pref_min_number_of_unplayed_tracks'} > $paramRef->{'pref_max_number_of_unplayed_tracks'}) {
			$prefs->set('min_number_of_unplayed_tracks', $paramRef->{'pref_max_number_of_unplayed_tracks'});
			$paramRef->{'pref_min_number_of_unplayed_tracks'} = $paramRef->{'pref_max_number_of_unplayed_tracks'};
		}

		$paramRef->{'pref_rememberactiveplaylist'} = $paramRef->{'pref_rememberactiveplaylist'} || 0;
		$paramRef->{'pref_showactiveplaylistinmainmenu'} = $paramRef->{'pref_showactiveplaylistinmainmenu'} || 0;
		$paramRef->{'pref_groupunclassifiedcustomplaylists'} = $paramRef->{'pref_groupunclassifiedcustomplaylists'} || 0;

		my $excludegenres_namelist;
		my $genres = getGenres();

		# %{$paramRef} will contain a key called genre_<genre id> for each ticked checkbox on the page
		for my $genre (keys %{$genres}) {
			if ($paramRef->{'genre_'.$genres->{$genre}->{'id'}}) {
				push (@{$excludegenres_namelist}, $genre);
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug("*** SAVED *** excludegenres_namelist = ".Data::Dump::dump($excludegenres_namelist));
		$prefs->set('excludegenres_namelist', $excludegenres_namelist);

		$result = $class->SUPER::handler($client, $paramRef);
	} elsif ($callHandler) {
		$result = $class->SUPER::handler($client, $paramRef);
	}
	return $result;
}

sub beforeRender {
	my ($class, $paramRef) = @_;

	my $genrelist = getGenres();
	main::DEBUGLOG && $log->is_debug && $log->debug("genrelist (all genres) = ".Data::Dump::dump($genrelist));
	$paramRef->{'genrelist'} = $genrelist;

	my $genrelistsorted = [getSortedGenres()];
	main::DEBUGLOG && $log->is_debug && $log->debug("genrelistsorted (just names) = ".Data::Dump::dump($genrelistsorted));
	$paramRef->{'genrelistsorted'} = $genrelistsorted;
}

sub getGenres {
	my $genres = {};
	my $query = ['genres', 0, 999_999];

	my $request = Slim::Control::Request::executeRequest(undef, $query);

	my $excludenamelist = $prefs->get('excludegenres_namelist');
	# Extract each genre name into a hash
	my %exclude;
	if (defined $excludenamelist) {
		%exclude = map { $_ => 1 } @{$excludenamelist};
	}

	my $i = 0;
	foreach my $genre ( @{ $request->getResult('genres_loop') || [] } ) {
		my $name = $genre->{genre};
		$genres->{$name} = {
			'name' => $name,
			'id' => $genre->{id},
			'chosen' => $exclude{$name} ? 'yes' : '',
			'sort' => $i++,
		};
	}
	return $genres;
}

sub getSortedGenres {
	my $genres = getGenres();
	return sort {
		$genres->{$a}->{sort} <=> $genres->{$b}->{sort};
	} keys %{$genres};
}

1;
