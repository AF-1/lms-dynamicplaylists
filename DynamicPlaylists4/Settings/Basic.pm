#
# Dynamic Playlists 4
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::DynamicPlaylists4::Settings::Basic;

use strict;
use warnings;
use utf8;
use base qw(Plugins::DynamicPlaylists4::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.dynamicplaylists4');
my $log = logger('plugin.dynamicplaylists4');

sub new {
	my ($class, $plugin) = @_;
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
	return [{ 'name' => Slim::Utils::Strings::string('PLUGIN_DYNAMICPLAYLISTS4_SETTINGS'), 'page' => page() }];
}

sub prefs {
	return ($prefs, qw(max_number_of_unplayed_tracks min_number_of_unplayed_tracks number_of_played_tracks_to_keep pluginshufflemode includesavedplaylists randomsavedplaylists groupunclassifiedcustomplaylists structured_savedplaylists rememberactiveplaylist song_adding_check_delay song_min_duration toprated_min_rating customdirparentfolderpath period_playedlongago minartisttracks minalbumtracks dstmstartindex paramsdplsaveenabled showtimeperchar enablestaticplsaving enabledplqueueing transferunsyncedtargetplayers jivenextwindow debugverbose));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	if ($paramRef->{'saveSettings'}) {
		if ($paramRef->{'pref_min_number_of_unplayed_tracks'} > $paramRef->{'pref_max_number_of_unplayed_tracks'}) {
			$prefs->set('min_number_of_unplayed_tracks', $paramRef->{'pref_max_number_of_unplayed_tracks'});
			$paramRef->{'pref_min_number_of_unplayed_tracks'} = $paramRef->{'pref_max_number_of_unplayed_tracks'};
		}

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
	}
	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;

	my $genrelist = getGenres();
	main::DEBUGLOG && $log->is_debug && $log->debug("genrelist (all genres) = ".Data::Dump::dump($genrelist)) if $prefs->get('debugverbose');
	$paramRef->{'genrelist'} = $genrelist;

	my $genrelistsorted = [getSortedGenres()];
	main::DEBUGLOG && $log->is_debug && $log->debug("genrelistsorted (just names) = ".Data::Dump::dump($genrelistsorted)) if $prefs->get('debugverbose');
	$paramRef->{'genrelistsorted'} = $genrelistsorted;
}

sub getGenres {
	my $genres = {};
	my $genreSQL = "select genres.id,genres.name,genres.namesearch from genres order by namesort asc";

	my $excludenamelist = $prefs->get('excludegenres_namelist');
	my %exclude;
	if ($excludenamelist) {
		%exclude = map { $_ => 1 } @{$excludenamelist};
	}

	my $i = 0;
	my $sth = Slim::Schema->dbh->prepare($genreSQL);
	main::DEBUGLOG && $log->is_debug && $log->debug("Executing: $genreSQL") if $prefs->get('debugverbose');
	eval {
		if (!$sth->execute()) {
			$log->error("Error executing: $genreSQL");
		} else {
			my ($id, $name, $namesearch);
			$sth->bind_col(1, \$id);
			$sth->bind_col(2, \$name);
			$sth->bind_col(3, \$namesearch);
			while ($sth->fetch()) {
				my %item = (
					'id' => Slim::Utils::Unicode::utf8decode($id, 'utf8'),
					'name' => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
					'namesearch' => Slim::Utils::Unicode::utf8decode($namesearch, 'utf8'),
					'chosen' => $exclude{$namesearch} ? 'yes' : '',
					'sort' => $i++,
				);
				$genres->{$namesearch} = \%item;
			}
			$sth->finish();
		}
	};
	if ($@) {
		$log->error("Database error: $@");
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('genre list before render = '.Data::Dump::dump($genres)) if $prefs->get('debugverbose');
	return $genres;
}

sub getSortedGenres {
	my $genres = getGenres();
	return sort {
		$genres->{$a}->{'sort'} <=> $genres->{$b}->{'sort'};
	} keys %{$genres};
}

1;
