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

package Plugins::DynamicPlayList::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Player::ProtocolHandlers;
use Slim::Player::Client;
use File::Spec::Functions qw(:ALL);
use POSIX qw(floor);
use Class::Struct;
use DBI qw(:sql_types);
use FindBin qw($Bin);
use Scalar::Util qw(blessed);
use Plugins::DynamicPlayList::Settings;
use Plugins::DynamicPlayList::PlaylistSettings;
use Plugins::DynamicPlayList::FavouriteSettings;
use Plugins::DynamicPlayList::ProtocolHandler;
use Digest::SHA1 qw(sha1_base64);
use Data::Dumper;
use File::Slurp; # for read_file
use File::Basename;
use HTML::Entities; # for parsing
use List::Util qw(shuffle);
use Time::HiRes qw(time);

our $PLUGINVERSION = undef;

my $prefs = preferences('plugin.dynamicplaylist');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.dynamicplaylist',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_DYNAMICPLAYLIST',
});

my %stopcommands = ();
my %mixInfo = ();
my $htmlTemplate = 'plugins/DynamicPlayList/dynamicplaylist_list.html';
my $playLists = undef;
my $playListTypes = undef;
my $playListItems = undef;
my $jiveMenu = undef;
my $rescan = 0;

my %plugins = ();
my %disablePlaylist = (
	'dynamicplaylistid' => 'disable',
	'name' => ''
);
my %disable = (
	'playlist' => \%disablePlaylist
);

my $historyQueue = {};
my $deleteQueue = {};
my $deleteAllQueues = 0;

my %empty = ();
my %choiceMapping;
my $localDynamicPlaylists;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};
	Plugins::DynamicPlayList::Settings->new();
	Plugins::DynamicPlayList::PlaylistSettings->new();
	Plugins::DynamicPlayList::FavouriteSettings->new();

	# playlist commands that will stop random play
	%stopcommands = (
		'clear' => 1,
		'loadtracks' => 1, # multiple play
		'playtracks' => 1, # single play
		'load' => 1, # old style url load (no play)
		'play' => 1, # old style url play
		'loadalbum' => 1, # old style multi-item load
		'playalbum' => 1, # old style multi-item play
	);

	initPrefs();
	initDatabase();
	clearPlayListHistory();
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlayList.ChooseParameters', getFunctions(), \&setModeChooseParameters);
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlayList.Mixer', getFunctions(), \&setModeMixer);
	my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'favorites'} = sub {Slim::Buttons::Input::Choice::callCallback('onFavorites', @_)};
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlayList.Choice', \%choiceFunctions, \&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		if (!defined($choiceMapping{'play.'.$buttonPressMode})) {
			$choiceMapping{'play.'.$buttonPressMode} = 'dead';
		}
		if (!defined($choiceMapping{'add.'.$buttonPressMode})) {
			$choiceMapping{'add.'.$buttonPressMode} = 'dead';
		}
		if (!defined($choiceMapping{'search.'.$buttonPressMode})) {
			$choiceMapping{'search.'.$buttonPressMode} = 'passback';
		}
		if (!defined($choiceMapping{'stop.'.$buttonPressMode})) {
			$choiceMapping{'stop.'.$buttonPressMode} = 'passback';
		}
		if (!defined($choiceMapping{'pause.'.$buttonPressMode})) {
			$choiceMapping{'pause.'.$buttonPressMode} = 'passback';
		}
	}
	Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.DynamicPlayList.Choice', \%choiceMapping);

	# set up our subscription
	Slim::Control::Request::subscribe(\&commandCallback65, [['playlist'], ['newsong', 'delete', keys %stopcommands]]);
	Slim::Control::Request::subscribe(\&powerCallback, [['power']]);
	Slim::Control::Request::subscribe(\&clientNewCallback, [['client'], ['new']]);
	Slim::Control::Request::subscribe(\&rescanDone, [['rescan'], ['done']]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'isactive'], [1, 1, 0, \&cliIsActive]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlists', '_all', '_start', '_itemsPerResponse'], [1, 1, 0, \&cliGetPlaylists]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'play'], [1, 0, 1, \&cliPlayPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'add'], [1, 0, 1, \&cliAddPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'continue'], [1, 0, 1, \&cliContinuePlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'stop'], [1, 0, 0, \&cliStopPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'browsejive', '_start', '_itemsPerResponse'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'jiveplaylistparameters', '_start', '_itemsPerResponse'], [1, 1, 1, \&cliJivePlaylistParametersHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'mixjive'], [1, 1, 1, \&cliMixJiveHandler]);

	Slim::Player::ProtocolHandlers->registerHandler(dynamicplaylist => 'Plugins::DynamicPlayList::ProtocolHandler');
}

sub title {
	return 'DYNAMICPLAYLIST';
}

sub weight {
	return 78;
}

sub postinitPlugin {
	my $class = shift;
	initPlayLists();
	initPlayListTypes();
	registerJiveMenu($class);
	registerStandardContextMenus();
	registerContextMenu();
}

sub initPrefs {
	%choiceMapping = (
		'arrow_left' => 'exit_left',
		'arrow_right' => 'exit_right',
		'knob_push' => 'exit_right',
		'play' => 'play',
		'add' => 'add',
		'search' => 'passback',
		'stop' => 'passback',
		'pause' => 'passback',
		'favorites.hold' => 'favorites_add',
		'preset_1.hold' => 'favorites_add1',
		'preset_2.hold' => 'favorites_add2',
		'preset_3.hold' => 'favorites_add3',
		'preset_4.hold' => 'favorites_add4',
		'preset_5.hold' => 'favorites_add5',
		'preset_6.hold' => 'favorites_add6',
	);

	if (!defined($prefs->get('max_number_of_unplayed_tracks'))) {
		$log->debug('Defaulting max_number_of_unplayed_tracks to 10');
		$prefs->set('max_number_of_unplayed_tracks', 15);
	}
	if (!defined($prefs->get('min_number_of_unplayed_tracks'))) {
		$log->debug('Defaulting min_number_of_unplayed_tracks to 4');
		$prefs->set('min_number_of_unplayed_tracks', 4);
	}
	if (!defined($prefs->get('number_of_played_tracks_to_keep'))) {
		$log->debug('Defaulting to keep 5 tracks');
		$prefs->set('number_of_played_tracks_to_keep', 3);
	}
	if (!defined $prefs->get('keep_adding_tracks')) {
		$log->debug('Defaulting to continous mode');
		$prefs->set('keep_adding_tracks', 1);
	}
	if (!defined($prefs->get('song_adding_check_delay'))) {
		$log->debug('Defaulting song_adding_check_delay to 30');
		$prefs->set('song_adding_check_delay', 30);
	}
	if (!defined($prefs->get('showmessages'))) {
		$log->debug('Defaulting to not showing messages');
		$prefs->set('showmessages', 0);
	}
	if (!defined($prefs->get('song_min_duration'))) {
		$log->debug('Defaulting song_min_duration to 90');
		$prefs->set('song_min_duration', 90);
	}
	if (!defined($prefs->get('toprated_min_rating'))) {
		$log->debug('Defaulting toprated_min_rating to 50');
		$prefs->set('toprated_min_rating', 60);
	}
	if (!defined($prefs->get('period_recentlyadded'))) {
		$log->debug('Defaulting period_recentlyadded to 1 month');
		$prefs->set('period_recentlyadded', 30);
	}
	if (!defined($prefs->get('period_recentlyplayed'))) {
		$log->debug('Defaulting period_recentlyplayed to 2 weeks');
		$prefs->set('period_recentlyplayed', 14);
	}
	if (!defined($prefs->get('period_playedlongago'))) {
		$log->debug('Defaulting period_playedlongago to 2 years');
		$prefs->set('period_playedlongago', 2);
	}
	if (!defined($prefs->get('_ts_rememberactiveplaylist'))) {
		$log->debug('Defaulting to remember active playlist');
		$prefs->set('rememberactiveplaylist', 'on');
	}
	if (!defined($prefs->get('_ts_groupunclassifiedcustomplaylists'))) {
		$log->debug('Defaulting to grouping unclassified playlists');
		$prefs->set('groupunclassifiedcustomplaylists', 'on');
	}
	if (!defined($prefs->get('customdirparentfolderpath'))) {
		my $playlistdir = $serverPrefs->get('playlistdir');
		$prefs->set('customdirparentfolderpath', $playlistdir);
	}
	if (!defined($prefs->get('randomsavedplaylists'))) {
		$log->debug('Defaulting to not playing songs in saved playlists in random order');
		$prefs->set('randomsavedplaylists', 0);
	}
	if (!defined($prefs->get('flatlist'))) {
		$log->debug('Defaulting to structured playlists');
		$prefs->set('flatlist', 0);
	}
	if (!defined($prefs->get('structured_savedplaylists'))) {
		$log->debug('Defaulting to structured playlists for saved playlists');
		$prefs->set('structured_savedplaylists', 'on');
	}
	if (!defined($prefs->get('favouritesname'))) {
		$log->debug('Defaulting favouritesname to '.string('PLUGIN_DYNAMICPLAYLIST_FAVOURITES'));
		$prefs->set('favouritesname', string('PLUGIN_DYNAMICPLAYLIST_FAVOURITES'));
	}

	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 50}, 'max_number_of_unplayed_tracks');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 0, 'high' => 100}, 'number_of_played_tracks_to_keep');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 60}, 'song_adding_check_delay');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 10}, 'min_number_of_unplayed_tracks');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 1800}, 'song_min_duration');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 365}, 'period_recentlyadded');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 365}, 'period_recentlyplayed');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 20}, 'period_playedlongago');
	$prefs->setValidate('dir', 'customdirparentfolderpath');
	$prefs->setChange(sub {
		my $customlistdir_parentfolderpath = $prefs->get('customdirparentfolderpath');
		my $customlistdir = $customlistdir_parentfolderpath.'/DPL-custom-lists';
		mkdir($customlistdir, 0755) unless (-d $customlistdir);
		}, 'customdirparentfolderpath');
}

sub initPlayLists {
	my $client = shift;
	$log->debug('Searching for playlists');

	getLocalDynamicPlaylists($client);

	my %localPlayLists = ();
	my %localPlayListItems = ();
	my %unclassifiedPlaylists = ();
	my $savedstaticPlaylists = undef;

	no strict 'refs';
	my @enabledplugins = Slim::Utils::PluginManager->enabledPlugins();
	for my $plugin (@enabledplugins) {
		if (UNIVERSAL::can("$plugin", 'getDynamicPlayLists') && UNIVERSAL::can("$plugin", 'getNextDynamicPlayListTracks')) {
			$log->debug("Getting dynamic playlists for: $plugin");
			my $items = eval {&{"${plugin}::getDynamicPlayLists"}($client)};
			if ($@) {
				$log->warn("Error getting playlists from $plugin: $@");
			}
			for my $item (keys %{$items}) {
				$plugins{$item} = "${plugin}";
				my $playlist = $items->{$item};
				$log->debug('Got dynamic playlist: '.$playlist->{'name'});
				$playlist->{'dynamicplaylistid'} = $item;
				$playlist->{'dynamicplaylistplugin'} = $plugin;

				my $pluginshortname = $plugin;
				if (starts_with($item, 'dpldefault_') == 0) {
					$pluginshortname = 'DynamicPlayList - built-in';
				} elsif (starts_with($item, 'dplusercustom_') == 0) {
					$pluginshortname = 'DynamicPlayList - custom/user-provided';
				} elsif (starts_with($item, 'dplstandardpl_') == 0) {
					$pluginshortname = 'Static LMS playlist';
					$savedstaticPlaylists = 'found saved static playlists';
				} else {
					$pluginshortname =~ s/^Plugins::|::Plugin+$//g;
				}
				$playlist->{'dynamicplaylistpluginshortname'} = $pluginshortname;

				my $enabled = $prefs->get('playlist_'.$item.'_enabled');
				if (!defined $enabled || $enabled) {
					$playlist->{'dynamicplaylistenabled'} = 1;
				} else {
					$playlist->{'dynamicplaylistenabled'} = 0;
				}

				my $favourite = $prefs->get('playlist_'.$item.'_favourite');
				if (defined($favourite) && $favourite) {
					$playlist->{'dynamicplaylistfavourite'} = 1;
				} else {
					$playlist->{'dynamicplaylistfavourite'} = 0;
				}

				$playlist->{'isFavorite'} = defined(Slim::Utils::Favorites->new($client)->findUrl('dynamicplaylist://'.$playlist->{'dynamicplaylistid'}))?1:0;
				if (defined($playlist->{'parameters'})) {
					foreach my $p (keys %{$playlist->{'parameters'}}) {
						if (defined($playLists)
							&& defined($playLists->{$item})
							&& defined($playLists->{$item}->{'parameters'})
							&& defined($playLists->{$item}->{'parameters'}->{$p})
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'name'})
							&& $playLists->{$item}->{'parameters'}->{$p}->{'name'} eq $playlist->{'parameters'}->{$p}->{'name'}
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'value'})) {

							$log->debug("Use already existing value for PlaylistParameter$p=".$playLists->{$item}->{'parameters'}->{$p}->{'value'});
							$playlist->{'parameters'}->{$p}->{'value'}=$playLists->{$item}->{'parameters'}->{$p}->{'value'};
						}
					}
				}
				$localPlayLists{$item} = $playlist;

				if (!$playlist->{'playlistcategory'}) {
					if ($playlist->{'menulisttype'} && ($playlist->{'menulisttype'} eq 'contextmenu')) {
						$unclassifiedPlaylists{'unclassifiedContextMenuPlaylists'} = 'found unclassified CPL';
					} else {
						$unclassifiedPlaylists{'unclassifiedPlaylists'} = 'found unclassified PL';
					}
				}
				my $groups = $playlist->{'groups'};
				if (!defined($groups)) {
					my $groupunclassifiedcustomplaylists = $prefs->get('groupunclassifiedcustomplaylists');
					if (defined($groupunclassifiedcustomplaylists)) {
						$groups = [['Not classified']];
					}
				}
				if (!defined($groups)) {
					my @emptyArray = ();
					$groups = \@emptyArray;
				}
				if ($favourite && $prefs->get('favouritesname')) {
					my @favouriteGroups = ();
					for my $g (@{$groups}) {
						push @favouriteGroups, $g;
					}
					my @favouriteGroup = ();
					push @favouriteGroup, $prefs->get('favouritesname');
					push @favouriteGroups, \@favouriteGroup;
					$groups = \@favouriteGroups;
				}
				if (scalar(@{$groups}) > 0) {
					for my $currentgroups (@{$groups}) {
						my $currentLevel = \%localPlayListItems;
						my $grouppath = '';
						my $enabled = 1;
						for my $group (@{$currentgroups}) {
							$grouppath .= '_'.escape($group);
							my $existingItem = $currentLevel->{'dynamicplaylistgroup_'.$group};
							if (defined($existingItem)) {
								if ($enabled) {
									$enabled = $prefs->get('playlist_group_'.$grouppath.'_enabled');
									if (!defined($enabled)) {
										$enabled = 1;
									}
								}
								if ($group eq 'Context menu lists') {
									$enabled = undef;
									$existingItem->{'dynamicplaylistenabled'} = 0;
								}
								if ($enabled && $playlist->{'dynamicplaylistenabled'}) {
									$existingItem->{'dynamicplaylistenabled'} = 1;
								}
								$currentLevel = $existingItem->{'childs'};
							} else {
								my %level = ();
								my %currentItemGroup = (
									'childs' => \%level,
									'name' => $group,
									'value' => $grouppath
								);
								if ($enabled) {
									$enabled = $prefs->get('playlist_group_'.$grouppath.'_enabled');
									if (!defined($enabled)) {
										$enabled = 1;
									}
								}
								if ($enabled && $playlist->{'dynamicplaylistenabled'}) {
									$currentItemGroup{'dynamicplaylistenabled'} = 1;
								} else {
									$currentItemGroup{'dynamicplaylistenabled'} = 0;
								}

								$currentLevel->{'dynamicplaylistgroup_'.$group} = \%currentItemGroup;
								$currentLevel = \%level;
							}
						}
						my %currentGroupItem = (
							'playlist' => $playlist,
							'dynamicplaylistenabled' => $playlist->{'dynamicplaylistenabled'},
							'value' => $playlist->{'dynamicplaylistid'}
						);
						$currentLevel->{$item} = \%currentGroupItem;
					}
				} else {
					my %currentItem = (
						'playlist' => $playlist,
						'dynamicplaylistenabled' => $playlist->{'dynamicplaylistenabled'},
						'value' => $playlist->{'dynamicplaylistid'}
					);
					$localPlayListItems{$item} = \%currentItem;
				}
			}
		}
	}
	use strict 'refs';
	addAlarmPlaylists(\%localPlayLists);
	$rescan = 0;

	$playLists = \%localPlayLists;
	$playListItems = \%localPlayListItems;
	#$log->debug('localPlayListItems = '.Dumper(\%localPlayListItems));

	return ($playLists, $playListItems, \%unclassifiedPlaylists, $savedstaticPlaylists);
}

sub initPlayListTypes {
	if (!$playLists || $rescan) {
		initPlayLists();
	}
	my %localPlayListTypes = ();
	for my $playlistId (keys %{$playLists}) {
		my $playlist = $playLists->{$playlistId};
		if ($playlist->{'dynamicplaylistenabled'}) {
			if (defined($playlist->{'parameters'})) {
				my $parameter1 = $playlist->{'parameters'}->{'1'};
				if (defined($parameter1)) {
					if ($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre' || $parameter1->{'type'} eq 'playlist' || $parameter1->{'type'} eq 'track' || $parameter1->{'type'} eq 'virtuallibrary') {
						$localPlayListTypes{$parameter1->{'type'}} = 1;
					} elsif ($parameter1->{'type'} =~ /^custom(.+)$/) {
						$localPlayListTypes{$1} = 1;
					}
				}
			}
		}
	}
	$playListTypes = \%localPlayListTypes;
}

sub getPlayList {
	my $client = shift;
	my $type = shift;
	return undef unless $type;

	$log->debug('Get playlist: '.$type);
	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	return undef unless $playLists;

	return $playLists->{$type};
}

# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $offset, $limit, $addOnly, $continue) = @_;
	$log->debug("Starting random selection of $limit items for type: $type");
	my $started = time();

	Slim::Utils::Timers::killTimers($client, \&findAndAdd);

	if (!defined($limit)) {
		$limit = $prefs->get('max_number_of_unplayed_tracks');
	}

	my $masterClient = masterOrSelf($client);
	my $playlist = getPlayList($client, $type);
	my $items = undef;
	my $filteredItems = undef;
	my $totalItems = undef;
	my $noOfFoundItems = 0;
	my $noOfRetriesToGetUnplayedTracks = 10;
	my $minUnplayedTracks = $prefs->get('min_number_of_unplayed_tracks');
	for (my $i = 1; $i <= $noOfRetriesToGetUnplayedTracks; $i++) {
		my $iterationStartTime = time();
		$items = getTracksForPlaylist($masterClient, $playlist, $limit, $offset + $noOfFoundItems);
		if ($items eq "error") {
			$log->error("Error trying to find tracks. Please check your playlist definition.");
			last;
		}
		next if (!defined $items || scalar(@{$items}) == 0);
		$log->debug("iteration $i returned ".(scalar @{$items}).' unfiltered '.((scalar @{$items}) == 1 ? 'item' : 'items'));

 		$items = filterTracks($masterClient, $items, $totalItems);
		$log->debug("iteration $i returned ".(scalar @{$items}).((scalar @{$items}) == 1 ? ' item' : ' items').' after filtering');

		$noOfFoundItems = $noOfFoundItems + (scalar @{$items});
		push (@{$totalItems}, @{$items});

		my $seen ||= {};
		$totalItems = [grep {!$seen->{$_}++} @{$totalItems}];
		$log->debug('total items found so far = '.scalar(@{$totalItems}));

		# if fetching tracks takes a long time but we already have more than the minimum number of tracks
		# let's start playback and get the rest of the tracks later
		if (time()-$iterationStartTime > 5 && scalar(@{$totalItems}) > $minUnplayedTracks && scalar(@{$totalItems}) < $limit) {
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 15, \&findAndAdd, $type, $offset, $limit-scalar(@{$totalItems}), 1, 0);
			last;
		}
		last if (defined $totalItems && scalar(@{$totalItems}) >= $limit);
	}
	if (!defined $totalItems || scalar(@{$totalItems}) == 0) {
		$log->info('found no tracks matching your search parameter or playist definition for dynamic playlist "'.$playlist->{'name'}.'" (query time = '.(time()-$started).' seconds).');
		return 0;
	}
	if (scalar(@{$totalItems}) > $limit) {
		$totalItems = [ @{$totalItems}[0..($limit-1)] ];
	}
	my $noOfTotalItems = scalar(@{$totalItems});
	# Pull the first track off to add / play it if needed.
	my $item = shift @{$totalItems};

	if ($item && ref($item)) {
		my $string = $item->title;
		$log->debug((($addOnly || $continue) ? 'Adding ' : 'Playing ')."$type: $string, ".($item->id));

		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute(['playlist', ($addOnly || $continue) ? 'addtracks' : 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'), $item->id)]);

		# indicate request source
		$request->source('PLUGIN_DYNAMICPLAYLIST');

		# Add the remaining items to the end
		if (! defined $limit || $limit > 1 || $totalItems > 1) {
			$log->debug('Adding '.(scalar @{$totalItems}).' tracks to end of playlist');
			if($totalItems > 1) {
				$request = $client->execute(['playlist', 'addtracks', 'listRef', $totalItems]);
				$request->source('PLUGIN_DYNAMICPLAYLIST');
			}
		}
	}
	$log->info('getting '.$noOfTotalItems.($noOfTotalItems == 1 ? ' track' : ' tracks').' for dynamic playlist "'.$playlist->{'name'}.'" took '.(time()-$started).' seconds.');
	return $noOfTotalItems;
}

sub filterTracks {
	my $client = shift;
	my $items = shift;
	my $totalItems = shift;

	# dedupe: first new items, then against total items
	if ($items && ref $items && scalar @{$items}) {
		my $seen ||= {};
		$items = [grep {!$seen->{$_}++} @{$items}];
	}
	if (defined $totalItems && scalar(@{$totalItems}) > 0) {
		my %seen;
		@seen {@{$items}} = ();
		delete @seen{@{$totalItems}};
		my $items = [keys %seen];
	}

	# add found tracks to DPL client history
	for my $item (@{$items}) {
		my $skipped = 0;
		my $addedTime = time();
		addToPlayListHistory($client, $item, $skipped, $addedTime);
		my @players = Slim::Player::Sync::slaves($client);
		foreach my $player (@players) {
			addToPlayListHistory($player, $item, $skipped, $addedTime);
		}
	}
	return \@{$items};
}

sub playRandom {
	# If addOnly, then track(s) are appended to end. Otherwise, a new playlist is created.
	my ($client, $type, $addOnly, $showFeedback, $forcedAdd, $continue) = @_;

	my $masterClient = masterOrSelf($client);

	Slim::Utils::Timers::killTimers($client, \&playRandom);

	# String to show with showBriefly
	my $string = '';
	my $playlist = getPlayList($client, $type);
	if ($playlist) {
		$string = $playlist->{'name'};
	}

	# Strings for non-track modes could be long so need some time to scroll
	my $showTime = 13;

	$log->debug('playRandom called with type '.$type);

	$masterClient->pluginData('type' => $type);
	$log->debug('pluginData type for '.$masterClient->name.' = '.$masterClient->pluginData('type'));
	$log->debug('client pref type = '.$mixInfo{$masterClient}->{'type'});

	# Whether to keep adding tracks after generating the initial playlist
	my $continuousMode = $prefs->get('keep_adding_tracks');;

	my $stopactions = undef;
	if (defined($mixInfo{$masterClient}->{'type'})) {
		my $playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
		if (defined($playlist)) {
			if (defined($playlist->{'stopactions'})) {
				$stopactions = $playlist->{'stopactions'};
			}
		}
	}

	# If this is a new mix, clear playlist history
	if (($continuousMode && (!$addOnly && !$continue)) || !$mixInfo{$masterClient} || $mixInfo{$masterClient}->{'type'} ne $type) {
		$continue = undef;
			my @players = Slim::Player::Sync::slaves($masterClient);
			push @players, $masterClient;
			clearPlayListHistory(\@players);

			# Executing actions related to new mix
			if (!$addOnly) {
				my $startactions = undef;
				if ($type ne 'disable') {
					my $playlist = getPlayList($client, $type);
					if (defined($playlist)) {
						if (defined($playlist->{'startactions'})) {
							$startactions = $playlist->{'startactions'};
						}
					}
				}
				my @actions = ();
				if (defined($stopactions)) {
					push @actions, @{$stopactions};
				}
				if (defined($startactions)) {
					push @actions, @{$startactions};
				}
				for my $action (@actions) {
					if (defined($action->{'type'}) && lc($action->{'type'}) eq 'cli' && defined($action->{'data'})) {
						$log->debug('Executing action: '.$action->{'type'}.', '.$action->{'data'});
						my @parts = split(/ /, $action->{'data'});
						my $request = $client->execute(\@parts);
						$request->source('PLUGIN_DYNAMICPLAYLIST');
					}
				}
			}
	}
	my $offset = $mixInfo{$masterClient}->{'offset'};
	if (!$mixInfo{$masterClient}->{'type'} || $mixInfo{$masterClient}->{'type'} ne $type || (!$addOnly && !$continue)) {
		$offset = 0;
	}

	my $PlaylistTrackCount = Slim::Player::Playlist::count($client);
	$log->debug('Current client playlist contains '.Slim::Player::Playlist::count($client).' tracks before adding new tracks');

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	$log->debug("$songsRemaining songs remaining, songIndex = $songIndex");
	my $minNumberUnplayedSongs = $prefs->get('min_number_of_unplayed_tracks');
	# Work out how many items need adding
	my $numItems = 0;
# my $unplayedSongsToAdd = $minNumberUnplayedSongs - $songsRemaining > 0 ? $minNumberUnplayedSongs - $songsRemaining : 0;

	if ($type ne 'disable' && ($continuousMode || !$mixInfo{$masterClient} || $mixInfo{$masterClient}->{'type'} ne $type || $songsRemaining < $minNumberUnplayedSongs)) {
		# Add new tracks if there aren't enough after the current track
		my $maxNumberUnplayedTracks = $prefs->get('max_number_of_unplayed_tracks');
		if (!$addOnly && !$continue) {
			$numItems = $maxNumberUnplayedTracks;
		} elsif ($songsRemaining < $minNumberUnplayedSongs) {
			$numItems = $maxNumberUnplayedTracks - $songsRemaining;
			$log->debug("$songsRemaining unplayed songs remaining < $minNumberUnplayedSongs minimum unplayed songs => adding ".$numItems.' new items');
		} elsif ($addOnly && $forcedAdd) {
			# Add a single track if add button is pushed when the playlist is full
			$numItems = 1;
		} else {
			$log->debug("$songsRemaining items remaining so not adding new track");
		}
	}

	my $count = 0;
	$log->debug('numItems = '.$numItems);
	if ($numItems) {
		if (!$addOnly) {
			if (Slim::Player::Source::playmode($client) ne 'stop') {
				if (UNIVERSAL::can('Slim::Utils::Alarm', 'getCurrentAlarm')) {
					my $alarm = Slim::Utils::Alarm->getCurrentAlarm($client);
					if (!defined($alarm) || !$alarm->active()) {
						my $request = $client->execute(['stop']);
						$request->source('PLUGIN_DYNAMICPLAYLIST');
					}
				} else {
					my $request = $client->execute(['stop']);
					$request->source('PLUGIN_DYNAMICPLAYLIST');
				}
			}
			if (!$client->power()) {
				my $request = $client->execute(['power', '1']);
				$request->source('PLUGIN_DYNAMICPLAYLIST');
			}
		}
		my $shuffle = Slim::Player::Playlist::shuffle($client);
		Slim::Player::Playlist::shuffle($client, 0);

		# Add tracks
		$count = findAndAdd($client,
				$type,
				$offset,
				$numItems,
				# 2nd time round just add tracks to end
				$addOnly,
				$continue);
		$log->debug('number of added items = '.$count);

		$offset += $count;
		if ($count > 0) {
			# Do a show briefly the first time things are added, or every time a new album/artist/year
			# is added
			if (!$addOnly || $type ne $mixInfo{$masterClient}->{'type'}) {
				# Don't do showBrieflys if visualiser screensavers are running as the display messes up
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly({'line' => [string($addOnly ? 'ADDING_TO_PLAYLIST' : 'NOW_PLAYING'),
										 $string]}, $showTime);
				}
			}
		} elsif ($showFeedback) {
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLIST_NOW_PLAYING_FAILED'),
										 string('PLUGIN_DYNAMICPLAYLIST_NOW_PLAYING_FAILED_LONG').' '.$string]}, $showTime);
				}
		}
		# Never show random as modified, since its a living playlist
		$client->currentPlaylistModified(0);
	}

	if ($continue) {
		my $request = $client->execute(['pause', '0']);
		$request->source('PLUGIN_DYNAMICPLAYLIST');
	}

	if ($type eq 'disable') {
		$log->debug('cyclic mode ended');
		# Don't do showBrieflys if visualiser screensavers are running as the display messes up
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLIST'), string('PLUGIN_DYNAMICPLAYLIST_DISABLED')]});
		}

		stateStop($masterClient);
		my @players = Slim::Player::Sync::slaves($masterClient);
		push @players, $masterClient;
		foreach my $player (@players) {
			stateStop($player);
		}
		clearPlayListHistory(\@players);
	} else {
		if (!$numItems || $numItems == 0 || $count > 0) {
			#$log->debug(($addOnly ? 'Adding ' : 'Playing ').($continuousMode ? 'continuous' : 'static')." $type with ".Slim::Player::Playlist::count($client).' items');
			if (!$addOnly) {
				# Record current mix type and the time it was started.
				# Do this last to prevent menu items changing too soon
				stateNew($masterClient, $type, $playlist);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateNew($player, $type, $playlist);
				}
			}
			if ($mixInfo{$masterClient}->{'type'} eq $type) {
				stateOffset($masterClient, $offset);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateOffset($player, $offset);
				}
			}
		} else {
			if (defined($stopactions)) {
				for my $action (@{$stopactions}) {
					if (defined($action->{'type'}) && lc($action->{'type'}) eq 'cli' && defined($action->{'data'})) {
						$log->debug('Executing action: '.$action->{'type'}.', '.$action->{'data'});
						my @parts = split(/ /, $action->{'data'});
						my $request = $client->execute(\@parts);
						$request->source('PLUGIN_DYNAMICPLAYLIST');
					}
				}
			}

			stateStop($masterClient);
			my @players = Slim::Player::Sync::slaves($client);
			foreach my $player (@players) {
				stateStop($player);
			}
		}
	}
	# if mode = addonly and client playlist trackcount before adding = 0,
	# you probably want to create a one-time static playlist instead of adding tracks to an existing one
	# so let's not keep these tracks in DPL history
	if ($addOnly && ($PlaylistTrackCount == 0)) {
		$masterClient->pluginData('type' => '');
		my @players = Slim::Player::Sync::slaves($masterClient);
		push @players, $masterClient;
		clearPlayListHistory(\@players);
	}
}

sub stateOffset {
	my $client = shift;
	my $offset = shift;

	$mixInfo{$client}->{'offset'} = $offset;
	$prefs->client($client)->set('offset', $offset);
}

sub stateNew {
	my $client = shift;
	my $type = shift;
	my $playlist = shift;

	Slim::Utils::Timers::killTimers($client, \&findAndAdd);
	$mixInfo{$client}->{'type'} = $type;
	$prefs->client($client)->set('playlist', $type);
	if (defined($playlist->{'parameters'})) {
		$prefs->client($client)->remove('playlist_parameters');
		my %storeParams = ();
		for my $p (keys %{$playlist->{'parameters'}}) {
			if (defined($playlist->{'parameters'}->{$p})) {
				$storeParams{$p}=$playlist->{'parameters'}->{$p}->{'value'};
			}
		}
		$prefs->client($client)->set('playlist_parameters', \%storeParams);
	} else {
		$prefs->client($client)->remove('playlist_parameters');
	}
}

sub stateContinue {
	my $client = shift;
	my $type = shift;
	my $offset = shift;
	my $parameters = shift;

	$mixInfo{$client}->{'type'} = $type;
	$prefs->client($client)->set('playlist', $type);
	if (defined($offset)) {
		$mixInfo{$client}->{'offset'} = $offset;
	} else {
		$mixInfo{$client}->{'offset'} = undef;
	}
	if (defined($parameters)) {
		$prefs->client($client)->remove('playlist_parameters');
		$prefs->client($client)->set('playlist_parameters', $parameters);
	} else {
		$prefs->client($client)->remove('playlist_parameters');
	}
}

sub stateStop {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&findAndAdd);
	$mixInfo{$client} = undef;
	$prefs->client($client)->remove('playlist');
	$prefs->client($client)->remove('playlist_parameters');
	$prefs->client($client)->remove('offset');
	my $masterClient = masterOrSelf($client);
	$masterClient->pluginData('type' => '');
}

# Do what's necessary when play or add button is pressed
sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	$log->debug(($add ? 'Add' : 'Play')."$item");

	my $masterClient = masterOrSelf($client);

	# Clear any current mix type in case user is restarting an already playing mix
	stateStop($masterClient);
	my @players = Slim::Player::Sync::slaves($client);
	foreach my $player (@players) {
		stateStop($player);
	}

	# Go go go!
	playRandom($client, $item, $add, 1, 1);
}

sub getCurrentPlayList {
	my $client = shift;

	my $masterClient = masterOrSelf($client);

	if (defined($client) && $mixInfo{$masterClient}) {
		return $mixInfo{$masterClient}->{'type'};
	}
	return undef;
}

sub addAlarmPlaylists {
	my $localPlayLists = shift;

	if (UNIVERSAL::can('Slim::Utils::Alarm', 'addPlaylists')) {
		my @alarmPlaylists = ();
		for my $playlist (values %{$localPlayLists}) {
			my $favs = Slim::Utils::Favorites->new();
			my ($index, $hk) = $favs->findUrl('dynamicplaylist://'.$playlist->{'dynamicplaylistid'});
			my $favorite = 0;
			if (defined($index)) {
				$favorite = 1;
			}

			if (!defined($playlist->{'parameters'}) && ($playlist->{'dynamicplaylistfavourite'} || $favorite)) {
				if (defined($playlist->{'groups'})) {
					my $groups = $playlist->{'groups'};
					for my $subgroup (@{$groups}) {
						my $group = '';
						for my $subgroup (@{$subgroup}) {
							$group .= $subgroup.'/';
						}
						my %entry = (
							'url' => 'dynamicplaylist://'.$playlist->{'dynamicplaylistid'},
							'title' => $group.$playlist->{'name'},
						);
						push @alarmPlaylists, \%entry;
					}
				} else {
					my %entry = (
						'url' => 'dynamicplaylist://'.$playlist->{'dynamicplaylistid'},
						'title' => $playlist->{'name'},
					);
					push @alarmPlaylists, \%entry;
				}
			}
		}
		@alarmPlaylists = sort {lc($a->{'title'}) cmp lc($b->{'title'})} @alarmPlaylists;
		$log->debug('Adding '.scalar(@alarmPlaylists).' playlists to alarm handler');
		Slim::Utils::Alarm->addPlaylists('PLUGIN_DYNAMICPLAYLIST', \@alarmPlaylists);
	}
}

sub addParameterValues {
	my $client = shift;
	my $listRef = shift;
	my $parameter = shift;
	my $parameterValues = shift;

	$log->debug('Getting values for '.$parameter->{'name'}.' of type '.$parameter->{'type'});
	my $sql = undef;
	if (lc($parameter->{'type'}) eq 'album') {
		$sql = "select id, title, substr(titlesort,1,1) from albums order by titlesort";
	} elsif (lc($parameter->{'type'}) eq 'artist') {
		$sql = "select id, name, substr(namesort,1,1) from contributors where namesort is not null order by namesort";
	} elsif (lc($parameter->{'type'}) eq 'genre') {
		$sql = "select id, name, substr(namesort,1,1) from genres order by namesort";
	} elsif (lc($parameter->{'type'}) eq 'year') {
		$sql = "select year, case when year > 0 then year else 'Unknown' end from tracks where year is not null group by year order by year desc";
	} elsif (lc($parameter->{'type'}) eq 'playlist') {
		$sql = "select playlist_track.playlist, tracks.title, substr(tracks.titlesort,1,1) from tracks, playlist_track where tracks.id=playlist_track.playlist group by playlist_track.playlist order by titlesort";
	} elsif (lc($parameter->{'type'}) eq 'track') {
		$sql = "select tracks.id, concat(albums.title, ' ', tracks.tracknum, '. ', tracks.title), substr(tracks.titlesort,1,1) from tracks, albums where tracks.album=albums.id and audio=1 group by tracks.id order by albums.titlesort, albums.disc, tracks.tracknum";
	} elsif (lc($parameter->{'type'}) eq 'list') {
		my $value = $parameter->{'definition'};
		if (defined($value) && $value ne '') {
			my @values = split(/,/, $value);
			if (@values) {
				for my $valueItem (@values) {
					my @valueItemArray = split(/:/, $valueItem);
					my $id = shift @valueItemArray;
					my $name = shift @valueItemArray;
					my $sortlink = shift @valueItemArray;

					if (defined($id)) {
						my %listitem = (
							'id' => $id,
							'value' => $id
						);
						if (defined($name)) {
							$listitem{'name'}=$name;
						} else {
							$listitem{'name'}=$id;
						}
						if (defined($sortlink)) {
							$listitem{'sortlink'}=$sortlink;
						}
						push @{$listRef}, \%listitem;
					}
				}
			} else {
				$log->warn("Error, invalid parameter value: $value");
			}
		}
 	} elsif (lc($parameter->{'type'}) eq 'virtuallibrary') {

			my $VLs = getVirtualLibraries();
			foreach my $thisVL (@{$VLs}) {
				push @{$listRef}, $thisVL;
			}
			$log->debug('virtual library listRef array = '.Dumper($listRef));
	} elsif (lc($parameter->{'type'}) eq 'custom' || lc($parameter->{'type'}) =~ /^custom(.+)$/) {
		if (defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/) {
			$sql = $parameter->{'definition'};
			for (my $i=1; $i < $parameter->{'id'}; $i++) {
				my $value = undef;
				if (defined($parameterValues)) {
					$value = $parameterValues->{$i};
				} else {
					my $parameter = $client->modeParam('dynamicplaylist_parameter_'.$i);
					$value = $parameter->{'id'};
				}
				my $parameterid = "\'PlaylistParameter".$i."\'";
				$log->debug('Replacing '.$parameterid.' with '.$value);
				$sql =~ s/$parameterid/$value/g;
			}
		}
	}

	if (defined($sql)) {
		my $dbh = getCurrentDBH();
		my $paramType = lc($parameter->{'type'});
		$log->debug('parameter type = '.lc($parameter->{'type'}));
		eval {
			my $sth = $dbh->prepare($sql);
			$log->debug("Executing value list: $sql");
			$sth->execute() or do {
				$log->warn("Error executing: $sql");
				$sql = undef;
			};
			if (defined($sql)) {
				my $id;
				my $name;
				my $sortlink = undef;
				if (($paramType eq 'customdecade') || ($paramType eq 'customdecadechained') || ($paramType eq 'year')) {
					eval {
						$sth->bind_columns(undef, \$id, \$name);
					};
				} else {
					eval {
						$sth->bind_columns(undef, \$id, \$name, \$sortlink);
					};
				}
				if ($@) {
					$sth->bind_columns(undef, \$id, \$name);
				}
				while ($sth->fetch()) {
					my %listitem = (
						'id' => $id,
						'value' => $id,
						'name' => Slim::Utils::Unicode::utf8decode($name, 'utf8')
					);
					if (defined($sortlink)) {
						$listitem{'sortlink'} = Slim::Utils::Unicode::utf8decode($sortlink, 'utf8');
					}
					push @{$listRef}, \%listitem;
				}
				if (($paramType eq 'customdecadechained') || ($paramType eq 'customgenrechained')) {
					unshift @{$listRef}, {'id' => '999999999', 'value' => 999999999, 'name' => 'any'};
				}
				$log->debug('Added '.scalar(@{$listRef}).' items to value list');
			}
			$sth->finish();
		};
		if ($@) {
			$log->warn("Database error: $DBI::errstr");
		}
	}
}

sub getVirtualLibraries {
	my (@items, @hiddenVLs);
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	$log->debug("ALL virtual libraries: ".Dumper($libraries));

	my $localonlyname = Slim::Music::VirtualLibraries->getNameForId("localTracksOnly");
	my $preferlocalname = Slim::Music::VirtualLibraries->getNameForId("preferLocalLibraryOnly");

	my %hiddenVLs;
	if ((defined $localonlyname) && ($localonlyname ne '') && (defined $preferlocalname) && ($preferlocalname ne '')) {
		%hiddenVLs = map {
		$_ => 1
		} ("Ratings Light - Rated Tracks", "Ratings Light - Top Rated Tracks", $preferlocalname, $localonlyname);
	} else {
		%hiddenVLs = map {
		$_ => 1
		} ("Ratings Light - Rated Tracks", "Ratings Light - Top Rated Tracks");
	}
	$log->debug("hidden libraries: ".Dumper(\%hiddenVLs));

	while (my ($k, $v) = each %{$libraries}) {
		my $count = Slim::Utils::Misc::delimitThousands(Slim::Music::VirtualLibraries->getTrackCount($k));
		my $name = Slim::Music::VirtualLibraries->getNameForId($k);
		$log->debug("VL: ".$name." (".$count.")");

		unless ($hiddenVLs{$name}) {
			push @items, {
				name => Slim::Utils::Unicode::utf8decode($name, 'utf8')." (".$count.($count eq '1' ? " track)" : " tracks)"),
				sortName => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
				value => "'".$k."'",
				id => "'".$k."'",
			};
		}
	}
	if (scalar @items == 0) {
		push @items, {
			name => "complete library",
			sortName => "complete library",
			value => "\'\'",
			id => "\'\'",
		};
	}

	if (scalar @items > 1) {
		@items = sort { $a->{sortName} cmp $b->{sortName} } @items;
	}
	return \@items;
}

sub getTracksForPlaylist {
	my $client = shift;
	my $playlist = shift;
	my $limit = shift;
	my $offset = shift;
	my @result;

	my $id = $playlist->{'dynamicplaylistid'};
	my $plugin = $plugins{$id};
	$log->debug("Calling: $plugin with: $id , $limit , $offset");
	my $result;
	no strict 'refs';
	if (UNIVERSAL::can("$plugin", 'getNextDynamicPlayListTracks')) {
		my %parameterHash;
		if (defined($playlist->{'parameters'})) {
			my $parameters = $playlist->{'parameters'};
			%parameterHash = ();
			foreach my $pk (keys %{$parameters}) {
				if (defined($parameters->{$pk}->{'value'})) {
					my %parameter = (
						'id' => $parameters->{$pk}->{'id'},
						'value' => $parameters->{$pk}->{'value'}
					);
					$parameterHash{$pk} = \%parameter;
				}
			}
		}
		$log->debug("Calling: $plugin :: getNextDynamicPlayListTracks");
		$result = eval {&{"${plugin}::getNextDynamicPlayListTracks"}($client, $playlist, $limit, $offset, \%parameterHash)};
		if ($@) {
			$log->debug("Error getting tracks from $plugin: $@");
			return "error";
		} else {
			$log->debug('Found '.scalar(@{$result}).(scalar(@{$result}) == 1 ? ' track ' : ' tracks ').'for playlist \''.$playlist->{'name'}.'\'');
		}
	}

	use strict 'refs';
	return $result;
}



## for VFD devices ##

sub setModeMixer {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	my $masterClient = masterOrSelf($client);
	my %customsortnames = ($prefs->get('favouritesname') => '00001_Favourites', 'Songs' => '00002_Songs', 'Artists' => '00003_Artists', 'Albums' => '00004_Albums', 'Genres' => '00005_Genres', 'Years' => '00006_Years', 'Playlists' => '00007_PLaylists', 'Static Playlists' => '00008_static_LMS_playlists', 'Not classified' => '00009_not_classified', 'Context menu lists' => '00010_contextmenulists');

	my @listRef = ();
	initPlayLists($client);
	initPlayListTypes();
	my $playlisttype = $client->modeParam('playlisttype');
	my $showFlat = $prefs->get('flatlist');
	if ($showFlat || defined($client->modeParam('flatlist'))) {
		foreach my $flatItem (sort keys %{$playLists}) {
			my $playlist = $playLists->{$flatItem};
			if ($playlist->{'dynamicplaylistenabled'}) {
				my %flatPlaylistItem = (
					'playlist' => $playlist,
					'dynamicplaylistenabled' => 1,
					'value' => $playlist->{'dynamicplaylistid'}
				);
				if (!defined($playlisttype)) {
					push @listRef, \%flatPlaylistItem;
				} else {
					if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype))) {
						push @listRef, \%flatPlaylistItem;
					}
				}
			}
		}
	} else {
		foreach my $menuItemKey (sort keys %{$playListItems}) {
			if ($playListItems->{$menuItemKey}->{'dynamicplaylistenabled'}) {
				if (!defined($playlisttype)) {
					if (!defined $playListItems->{$menuItemKey}->{'playlist'} && $customsortnames{$playListItems->{$menuItemKey}->{'name'}}) {
						$playListItems->{$menuItemKey}->{'sortname'} = $customsortnames{$playListItems->{$menuItemKey}->{'name'}};
					} else {
						$playListItems->{$menuItemKey}->{'playlist'}->{'sortname'} = $playListItems->{$menuItemKey}->{'playlist'}->{'name'};
					}
					push @listRef, $playListItems->{$menuItemKey};
			} else {
					if (defined($playListItems->{$menuItemKey}->{'playlist'})) {
						my $playlist = $playListItems->{$menuItemKey}->{'playlist'};
						if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype))) {
							if ($playlist->{'name'}) {
								$playlist->{'sortname'} = $playlist->{'name'};
							}
							push @listRef, $playListItems->{$menuItemKey};
						}
					} else {
						if ($customsortnames{$playListItems->{$menuItemKey}->{'name'}}) {
							$playListItems->{$menuItemKey}->{'sortname'} = $customsortnames{$playListItems->{$menuItemKey}->{'name'}};
						}
						push @listRef, $playListItems->{$menuItemKey};
					}
				}
			}
		}
		my $playlistgroup = $client->modeParam('selectedgroup');
		if ($playlistgroup) {
			my @playlistGroups = split(/\//, $playlistgroup);
			if (enterSelectedGroup($client, \@listRef, \@playlistGroups)) {
				return;
			}
		}
	}

	@listRef = sort {
		if (defined($a->{'sortname'}) && defined($b->{'sortname'})) {
			return lc($a->{'sortname'}) cmp lc($b->{'sortname'});
		}
		if (defined($a->{'sortname'}) && !defined($b->{'sortname'})) {
			return lc($a->{'sortname'}) cmp lc($b->{'playlist'}->{'sortname'});
		}
		if (!defined($a->{'sortname'}) && defined($b->{'sortname'})) {
			return lc($a->{'playlist'}->{'sortname'}) cmp lc($b->{'sortname'});
		}
		return lc($a->{'playlist'}->{'sortname'}) cmp lc($b->{'playlist'}->{'sortname'})
	} @listRef;

	# use PLUGIN.DynamicPlayList.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_DYNAMICPLAYLIST} {count}',
		listRef => \@listRef,
		name => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName => 'PLUGIN.DynamicPlayList',
		onPlay => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if (defined($client->modeParam('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
					}
					requestFirstParameter($client, $playlist, 0, \%parameterValues);
				} else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
				}
			}
		},
		onAdd => sub {
			my ($client, $item) = @_;
			my $playlist = $item->{'playlist'};
			if (defined($item->{'playlist'})) {
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if (defined($client->modeParam('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
					}
					requestFirstParameter($client, $playlist, 1, \%parameterValues);
				} else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 1);
				}
			}
		},
		onRight => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} eq 'disable') {
				handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
			} elsif (defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
			} elsif (defined($item->{'playlist'}) && defined($item->{'playlist'}->{'parameters'})) {
				my %parameterValues = ();
				my $i = 1;
				while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
					$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
					$i++;
				}
				if (defined($client->modeParam('extrapopmode'))) {
					$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
				}
				requestFirstParameter($client, $item->{'playlist'}, 0, \%parameterValues)
			} else {
				$client->bumpRight();
			}
		},
		onFavorites	=> sub {
			my ($client, $item, $arg) = @_;
			if (defined $arg && $arg =~ /^add$|^add(\d+)/) {
				addFavorite($client, $item, $1);
			} elsif (Slim::Buttons::Common::mode($client) ne 'FAVORITES') {
				Slim::Buttons::Common::setMode($client, 'home');
				Slim::Buttons::Home::jump($client, 'FAVORITES');
				Slim::Buttons::Common::pushModeLeft($client, 'FAVORITES');
				}
		},
	);
	my $i=1;
	while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
		$i++;
	}
	if (defined($client->modeParam('extrapopmode'))) {
		$params{'extrapopmode'} = $client->modeParam('extrapopmode');
	}

	# if we have an active mode, temporarily add the disable option to the list.
	if ($mixInfo{$masterClient} && $mixInfo{$masterClient}->{'type'} ne '') {
		push @{$params{listRef}}, \%disable;
	}

	Slim::Buttons::Common::pushMode($client, 'PLUGIN.DynamicPlayList.Choice', \%params);
}

sub addFavorite {
	my ($client, $item, $hotkey) = @_;
	if (Slim::Utils::Favorites->enabled && defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} ne 'disable' && !defined($item->{'playlist'}->{'parameters'})) {
		my $url = 'dynamicplaylist://'.$item->{'playlist'}->{'dynamicplaylistid'};
		my $favs = Slim::Utils::Favorites->new($client);
		my ($index, $hk) = $favs->findUrl($url);
		if (!defined($index)) {
			if (defined $hotkey) {
				my $oldindex = $favs->hasHotkey($hotkey);
				$favs->setHotkey($oldindex, undef) if defined $oldindex;
				my $newindex = $favs->add($url, $item->{'playlist'}->{'name'}, 'audio');
				$favs->setHotkey($newindex, $hotkey);
			} else {
				my (undef, $hotkey) = $favs->add($url, $item->{'playlist'}->{'name'}, 'audio', undef, 'hotkey');
			}

			$client->showBriefly({
				'line' => [$client->string('FAVORITES_ADDING'), $item->{'playlist'}->{'name'}]
			});
		} elsif (defined($hotkey)) {
			$favs->setHotkey($index, undef);
			$favs->setHotkey($index, $hotkey);

			$client->showBriefly({
				'line' => [$client->string('FAVORITES_ADDING'), $item->{'playlist'}->{'name'}]
			});
		} else {
			$log->debug('Already exists as a favorite');
		}
	} else {
		$log->warn('Favorites not supported on this item');
	}
}

sub setMode {
	my $class = shift;
	my $client = shift;
	my $method = shift;

	setModeMixer($client, $method);
}

sub enterSelectedGroup {
	my $client = shift;
	my $listRef = shift;
	my $selectedGroups = shift;

	my $currentGroup = shift @{$selectedGroups};
	for my $item (@{$listRef}) {
		if (!defined($item->{'playlist'}) && defined($item->{'childs'}) && $item->{'name'} eq $currentGroup) {
			if (scalar(@{$selectedGroups}) > 0) {
				my @itemArray = ();
				for my $key (%{$item->{'childs'}}) {
					push @itemArray, $item->{'childs'}->{$key};
				}
				return enterSelectedGroup($client, \@itemArray, $selectedGroups);
			} else {
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
				return 1;
			}
		}
	}
	return undef;
}

sub setModeChooseParameters {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $parameterId = $client->modeParam('dynamicplaylist_nextparameter');
	my $playlist = $client->modeParam('dynamicplaylist_selectedplaylist');
	if (!defined($playlist)) {
		my $playlistId = $client->modeParam('dynamicplaylist_selectedplaylistid');
		if (defined($playlistId)) {
			$playlist = getPlayList($client, $playlistId);
		}
	}

	my $parameter= $playlist->{'parameters'}->{$parameterId};

	my @listRef = ();
	addParameterValues($client, \@listRef, $parameter);
	my $sorted = '0';
	if (scalar(@listRef) > 0) {
		my $firstItem = @listRef[0];
		if (defined($firstItem->{'sortlink'})) {
			$sorted = 'L';
		}
	}
	my $name = $parameter->{'name'};
	my %params = (
		header => "$name {count}",
		listRef => \@listRef,
		lookupRef => sub {
				my ($index) = @_;
				my $sortListRef = Slim::Buttons::Common::param($client, 'listRef');
				my $sortItem = $sortListRef->[$index];
				if (defined($sortItem->{'sortlink'})) {
					return $sortItem->{'sortlink'};
				} else {
					return $sortItem->{'name'};
				}
			},
		isSorted => $sorted,
		name => \&getChooseParametersDisplayText,
		overlayRef => \&getChooseParametersOverlay,
		modeName => 'PLUGIN.DynamicPlayList.ChooseParameters',
		onRight => sub {
			my ($client, $item) = @_;
			requestNextParameter($client, $item, $parameterId, $playlist);
		},
		onPlay => sub {
			my ($client, $item) = @_;
			requestNextParameter($client, $item, $parameterId, $playlist, 0);
		},
		onAdd => sub {
			my ($client, $item) = @_;
			requestNextParameter($client, $item, $parameterId, $playlist, 1);
		},
		dynamicplaylist_nextparameter => $parameterId,
		dynamicplaylist_selectedplaylist => $playlist,
		dynamicplaylist_addonly => $client->modeParam('dynamicplaylist_addonly')
	);
	for(my $i=1; $i < $parameterId; $i++) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
	}
	if (defined($client->modeParam('extrapopmode'))) {
		$params{'extrapopmode'} = $client->modeParam('extrapopmode');
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getSetModeDataForSubItems {
	my $client = shift;
	my $currentItem = shift;
	my $items = shift;

	my @listRefSub = ();
	foreach my $menuItemKey (sort keys %{$items}) {
		if ($items->{$menuItemKey}->{'dynamicplaylistenabled'}) {
			my $playlisttype = $client->modeParam('playlisttype');
			if (!defined($playlisttype)) {
				push @listRefSub, $items->{$menuItemKey};
			} else {
				if (defined($items->{$menuItemKey}->{'playlist'})) {
					my $playlist = $items->{$menuItemKey}->{'playlist'};
					if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype))) {
						push @listRefSub, $items->{$menuItemKey};
					}
				} else {
					push @listRefSub, $items->{$menuItemKey};
				}
			}
		}
	}

	@listRefSub = sort {
		if (defined($a->{'dynamicplaylistid'}) && defined($b->{'dynamicplaylistid'})) {
			return lc($a->{'dynamicplaylistid'}) cmp lc($b->{'dynamicplaylistid'});
		}
		if (defined($a->{'playlist'}->{'dynamicplaylistid'}) && defined($b->{'playlist'}->{'dynamicplaylistid'})) {
			return lc($a->{'playlist'}->{'dynamicplaylistid'}) cmp lc($b->{'playlist'}->{'dynamicplaylistid'});
		}
		if (defined($a->{'name'}) && defined($b->{'name'})) {
			return lc($a->{'name'}) cmp lc($b->{'name'});
		}
		if (defined($a->{'name'}) && !defined($b->{'name'})) {
			return lc($a->{'name'}) cmp lc($b->{'playlist'}->{'name'});
		}
		if (!defined($a->{'name'}) && defined($b->{'name'})) {
			return lc($a->{'playlist'}->{'name'}) cmp lc($b->{'name'});
		}
		return lc($a->{'playlist'}->{'name'}) cmp lc($b->{'playlist'}->{'name'})
	} @listRefSub;

	my %params = (
		header => '{PLUGIN_DYNAMICPLAYLIST} {count}',
		listRef => \@listRefSub,
		name => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName => 'PLUGIN.DynamicPlayList'.$currentItem->{'value'},
		onPlay => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if (defined($client->modeParam('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
					}
					requestFirstParameter($client, $playlist, 0, \%parameterValues);
				} else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
				}
			}
		},
		onAdd => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i=1;
					while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
						$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
						$i++;
					}
					if (defined($client->modeParam('extrapopmode'))) {
						$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
					}
					requestFirstParameter($client, $playlist, 1, \%parameterValues);
				} else {
					handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 1);
				}
			}
		},
		onRight => sub {
			my ($client, $item) = @_;
			if (defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
			} elsif (defined($item->{'playlist'}) && defined($item->{'playlist'}->{'parameters'})) {
				my %parameterValues = ();
				my $i=1;
				while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
					$parameterValues{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
					$i++;
				}
				if (defined($client->modeParam('extrapopmode'))) {
					$parameterValues{'extrapopmode'} = $client->modeParam('extrapopmode');
				}
				requestFirstParameter($client, $item->{'playlist'}, 0, \%parameterValues);
			} else {
				$client->bumpRight();
			}
		},
		onFavorites	=> sub {
			my ($client, $item, $arg) = @_;
			if (defined $arg && $arg =~ /^add$|^add(\d+)/) {
				addFavorite($client, $item, $1);
			} elsif (Slim::Buttons::Common::mode($client) ne 'FAVORITES') {
				Slim::Buttons::Common::setMode($client, 'home');
				Slim::Buttons::Home::jump($client, 'FAVORITES');
				Slim::Buttons::Common::pushModeLeft($client, 'FAVORITES');
			}
		},
	);
	return \%params;
}

sub requestNextParameter {
	my $client = shift;
	my $item = shift;
	my $parameterId = shift;
	my $playlist = shift;
	my $addOnly = shift;

	if (!defined($addOnly)) {
		$addOnly = $client->modeParam('dynamicplaylist_addonly');
	}
	$client->modeParam('dynamicplaylist_parameter_'.$parameterId, $item);
	if (defined($playlist->{'parameters'}->{$parameterId + 1})) {
		my %nextParameter = (
			'dynamicplaylist_nextparameter' => $parameterId + 1,
			'dynamicplaylist_selectedplaylist' => $playlist,
			'dynamicplaylist_addonly' => $addOnly
		);
		my $i;
		for($i = 1; $i <= $parameterId; $i++) {
			$nextParameter{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
		}
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.ChooseParameters', \%nextParameter);
	} else {
		for(my $i = 1; $i <= $parameterId; $i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
		}
		handlePlayOrAdd($client, $playlist->{'dynamicplaylistid'}, $addOnly);
		my $noOfLevels = $parameterId + 1;
		if (defined($client->modeParam('extrapopmode'))) {
			$noOfLevels++;
		}
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time(), \&stepOut, $noOfLevels);
		$client->update();
	}
}

sub requestFirstParameter {
	my $client = shift;
	my $playlist = shift;
	my $addOnly = shift;
	my $params = shift;

	my %nextParameters = (
		'dynamicplaylist_selectedplaylist' => $playlist,
		'dynamicplaylist_addonly' => $addOnly
	);
	foreach my $pk (keys %{$params}) {
		$nextParameters{$pk} = $params->{$pk};
	}
	my $i = 1;
	while (defined($nextParameters{'dynamicplaylist_parameter_'.$i})) {
		$i++;
	}
	$nextParameters{'dynamicplaylist_nextparameter'}=$i;

	if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{$nextParameters{'dynamicplaylist_nextparameter'}})) {
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.ChooseParameters', \%nextParameters);
	} else {
		for($i=1; $i < $nextParameters{'dynamicplaylist_nextparameter'}; $i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $params->{'dynamicplaylist_parameter_'.$i}->{'id'};
		}
		handlePlayOrAdd($client, $playlist->{'dynamicplaylistid'}, $addOnly);
		my $noOfLevels = $nextParameters{'dynamicplaylist_nextparameter'};
		if (defined($nextParameters{'extrapopmode'})) {
			$noOfLevels++;
		}
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time(), \&stepOut, $noOfLevels);
		$client->update();
	}
}

sub stepOut {
	my $client = shift;
	my $noOfSteps = shift;
	for(my $i = 1; $i < $noOfSteps; $i++) {
		Slim::Buttons::Common::popMode($client);
	}
	$client->update();
}

# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;
	my $masterClient = masterOrSelf($client);

	my $id = undef;
	my $name = '';
	if ($item) {
		$name = $item->{'name'};
		if ($name eq '' && defined($item->{'playlist'})) {
			$name = $item->{'playlist'}->{'name'};
			$id = $item->{'playlist'}->{'dynamicplaylistid'};
		}
	}

	# if showing the current mode, show altered string
	if ($mixInfo{$masterClient} && defined($mixInfo{$masterClient}->{'type'}) && $id eq $mixInfo{$masterClient}->{'type'}) {
		return $name.' ('.string('PLUGIN_DYNAMICPLAYLIST_PLAYING').')';

	# if a mode is active, handle the temporarily added disable option
	} elsif ($id eq 'disable' && $mixInfo{$masterClient}) {
		return string('PLUGIN_DYNAMICPLAYLIST_PRESS_RIGHT');
	} else {
		return $name;
	}
}

sub getChooseParametersDisplayText {
	my ($client, $item) = @_;

	my $name = '';
	if ($item) {
		$name = $item->{'name'};
	}
	return $name;
}

# Returns the overlay to be displayed next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	my $masterClient = masterOrSelf($client);

	# Put the right arrow by genre filter and notesymbol by mixes
	if (defined($item->{'childs'})) {
		return [$client->symbols('rightarrow'), undef];
	} elsif (defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} eq 'disable') {
		return [undef, $client->symbols('rightarrow')];
	} elsif (!defined($item->{'playlist'})) {
		return [undef, $client->symbols('rightarrow')];
	} elsif (!defined($mixInfo{$masterClient}) || !defined($mixInfo{$masterClient}->{'type'}) || $item->{'playlist'}->{'dynamicplaylistid'} ne $mixInfo{$masterClient}->{'type'}) {
		if (defined($item->{'playlist'}->{'parameters'})) {
			return [$client->symbols('rightarrow'), $client->symbols('notesymbol')];
		} else {
			return [undef, $client->symbols('notesymbol')];
		}
	} elsif (defined($item->{'playlist'}->{'parameters'})) {
		return [$client->symbols('rightarrow'), undef];
	}
	return [undef, undef];
}

sub getChooseParametersOverlay {
	my ($client, $item) = @_;

	return [undef, $client->symbols('rightarrow')];
}


# misc

sub powerCallback {
	my $request = shift;
	my $client = $request->client();

	return if !defined $client;

	if ($request->getParam('_newvalue')) {
		if ($prefs->get('rememberactiveplaylist')) {
			continuePreviousPlaylist($client);
		}
	}
}

sub clientNewCallback {
	my $request = shift;
	my $client = $request->client();

	return if !defined $client;

	if ($prefs->get('rememberactiveplaylist')) {
		continuePreviousPlaylist($client);
	}
}

sub rescanDone {
	my $request = shift;
	my $client = $request->client();

	$rescan = 1;
	if ($deleteAllQueues) {
		$log->debug('Clearing play history for all players');
		clearPlayListHistory();
		$deleteAllQueues = 0;
		$deleteQueue = {};
	} elsif (scalar(keys %{$deleteQueue}) > 0) {
		my @clients = ();
		foreach my $clientId (keys %{$deleteQueue}) {
			my $deleteClient = Slim::Player::Client::getClient($clientId);
			push @clients, $deleteClient;
			$log->debug('Clearing play history for player: '.$deleteClient->name);
		}
		clearPlayListHistory(\@clients);
		$deleteQueue = {};
	}

	if (scalar(keys %{$historyQueue}) > 0) {
		foreach my $clientId (keys %{$historyQueue}) {
			my $addedClient = Slim::Player::Client::getClient($clientId);
			my $queue = $historyQueue->{$clientId};
			if (scalar(@{$queue}) > 0) {
				foreach my $item (@{$queue}) {
					my $track = Slim::Schema->objectForUrl({
							'url' => $item->{'url'},
						});
					if (defined($track)) {
						$log->debug('Added play history of track: '.$item->{'url'});
						addToPlayListHistory($addedClient, $track, $item->{'skipped'}, $item->{'addedTime'});
					}
				}
			}
		}
		$historyQueue = {};
	}
}

sub continuePreviousPlaylist {
	my $client = shift;
	my $masterClient = masterOrSelf($client);

	my $type = $prefs->client($masterClient)->get('playlist');
	if (defined($type)) {
		my $offset = $prefs->client($masterClient)->get('offset');
		$log->debug("Continuing playing playlist: $type on ".$client->name);
		my $parameters = $prefs->client($masterClient)->get('playlist_parameters');

		my $playlist = getPlayList($client, $type);
		if (defined($playlist->{'parameters'})) {
			foreach my $p (keys %{$playlist->{'parameters'}}) {
				if (defined($playlist->{'parameters'}->{$p})) {
					$playlist->{'parameters'}->{$p}->{'value'} = $parameters->{$p};
				}
			}
		}

		stateContinue($masterClient, $type, $offset, $parameters);
		my @players = Slim::Player::Sync::slaves($client);
		foreach my $player (@players) {
			stateContinue($player, $type, $offset, $parameters);
		}
	} else {
		$log->debug('No previously playing playlist');
	}
}

sub commandCallback65 {
	my $request = shift;

	my $client = $request->client();
	my $masterClient = masterOrSelf($client);

	if (defined($request->source()) && $request->source() eq 'PLUGIN_DYNAMICPLAYLIST') {
		return;
	} elsif (defined($request->source())) {
		$log->debug('received command initiated by '.$request->source());
	}
	if ($request->isCommand([['playlist'], ['play']])) {
		my $url = $request->getParam('_item');
		if ($url =~ /^dynamicplaylist:\/\//) {
			$log->debug('Skipping '.$request->getRequestString()." $url");
			return;
		}
	}

	$log->debug('received command '.($request->getRequestString()));

	# because of the filter this should never happen
	# in addition there are valid commands (rescan f.e.) that have no
	# client so the bt() is strange here
	if (!defined $masterClient || !defined $mixInfo{$masterClient}->{'type'}) {
		return;
	}
	$log->debug('while in mode: '.($mixInfo{$masterClient}->{'type'}).', from '.($client->name));

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']])
		|| $request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex) {

		if ($request->isCommand([['playlist'], ['newsong']])) {
			if ($masterClient->id ne $client->id) {
				$log->debug('Ignoring event, this is a slave player');
				return;
			}
			$log->debug("new song detected ($songIndex)");
		} else {
			$log->debug('deletion detected ('.($request->getParam('_index')).')');
		}

		my $songsToKeep = $prefs->get('number_of_played_tracks_to_keep');
		if ($songIndex && $songsToKeep ne '') {
			$log->debug('Stripping off completed track(s)');

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_DYNAMICPLAYLIST');
			}
		}

		my $songAddingCheckDelay = $prefs->get('song_adding_check_delay') || 0;
		my $songIndex = Slim::Player::Source::streamingSongIndex($client);
		my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
		if ($songAddingCheckDelay && $songsRemaining > 0) {
			$log->debug("Will check in $songAddingCheckDelay seconds if new songs have to be added");
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $songAddingCheckDelay, \&playRandom, $mixInfo{$masterClient}->{'type'}, 1, 0);
		} else {
			playRandom($client, $mixInfo{$masterClient}->{'type'}, 1, 0);
		}
	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		$log->debug('cyclic mode ending due to playlist: '.($request->getRequestString()).' command');
		playRandom($client, 'disable');
	}
}

sub mixable {
	my $class = shift;
	my $item = shift;
	my $blessed = blessed($item);

	if (!$playListTypes) {
		initPlayListTypes();
	}

	if (!$blessed) {
		if (ref($item) eq 'HASH' && defined($item->{'type'})) {
			return 1 if ($playListTypes->{$item->{'type'}});
		} else {
			return undef;
		}
	} elsif ($blessed eq 'Slim::Schema::Track') {
		return 1 if ($playListTypes->{'track'});
	} elsif ($blessed eq 'Slim::Schema::Year') {
		return 1 if ($playListTypes->{'year'} && $item->id);
	} elsif ($blessed eq 'Slim::Schema::Album') {
		return 1 if ($playListTypes->{'album'});
	} elsif ($blessed eq 'Slim::Schema::Age') {
		return 1 if ($playListTypes->{'album'});
	} elsif ($blessed eq 'Slim::Schema::Contributor') {
		return 1 if ($playListTypes->{'artist'} && Slim::Schema->variousArtistsObject->id ne $item->id);
	} elsif ($blessed eq 'Slim::Schema::Genre') {
		return 1 if ($playListTypes->{'genre'});
	} elsif ($blessed eq 'Slim::Schema::Playlist') {
		return 1 if ($playListTypes->{'playlist'});
	}
	return undef;
}

sub mixerFunction {
	my ($client, $noSettings) = @_;
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->modeParam('parentParams') ? $client->modeParam('parentParams') : $client->modeParameterStack(-1);
	if (defined($paramref)) {
		if (!$playListTypes) {
			initPlayListTypes();
		}

		my $listIndex = $paramref->{'listIndex'};
		my $items = $paramref->{'listRef'};
		my $currentItem = $items->[$listIndex];
		my $hierarchy = $paramref->{'hierarchy'};
		my @levels = split(',', $hierarchy);
		my $level = $paramref->{'level'} || 0;
		my $mixerType = $levels[$level];
		if ($mixerType eq 'contributor') {
			$mixerType='artist';
		}
		if ($mixerType eq 'age') {
			$mixerType='album';
		}
		if ($playListTypes->{$mixerType} && ($mixerType ne 'artist' || Slim::Schema->variousArtistsObject->id ne $currentItem->id)) {
			if ($mixerType eq 'album') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->title
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'album',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling album playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} elsif ($mixerType eq 'year') {
				my %p = (
					'id' => $currentItem,
					'name' => $currentItem
				);
				$p{'id'} = $currentItem->id;
				$p{'name'} = $currentItem->name;
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'year',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling year playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} elsif ($mixerType eq 'artist') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'artist',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling artist playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} elsif ($mixerType eq 'genre') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->name
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'genre',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling album playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} elsif ($mixerType eq 'playlist') {
				my %p = (
					'id' => $currentItem->id,
					'name' => $currentItem->title
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'playlist',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling playlist playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} elsif ($mixerType eq 'track') {
				my %p = (
					'id' => $currentItem->id,
					'name' => Slim::Music::Info::standardTitle(undef, $currentItem),
				);
				my %params = (
					'dynamicplaylist_parameter_1' => \%p,
					'playlisttype' => 'track',
					'flatlist' => 1,
					'extrapopmode' => 1
				);
				$log->debug('Calling track playlists with '.$params{'dynamicplaylist_parameter_1'}->{'name'}.'('.$params{'dynamicplaylist_parameter_1'}->{'id'}.')');
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlayList.Mixer', \%params);
				$client->update();
			} else {
				$log->warn('Unknown playlisttype = '.$mixerType);
			}
		} else {
			$log->warn('No playlist found for '.$mixerType);
		}
	} else {
		$log->warn('No parent parameter found');
	}

}

sub mixerlink {
	my $item = shift;
	my $form = shift;
	my $descend = shift;

	if (!$playListTypes) {
		initPlayListTypes();
	}
	if ($form->{'noDynamicPlayListButton'}) {
	} else {
		my $contextId = undef;
		my $contextName = undef;
		my $contextType = undef;
		if (ref($item) eq 'Slim::Schema::Album' || ref($item) eq 'Slim::Schema::Age') {
			$contextId = $item->id;
			$contextName = $item->title;
			$contextType = 'album';
		} elsif (ref($item) eq 'Slim::Schema::Track') {
			$contextId = $item->id;
			$contextName = Slim::Music::Info::standardTitle(undef, $item); # was $item),;
			$contextType = 'track';
			$form->{'noitems'} = 1;
		} elsif (ref($item) eq 'Slim::Schema::Contributor' && Slim::Schema->variousArtistsObject->id ne $item->id) {
			$contextId = $item->id;
			$contextName = $item->name;
			$contextType = 'artist';
		} elsif (ref($item) eq 'Slim::Schema::Genre') {
			$contextId = $item->id;
			$contextName = $item->name;
			$contextType = 'genre';
		} elsif (ref($item) eq 'Slim::Schema::Year') {
			$contextId = $item->id;
			if ($item->id) {
				$contextName = $item->id;
			} else {
				$contextName = string('UNK');
			}
			$contextType = 'year';
		} elsif (ref($item) eq 'Slim::Schema::Playlist') {
			$contextId = $item->id;
			$contextName = $item->title;
			$contextType = 'playlist';
		}

		if ($playListTypes->{$contextType} && ($contextType ne 'artist' || Slim::Schema->variousArtistsObject->id ne $item->id)) {
			if (defined($contextType) && defined($contextId)) {
				$form->{'dplmixercontexttype'} = $contextType;
				$form->{'dplmixercontextid'} = $contextId;
				$form->{'dplmixercontextname'} = $contextName;
			}
		}
	}
	return $form;
}


#### web pages ####

sub webPages {
	my $class = shift;
	my %pages = (
		'dynamicplaylist_list\.(?:htm|xml)' => \&handleWebList,
		'dynamicplaylist_mix\.(?:htm|xml)' => \&handleWebMix,
		'dynamicplaylist_mixparameters\.(?:htm|xml)' => \&handleWebMixParameters,
		'dynamicplaylist_selectplaylists\.(?:htm|xml)' => \&handleWebSelectPlaylists,
		'dynamicplaylist_saveselectplaylists\.(?:htm|xml)' => \&handleWebSaveSelectPlaylists,
	);

	my $value = $htmlTemplate;

	for my $page (keys %pages) {
		Slim::Web::Pages->addPageFunction($page, $pages{$page});
	}

	Slim::Web::Pages->addPageLinks('browse', {'PLUGIN_DYNAMICPLAYLIST' => $value});
	Slim::Web::Pages->addPageLinks('icons', {'PLUGIN_DYNAMICPLAYLIST' => 'plugins/DynamicPlayList/html/images/dpl_icon_svg.png'});
}

sub handleWebList {
	my ($client, $params) = @_;
	my $masterClient = masterOrSelf($client);

	# Pass on the current pref values and now playing info
	initPlayLists($client);
	initPlayListTypes();
	registerJiveMenu('Plugins::DynamicPlayList::Plugin');

	my $playlist = undef;
	if (defined($client) && defined($mixInfo{$masterClient}) && defined($mixInfo{$masterClient}->{'type'})) {
		$playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
	}
	my $name = undef;
	if ($playlist) {
		$name = $playlist->{'name'};
		if ($prefs->get('showactiveplaylistinmainmenu')) {
			$params->{'activeClientMixName'} = $name;
			$params->{'activeClientName'} = $client->name;
			$log->debug('active dynamic playlist for client "'.$client->name.'" = '.$name);
		}
	}
	if (defined($params->{'group1'})) {
		my $group = unescape($params->{'group1'});
		if ($group =~/\//) {
			my @groups = split(/\//, $group);
			my $i=1;
			for my $grp (@groups) {
				$params->{'group'.$i} = escape($grp);
				$i++;
			}
		}
	}

	$params->{'pluginDynamicPlayListContext'} = getPlayListContext($client, $params, $playListItems, 1);
	$params->{'pluginDynamicPlayListGroups'} = getPlayListGroupsForContext($client, $params, $playListItems, 1);
	$params->{'pluginDynamicPlayListPlayLists'} = getPlayListsForContext($client, $params, $playListItems, 1, $params->{'playlisttype'});

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

# web context menu mixer
sub registerContextMenu {
	if (Slim::Utils::PluginManager->isEnabled('Plugins::ContextMenu::Plugin')) {
		my $contextMenuApi = $Plugins::ContextMenu::Plugin::apiVersion;
		if (defined($contextMenuApi) && ($contextMenuApi >= 0.67)) {
			Plugins::ContextMenu::Public::registerContextChoice({
				uid => 'plugin.DynamicPlaylist.mixer',
				api => 0.69,
				coderef => sub {
					my $parameters = shift;
					my $client = $parameters->{'client'};
					my $selectedItem = $parameters->{'selected'};
					if(!$playListTypes) {
						initPlayListTypes();
					}
					if($selectedItem && (ref($selectedItem) eq 'Slim::Schema::Contributor' ||
						ref($selectedItem) eq 'Slim::Schema::Album' ||
						ref($selectedItem) eq 'Slim::Schema::Playlist' ||
						ref($selectedItem) eq 'Slim::Schema::Year' ||
						ref($selectedItem) eq 'Slim::Schema::Genre')) {

						my $mixerType = ref($selectedItem);
						$mixerType =~ s/^Slim::Schema:://;
						$mixerType = lc($mixerType);
						if($mixerType eq 'contributor') {
							$mixerType='artist';
						}
						if($playListTypes->{$mixerType} && ($mixerType ne 'artist' || Slim::Schema->variousArtistsObject->id ne $selectedItem->id)) {
							return ({
								'label' => $client->string('PLUGIN_DYNAMICPLAYLIST'),
								'coderef' => \&contextMenuMixer,
								'execargs' => ({
									'item' => $selectedItem,
									'contextmenu' => 'so true'
								})
							});
						}
					}
					return undef;
				},
				displayname => string('PLUGIN_DYNAMICPLAYLIST'),
				pluginname => string('PLUGIN_DYNAMICPLAYLIST'),
			} );
		}
	}
}

sub contextMenuMixer {
	my $params = shift;
	my $client = $params->{'client'};
	my $item = $params->{'execargs'}->{'item'};

	my %p = ();
	if($item && ref($item) eq 'Slim::Schema::Contributor') {
		my %paramItem = (
			'id' => $item->id,
			'name' => $item->name,
		);
		%p = (
			'dynamicplaylist_parameter_1' => \%paramItem,
			'playlisttype' => 'artist',
			'flatlist' => 1,
			'extrapopmode' => 1
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Album') {
		my %paramItem = (
			'id' => $item->id,
			'name' => $item->title,
			'mymode' => 'plugincall'
		);
		%p = (
			'dynamicplaylist_parameter_1' => \%paramItem,
			'playlisttype' => 'album',
			'flatlist' => 1,
			'extrapopmode' => 1
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Playlist') {
		my %paramItem = (
			'id' => $item->id,
			'name' => $item->title,
		);
		%p = (
			'dynamicplaylist_parameter_1' => \%paramItem,
			'playlisttype' => 'playlist',
			'flatlist' => 1,
			'extrapopmode' => 1
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Genre') {
		my %paramItem = (
			'id' => $item->id,
			'name' => $item->name,
		);
		%p = (
			'dynamicplaylist_parameter_1' => \%paramItem,
			'playlisttype' => 'genre',
			'flatlist' => 1,
			'extrapopmode' => 1
		);
	}elsif($item && ref($item) eq 'Slim::Schema::Year') {
		my %paramItem = (
			'id' => $item->id,
			'name' => ($item->id?$item->id:$client->string('UNK'))
		);
		%p = (
			'dynamicplaylist_parameter_1' => \%paramItem,
			'playlisttype' => 'year',
			'flatlist' => 1,
			'extrapopmode' => 1
		);
	}
	Slim::Buttons::Common::pushModeLeft($client,'PLUGIN.DynamicPlayList.Mixer',\%p);
	$client->update();
}

sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		if ($params->{'type'} eq 'disable') {
			playRandom($client, 'disable');
		} else {
			my $playlist = getPlayList($client, $params->{'type'});
			if (!defined($playlist)) {
				$log->warn('Playlist not found:'.$params->{'type'});
			} elsif (defined($playlist->{'parameters'})) {
				return handleWebMixParameters($client, $params);
			} else {
				playRandom($client, $params->{'type'}, $params->{'addOnly'}, 1, 1);
			}
		}
	}
	return handleWebList($client, $params);
}

sub handleWebMixParameters {
	my ($client, $params) = @_;
	$log->debug('Entering handleWebMixParameters');
	my $parameterId = 1;
	my @parameters = ();
	my $playlist = getPlayList($client, $params->{'type'});

	my $i=1;
	while (defined($params->{'dynamicplaylist_parameter_'.$i})) {
		$parameterId = $parameterId +1;
		my %value = (
			'id' => $params->{'dynamicplaylist_parameter_'.$i}
		);
		$client->modeParam('dynamicplaylist_parameter_'.$i, \%value);
		$log->debug("Storing parameter $i = ".$value{'id'});
		$i++;
	}
	if (defined($playlist->{'parameters'}->{$parameterId})) {
		for(my $i = 1; $i < $parameterId; $i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};
			addParameterValues($client, \@parameterValues, $parameter);
			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'dynamicplaylist_parameter_'.$i}
			);
			push @parameters, \%webParameter;
		}

		my $parameter = $playlist->{'parameters'}->{$parameterId};
		$log->debug('Getting values for: '.$parameter->{'name'});
		my @parameterValues = ();
		addParameterValues($client, \@parameterValues, $parameter);
		my %currentParameter = (
			'parameter' => $parameter,
			'values' => \@parameterValues
		);
		push @parameters, \%currentParameter;
		$params->{'pluginDynamicPlayListPlaylist'} = $playlist;
		$params->{'pluginDynamicPlayListPlaylistId'} = $params->{'type'};
		$params->{'pluginDynamicPlayListAddOnly'} = $params->{'addOnly'};
		$params->{'pluginDynamicPlayListMixParameters'} = \@parameters;
		my $currentPlaylistId = getCurrentPlayList($client);
		if (defined($currentPlaylistId)) {
			$log->debug('Setting current playlist id to '.$currentPlaylistId);
			my $currentPlaylist = getPlayList($client, $currentPlaylistId);
			if (defined($currentPlaylist)) {
				$log->debug('Setting current playlist to '.$currentPlaylist->{'name'});
				$params->{'pluginDynamicPlayListNowPlaying'} = $currentPlaylist->{'name'};
			}
		}
		$log->debug('Exiting handleWebMixParameters');
		return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlayList/dynamicplaylist_mixparameters.html', $params);
	} else {
		for(my $i = 1; $i < $parameterId; $i++) {
			$playlist->{'parameters'}->{$i}->{'value'} = $client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
		}
		playRandom($client, $params->{'type'}, $params->{'addOnly'}, 1, 1);
		$log->debug('Exiting handleWebMixParameters');
		return handleWebList($client, $params);
	}
}

sub handleWebSelectPlaylists {
	my ($client, $params) = @_;
	my $masterClient = masterOrSelf($client);

	# Pass on the current pref values and now playing info
	initPlayLists($client);
	initPlayListTypes();
	my $playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
	my $name = undef;
	if ($playlist) {
		$name = $playlist->{'name'};
	}

	$params->{'pluginDynamicPlayListPlayLists'} = $playLists;
	my @groupPath = ();
	my @groupResult = ();
	$params->{'pluginDynamicPlayListGroups'} = getPlayListGroups(\@groupPath, $playListItems, \@groupResult);
	$params->{'pluginDynamicPlayListNowPlaying'} = $name;
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlayList/dynamicplaylist_selectplaylists.html', $params);
}

sub getPlayListContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();
	$log->debug("Get playlist context for level=$level");
	if (defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		$log->debug('Getting group: '.$group);
		my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
		if (defined($item) && !defined($item->{'playlist'})) {
			my $currentUrl = '&group'.$level.'='.escape($group);
			my %resultItem = (
				'url' => $currentUrl,
				'name' => $group,
				'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
			);
			$log->debug('Adding context: '.$group);
			push @result, \%resultItem;

			if (defined($item->{'childs'})) {
				my $childResult = getPlayListContext($client, $params, $item->{'childs'}, $level + 1);
				for my $child (@{$childResult}) {
					$child->{'url'} = $currentUrl.$child->{'url'};
					$log->debug('Adding child context: '.$child->{'name'});
					push @result, $child;
				}
			}
		}
	}
	return \@result;
}

sub getPlayListGroupsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my @result = ();

	if ($prefs->get('flatlist') || $params->{'flatlist'}) {
		return \@result;
	}

	my %customsortnames = ($prefs->get('favouritesname') => '00001_Favourites', 'Songs' => '00002_Songs', 'Artists' => '00003_Artists', 'Albums' => '00004_Albums', 'Genres' => '00005_Genres', 'Years' => '00006_Years', 'Playlists' => '00007_PLaylists', 'Static Playlists' => '00008_static_LMS_playlists', 'Not classified' => '00009_not_classified', 'Context menu lists' => '00010_contextmenulists');

	if (defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		$log->debug('Getting group: '.$group);
		my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
		if (defined($item) && !defined($item->{'playlist'})) {
			if (defined($item->{'childs'})) {
				return getPlayListGroupsForContext($client, $params, $item->{'childs'}, $level + 1);
			} else {
				return \@result;
			}
		}
	} else {
		my $currentLevel;
		my $url = '';
		for ($currentLevel = 1; $currentLevel < $level; $currentLevel++) {
			$url.='&group'.$currentLevel.'='.$params->{'group'.$currentLevel};
		}
		for my $itemKey (keys %{$currentItems}) {
			my $item = $currentItems->{$itemKey};
			if (!defined($item->{'playlist'}) && defined($item->{'name'})) {
				my $currentUrl = $url.'&group'.$level.'='.escape($item->{'name'});
				my $sortname;
				if (($level == 1) && ($customsortnames{$item->{'name'}})) {
					$sortname = $customsortnames{$item->{'name'}};
				} else {
					$sortname = $item->{'name'};
				}
				my %resultItem = (
					'url' => $currentUrl,
					'name' => $item->{'name'},
					'sortname' => $sortname,
					'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
				);
				$log->debug('Adding group: '.$itemKey);
				push @result, \%resultItem;
			}
		}
	}
	@result = sort {lc($a->{'sortname'}) cmp lc($b->{'sortname'})} @result;
	return \@result;
}

sub getPlayListsForContext {
	my $client = shift;
	my $params = shift;
	my $currentItems = shift;
	my $level = shift;
	my $playlisttype = shift;
	my @result = ();

	if ($prefs->get('flatlist') || $params->{'flatlist'}) {
		foreach my $itemKey (keys %{$playLists}) {
			my $playlist = $playLists->{$itemKey};
			if (!defined($playlisttype) || (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype)))) {
				$log->debug('Adding playlist: '.$itemKey);
				push @result, $playlist;
			}
		}
	} else {
		if (defined($params->{'group'.$level})) {
			my $group = unescape($params->{'group'.$level});
			$log->debug('Getting group: '.$group);
			my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
			if (defined($item) && !defined($item->{'playlist'})) {
				if (defined($item->{'childs'})) {
					return getPlayListsForContext($client, $params, $item->{'childs'}, $level + 1);
				} else {
					return \@result;
				}
			}
		} else {
			for my $itemKey (keys %{$currentItems}) {
				my $item = $currentItems->{$itemKey};
				if (defined($item->{'playlist'})) {
					my $playlist = $item->{'playlist'};
					if (!defined($playlisttype) || (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype)))) {
						$log->debug('Adding playlist: '.$itemKey);
						push @result, $item->{'playlist'};
					}
				}
			}
		}
	}
	@result = sort {lc($a->{'dynamicplaylistid'}) cmp lc($b->{'dynamicplaylistid'})} @result;
	return \@result;
}

sub getPlayListGroups {
	my $path = shift;
	my $items = shift;
	my $result = shift;
	for my $key (keys %{$items}) {
		my $item = $items->{$key};
		if (!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupName = undef;
			my $groupId = '';
			for my $pathItem (@{$path}) {
				if (defined($groupName)) {
					$groupName .= '/';
				} else {
					$groupName = '';
				}
				$groupName .= $pathItem;
				$groupId .= '_'.$pathItem;
			}
			if (defined($groupName)) {
				$groupName .= '/';
			} else {
				$groupName = '';
			}

			my %customsortnames = ($prefs->get('favouritesname') => '00001_Favourites', 'Songs' => '00002_Songs', 'Artists' => '00003_Artists', 'Albums' => '00004_Albums', 'Genres' => '00005_Genres', 'Years' => '00006_Years', 'Playlists' => '00007_PLaylists', 'Static Playlists' => '00008_static_LMS_playlists', 'Not classified' => '00009_not_classified', 'Context menu lists' => '00010_contextmenulists');
			my $sortname;
			if (($groupName eq '') && ($customsortnames{$item->{'name'}})) {
				$sortname = $customsortnames{$item->{'name'}}.'/';
			} else {
				$sortname = $groupName.$item->{'name'}.'/';
			}

			my %resultItem = (
				'id' => escape($groupId.'_'.$item->{'name'}),
				'name' => $groupName.$item->{'name'}.'/',
				'sortname' => $sortname,
				'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
			);
			push @{$result}, \%resultItem;
			my $childs = $item->{'childs'};
			if (defined($childs)) {
				my @childpath = ();
				for my $childPathItem (@{$path}) {
					push @childpath, $childPathItem;
				}
				push @childpath, $item->{'name'};
				$result = getPlayListGroups(\@childpath, $childs, $result);
			}
		}
	}
	if ($result) {
		my @temp = sort {lc($a->{'sortname'}) cmp lc($b->{'sortname'})} @{$result};
		$result = \@temp;
		$log->debug('Got sorted array: '.$result);
	}
	return $result;
}

sub handleWebSaveSelectPlaylists {
	my ($client, $params) = @_;

	initPlayLists($client);
	initPlayListTypes();
	my $first = 1;
	my $sql = '';
	foreach my $playlist (keys %{$playLists}) {
		my $playlistid = 'playlist_'.$playLists->{$playlist}{'dynamicplaylistid'};
		if ($params->{$playlistid}) {
			$prefs->delete('playlist_'.$playlist.'_enabled');
		} else {
			$prefs->set('playlist_'.$playlist.'_enabled', 0);
		}
		my $playlistfavouriteid = 'playlistfavourite_'.$playLists->{$playlist}{'dynamicplaylistid'};
		if ($params->{$playlistfavouriteid}) {
			$prefs->set('playlist_'.$playlist.'_favourite', 1);
		} else {
			$prefs->delete('playlist_'.$playlist.'_favourite');
		}
	}
	savePlayListGroups($playListItems , $params, '');
	handleWebList($client, $params);
}

sub savePlayListGroups {
	my $items = shift;
	my $params = shift;
	my $path = shift;

	foreach my $itemKey (keys %{$items}) {
		my $item = $items->{$itemKey};
		if (!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path).'_'.escape($item->{'name'});
			my $playlistid = 'playlist_'.$groupid;
			if ($params->{$playlistid}) {
				#$log->debug('Saving: plugin_dynamicplaylist_playlist_'.escape($path).'_'.escape($itemKey).'_enabled=1');
				$prefs->set('playlist_group_'.$groupid.'_enabled', 1);
			} else {
				#$log->debug('Saving: plugin_dynamicplaylist_playlist_'.escape($path).'_'.escape($itemKey).'_enabled=0');
				$prefs->set('playlist_group_'.$groupid.'_enabled', 0);
			}
			if (defined($item->{'childs'})) {
				savePlayListGroups($item->{'childs'}, $params, $path.'_'.$item->{'name'});
			}
		}
	}
}


## jive menus ##

sub registerJiveMenu {
	my $class = shift;
	my $client = shift;
	my @menuItems = (
		{
			text => Slim::Utils::Strings::string(getDisplayName()),
			weight => 78,
			id => 'dynamicplaylist',
			menuIcon => 'plugins/DynamicPlayList/html/images/dpl_icon_svg.png',
			window => {titleStyle => 'mymusic', 'icon-id' => $class->_pluginDataFor('icon')},
			actions => {
				go => {
					cmd => ['dynamicplaylist', 'browsejive'],
				},
			},
		},
	);
	Slim::Control::Jive::registerPluginMenu(\@menuItems, 'myMusic');
}

sub registerStandardContextMenus {
	Slim::Menu::TrackInfo->registerInfoProvider(dynamicplaylist => (
		before => 'favorites',
		func => sub {
			return objectInfoHandler(@_, undef, 'track');
		},
	));
	Slim::Menu::AlbumInfo->registerInfoProvider(dynamicplaylist => (
		after => 'addalbum',
		func => sub {
			if (scalar(@_) < 6) {
				return objectInfoHandler(@_, undef, 'album');
			} else {
				return objectInfoHandler(@_, 'album');
			}
		},
	));
	Slim::Menu::ArtistInfo->registerInfoProvider(dynamicplaylist => (
		after => 'addartist',
		func => sub {
			return objectInfoHandler(@_, undef, 'artist');
		},
	));
	Slim::Menu::YearInfo->registerInfoProvider(dynamicplaylist => (
		after => 'addyear',
		func => sub {
			return objectInfoHandler(@_, undef, 'year');
		},
	));
	Slim::Menu::PlaylistInfo->registerInfoProvider(dynamicplaylist => (
		after => 'addplaylist',
		func => sub {
			return objectInfoHandler(@_, 'playlist');
		},
	));
	Slim::Menu::GenreInfo->registerInfoProvider(dynamicplaylist => (
		after => 'addgenre',
		func => sub {
			return objectInfoHandler(@_, undef, 'genre');
		},
	));
}

sub objectInfoHandler {
	my ($client, $url, $obj, $remoteMeta, $tags, $filter, $objectType) = @_;
	$tags ||= {};
	my $iscontextmenu = 1;
	my $objectName = undef;
	my $objectId = undef;
	my $parameterId = $objectType.'_id';
	if ($objectType eq 'genre' || $objectType eq 'artist') {
		$objectName = $obj->name;
		$objectId = $obj->id;
	} elsif ($objectType eq 'album' || $objectType eq 'playlist' || $objectType eq 'track') {
		$objectName = $obj->title;
		$objectId = $obj->id;
		if ($objectType eq 'playlist') {
			$parameterId = $objectType;
		}
	} elsif ($objectType eq 'year') {
		$objectName = ($obj?$obj:$client->string('UNK'));
		$objectId = $obj;
		$parameterId = $objectType;
	} else {
		return undef;
	}

	if (!$playListTypes) {
		initPlayListTypes();
	}

	my $mixable = 0;
	if ($playListTypes->{$objectType} && ($objectType ne 'artist' || Slim::Schema->variousArtistsObject->id ne $objectId)) {
		my $jive = {};

		if ($tags->{menuMode}) {
			my $actions = {
				go => {
					player => 0,
					cmd => ['dynamicplaylist', 'mixjive'],
					params => {
						$parameterId => $objectId,
					},
				},
			};
			$jive->{actions} = $actions;
		}

		my $paramItem = {
			id => $objectId,
			name => $objectName
		};

		return {
			type => 'redirect',
			jive => $jive,
			name => $client->string('PLUGIN_DYNAMICPLAYLIST'),
			favorites => 0,

			player => {
				mode => 'PLUGIN.DynamicPlayList.Mixer',
				modeParams => {
					'dynamicplaylist_parameter_1' => $paramItem,
					'playlisttype' => $objectType,
					'flatlist' => 1,
					'extrapopmode' => 1,
				},
			},
			web => {
				group => 'mixers',
				url => 'plugins/DynamicPlayList/dynamicplaylist_list.html?playlisttype='.$objectType.'&flatlist=1&dynamicplaylist_parameter_1='.$objectId.'&iscontextmenu='.$iscontextmenu,
				item => mixerlink($obj),
			},
		};
	}
	return undef;
}


## CLI ##

sub cliJiveHandler {
	$log->debug('Entering cliJiveHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['browsejive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliJiveHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliJiveHandler');
		return;
	}

	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		$log->debug("Got: $k=".$params->{$k});
	}

	$log->debug('Executing CLI browsejive command');
	my $menuGroupResult;
	my $showFlat = $prefs->get('flatlist');
	if ($showFlat) {
		my @empty = ();
		$menuGroupResult = \@empty;
	} else {
		$menuGroupResult = getPlayListGroupsForContext($client, $params, $playListItems, 1);
	}

	my $menuResult = getPlayListsForContext($client, $params, $playListItems, 1);
	my $count = scalar(@{$menuGroupResult}) + scalar(@{$menuResult});

	my %baseParams = ();
	my $nextGroup = 1;
	foreach my $param (keys %{$params}) {
		if ($param !~ /^_/) {
			$baseParams{$param} = $params->{$param};
		}
		if ($param =~ /^group/) {
			$nextGroup++;
		}
	}
	my $baseMenu = {
		'actions' => {
			'play' => {
				'cmd' => ['dynamicplaylist', 'playlist', 'play'],
				'itemsParams' => 'params',
			},
			'add' => {
				'cmd' => ['dynamicplaylist', 'playlist', 'add'],
				'itemsParams' => 'params',
			},
		},
	};
	$request->addResult('base', $baseMenu);

	my $cnt = 0;

	if ($prefs->get('showactiveplaylistinmainmenu')) {
		my $masterClient = masterOrSelf($client);
		my $playlist = undef;
		if (defined($client) && defined($mixInfo{$masterClient}) && defined($mixInfo{$masterClient}->{'type'})) {
			$playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
		}
		if ($playlist && $nextGroup == 1) {
			my $text = '** Active ** playlist: '.$playlist->{'name'};
			$log->debug('active dynamic playlist for client "'.$client->name.'" = '.$playlist->{'name'});
			$request->addResultLoop('item_loop', 0, 'text', $text);
			$request->addResultLoop('item_loop', 0, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', 0, 'action', 'none');
			$cnt++;
		}
	}

	foreach my $item (@{$menuGroupResult}) {
		if ($item->{'dynamicplaylistenabled'}) {
			my $name;
			my $id;
			$name = $item->{'name'};
			$id = escape($item->{'name'});

			my %itemParams = ();
			foreach my $p (keys %baseParams) {
				if ($p =~ /^group/) {
					$itemParams{$p}=$baseParams{$p}
				}
			}
			$itemParams{'group'.$nextGroup} = $id;

			my $actions = {
				'play' => undef,
				'add' => undef,
				'go' => {
					'cmd' => ['dynamicplaylist', 'browsejive'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $cnt, 'text', $name.'/');
			$cnt++;
		}
	}

	foreach my $item (@{$menuResult}) {
		if ($item->{'dynamicplaylistenabled'} && $item->{'menulisttype'} ne 'contextmenu') {
			my $name;
			my $id;
			$name = $item->{'name'};
			$id = $item->{'dynamicplaylistid'};

			my %itemParams = (
				'playlistid' => $id,
			);

			if (exists $item->{'parameters'} && exists $item->{'parameters'}->{'1'}) {
				my $actions = {
					'go' => {
						'cmd' => ['dynamicplaylist', 'jiveplaylistparameters'],
						'params' => \%itemParams,
						'itemsParams' => 'params',
					},
					'play' => undef,
					'add' => undef,
				};
				$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			} else {
				my $actions = {
					'do' => {
						'cmd' => ['dynamicplaylist', 'playlist', 'play'],
						'params' => \%itemParams,
						'itemsParams' => 'params',
					},
				};
				$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
				$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
			}
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $cnt, 'text', $name);
			$cnt++;
		}
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);

	$request->setStatusDone();
	$log->debug('Exiting cliJiveHandler');
}

sub cliJivePlaylistParametersHandler {
	$log->debug('Entering cliJivePlaylistParametersHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['jiveplaylistparameters']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	my $playlistId = $request->getParam('playlistid');
	if (!defined($playlistId)) {
		$log->warn('playlistid parameter required');
		$request->setStatusBadParams();
		$log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	my $playlist = getPlayList($client, $playlistId);
	if (!defined($playlist)) {
		$log->warn("Playlist $playlistId can\'t be found");
		$request->setStatusBadParams();
		$log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}

	my $params = $request->getParamsCopy();

	my %baseParams = (
		'playlistid' => $playlistId,
	);
	for my $k (keys %{$params}) {
		$log->debug("Got: $k=".$params->{$k});
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			$baseParams{$k} = $params->{$k};
		}
	}

	my $parameters = {};
	my $nextParameterId = 1;
	my $parameterValue = $request->getParam('dynamicplaylist_parameter_'.$nextParameterId);
	while (defined $parameterValue) {
		$parameters->{$nextParameterId} = $parameterValue;
		$nextParameterId++;
		$parameterValue = $request->getParam('dynamicplaylist_parameter_'.$nextParameterId);
	}

	if (!exists $playlist->{'parameters'}->{$nextParameterId}) {
		$log->warn('More parameters than requested: '.$nextParameterId);
		$request->setStatusBadParams();
		$log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}

	my $start = $request->getParam('_start') || 0;
	$log->debug('Executing CLI jiveplaylistparameters command');

	my $parameter= $playlist->{'parameters'}->{$nextParameterId};

	my @listRef = ();
	addParameterValues($client, \@listRef, $parameter, $parameters);

	my $count = scalar(@listRef);
	my $itemsPerResponse = $request->getParam('_itemsPerResponse') || $count;

	if (exists $playlist->{'parameters'}->{($nextParameterId + 1)}) {
		my $baseMenu = {
			'actions' => {
				'go' => {
					'cmd' => ['dynamicplaylist', 'jiveplaylistparameters'],
					'params' => \%baseParams,
					'itemsParams' => 'params',
				},
			},
		};
		$request->addResult('base', $baseMenu);
	} else {
		my $baseMenu = {
			'actions' => {
				'do' => {
					'cmd' => ['dynamicplaylist', 'playlist', 'play'],
					'params' => \%baseParams,
					'itemsParams' => 'params',
				},
			},
		};
		$request->addResult('base', $baseMenu);
	}

	my $cnt = 0;
	my $offsetCount = 0;
	foreach my $item (@listRef) {
		if ($cnt >= $start && $offsetCount < $itemsPerResponse) {
			my %itemParams = (
				'dynamicplaylist_parameter_'.$nextParameterId => $item->{'id'}
			);

			$request->addResultLoop('item_loop', $offsetCount, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $offsetCount, 'text', $item->{'name'});
			if (defined($item->{'sortlink'})) {
				$request->addResultLoop('item_loop', $offsetCount, 'textkey', $item->{'sortlink'});
			}
			if (!exists $playlist->{'parameters'}->{($nextParameterId + 1)}) {
				$request->addResultLoop('item_loop', $offsetCount, 'style', 'itemplay');
			}
			$offsetCount++;
		}
		$cnt++;
	}

	$request->addResult('offset', $start);
	$request->addResult('count', $cnt);

	$request->setStatusDone();
	$log->debug('Exiting cliJivePlaylistParametersHandler');
}

sub cliMixJiveHandler {
	$log->debug('Entering cliMixJiveHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['mixjive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliMixJiveHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliMixJiveHandler');
		return;
	}

	if (!$playListTypes || $rescan) {
		initPlayLists($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		$log->debug("Got: $k=".$params->{$k});
	}

	my $playlisttype = undef;
	my $itemId = undef;
	if ($request->getParam('album_id')) {
		$playlisttype = 'album';
		$itemId = $request->getParam('album_id');
	} elsif ($request->getParam('artist_id')) {
		$playlisttype = 'artist';
		$itemId = $request->getParam('artist_id');
	} elsif ($request->getParam('contributor_id')) {
		$playlisttype = 'artist';
		$itemId = $request->getParam('contributor_id');
	} elsif ($request->getParam('genre_id')) {
		$playlisttype = 'genre';
		$itemId = $request->getParam('genre_id');
	} elsif ($request->getParam('year')) {
		$playlisttype = 'year';
		$itemId = $request->getParam('year');
	} elsif ($request->getParam('playlist')) {
		$playlisttype = 'playlist';
		$itemId = $request->getParam('playlist');
	} elsif ($request->getParam('track_id')) {
		$playlisttype = 'track';
		$itemId = $request->getParam('track_id');
	}
	$log->debug('Executing CLI mixjive command');

	my $cnt = 0;
	if (defined($playlisttype)) {
		foreach my $flatItem (sort keys %{$playLists}) {
			my $playlist = $playLists->{$flatItem};
			next if (($request->getParam('useContextMenu') == 1) && ($playlist->{'menulisttype'} ne 'contextmenu'));
			if ($playlist->{'dynamicplaylistenabled'}) {
				if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype))) {
					my $name;
					my $id;
					$name = $playlist->{'name'};
					$id = $playlist->{'dynamicplaylistid'};

					my %itemParams = (
						'playlistid' => $id,
						'dynamicplaylist_parameter_1' => $itemId,
					);

					if (exists $playlist->{'parameters'}->{'2'}) {
						my $actions = {
							'go' => {
								'cmd' => ['dynamicplaylist', 'jiveplaylistparameters'],
								'params' => \%itemParams,
								'itemsParams' => 'params',
							},
						};
						$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
					} else {
						my $actions = {
							'do' => {
								'cmd' => ['dynamicplaylist', 'playlist', 'play'],
								'params' => \%itemParams,
								'itemsParams' => 'params',
							},
						};
						$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
						$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
						$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'parent');
					}
					$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
					$request->addResultLoop('item_loop', $cnt, 'text', $name);
					$cnt++;
				}
			}
		}
	}
	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);

	$request->setStatusDone();
	$log->debug('Exiting cliJiveHandler');
}

sub cliGetPlaylists {
	$log->debug('Entering cliGetPlaylists');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotQuery([['dynamicplaylist'], ['playlists']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliGetPlaylists');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliGetPlaylists');
		return;
	}

	my $all = $request->getParam('_all');
	initPlayLists($client);
	initPlayListTypes();
	if (!defined($all) || $all ne 'all') {
		$all = undef;
	}
	my $count = 0;
	foreach my $playlist (sort keys %{$playLists}) {
		if (!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			$count++;
		}
	}
	my $start = $request->getParam('_start') || 0;
	my $itemsPerResponse = $request->getParam('_itemsPerResponse') || $count;

	$request->addResult('count', $count);
	$request->addResult('offset', $start);
	$count = 0;
	my $offsetCount = 0;
	foreach my $playlist (sort keys %{$playLists}) {
		if (!defined($playLists->{$playlist}->{'parameters'}) && ($playLists->{$playlist}->{'dynamicplaylistenabled'} || defined $all)) {
			if ($count >= $start + $itemsPerResponse) {
				last;
			}
			if ($count >= $start) {
				$request->addResultLoop('playlists_loop', $offsetCount, 'playlistid', $playlist);
				my $p = $playLists->{$playlist};
				my $name = $p->{'name'};
				$request->addResultLoop('playlists_loop', $offsetCount, 'playlistname', $name);
				if (defined $all) {
					$request->addResultLoop('playlists_loop', $offsetCount, 'playlistenabled', $playLists->{$playlist}->{'dynamicplaylistenabled'});
				}
				$offsetCount++
			}
			$count++;
		}
	}
	$request->setStatusDone();
	$log->debug('Exiting cliGetPlaylists');
}

sub cliPlayPlaylist {
	$log->debug('Entering cliPlayPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['play']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliPlayPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliPlayPlaylist');
		return;
	}

	my $playlistId = $request->getParam('playlistid');
	if (!defined($playlistId)) {
		$playlistId = $request->getParam('_p3');
		if (!defined($playlistId)) {
			$playlistId = $request->getParam('_p0');
		}
	}
	if ($playlistId =~ /^?playlistid:(.+)$/) {
		$playlistId = $1;
	}

	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			my $parameterId = $1;
			if (exists $playLists->{$playlistId}->{'parameters'}->{$1}) {
				$log->debug("Using: $k=".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			$log->debug("Got: $k=".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 0, 1);

	$request->setStatusDone();
	$log->debug('Exiting cliPlayPlaylist');
}

sub cliContinuePlaylist {
	$log->debug('Entering cliContinuePlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['continue']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliContinuePlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliContinuePlaylist');
		return;
	}

	my $playlistId = $request->getParam('playlistid');
	if (!defined($playlistId)) {
		$playlistId = $request->getParam('_p3');
		if (!defined($playlistId)) {
			$playlistId = $request->getParam('_p0');
		}
	}
	if ($playlistId =~ /^?playlistid:(.+)$/) {
		$playlistId = $1;
	}

	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			my $parameterId = $1;
			if (exists $playLists->{$playlistId}->{'parameters'}->{$1}) {
				$log->debug("Using: $k=".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			$log->debug("Got: $k=".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 0, 1, undef, 1);

	$request->setStatusDone();
	$log->debug('Exiting cliContinuePlaylist');
}

sub cliAddPlaylist {
	$log->debug('Entering cliAddPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['add']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliAddPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliAddPlaylist');
		return;
	}

	my $playlistId = $request->getParam('playlistid');
	if (!defined($playlistId)) {
		$playlistId = $request->getParam('_p3');
		if (!defined($playlistId)) {
			$playlistId = $request->getParam('_p0');
		}
	}
	if ($playlistId =~ /^?playlistid:(.+)$/) {
		$playlistId = $1;
	}

	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			my $parameterId = $1;
			if (exists $playLists->{$playlistId}->{'parameters'}->{$1}) {
				$log->debug("Using: $k=".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			$log->debug("Got: $k=".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 1, 1, 1);

	$request->setStatusDone();
	$log->debug('Exiting cliAddPlaylist');
}

sub cliStopPlaylist {
	$log->debug('Entering cliStopPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['stop']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		$log->debug('Exiting cliStopPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		$log->debug('Exiting cliStopPlaylist');
		return;
	}

	playRandom($client, 'disable');

	$request->setStatusDone();
	$log->debug('Exiting cliStopPlaylist');
}


### built-in & user-provided custom dynamic playlists + saved static playlists

sub getDynamicPlayLists {
	my ($client) = @_;

	my $playLists = ();
	my %result = ();

	if ($prefs->get('includesavedplaylists')) {
		my @result;
		for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {
			push @result, $playlist;
		}
		$playLists = \@result;

		$log->debug('Got: '.scalar(@{$playLists}).' number of saved static playlists');
		my $playlistDir = $serverPrefs->get('playlistdir');
		if ($playlistDir) {
			$playlistDir = Slim::Utils::Misc::fileURLFromPath($playlistDir);
		}
		foreach my $playlist (@{$playLists}) {
			my $playlistid = 'dplstandardpl_'.sha1_base64($playlist->url);
			my $id = $playlist->id;
			my $name = $playlist->title;
			my $playlisturl;
			$playlisturl = 'clixmlbrowser/clicmd=browselibrary+items&linktitle=SAVED_PLAYLISTS&mode=playlistTracks&playlist_id='.$playlist->id;

			my %currentResult = (
				'id' => $id,
				'name' => $name,
				'playlistcategory' => 'static LMS playlists',
				'url' => $playlisturl,
				'groups' => [['Static Playlists']]
			);

			if ($prefs->get('structured_savedplaylists') && $playlistDir) {
				my $url = $playlist->url;
				if ($url =~ /^$playlistDir/) {
					$url =~ s/^$playlistDir[\/\\]?//;
				}
				$url = unescape($url);
				my @groups = split(/[\/\\]/, $url);
				if (@groups) {
					pop @groups;
				}
			if (@groups) {
					unshift @groups, 'Static Playlists';
					my @mainGroup = [@groups];
					$currentResult{'groups'} = \@mainGroup;
				}
			}
			$result{$playlistid} = \%currentResult;
		}
	}

	if ($localDynamicPlaylists) {
		foreach my $playlist (sort keys %{$localDynamicPlaylists}) {
			my $current = $localDynamicPlaylists->{$playlist};
			my $playlistid;
			if ($current->{'defaultplaylist'}) {
				$playlistid = 'dpldefault_'.$playlist;
			} else {
				$playlistid = 'dplusercustom_'.$playlist;
			}
			my %currentResult = (
				'id' => $playlist,
				'name' => $current->{'name'},
				'menulisttype' => $current->{'menulisttype'},
				'playlistcategory' => $current->{'playlistcategory'},
 				'url' => ''
			);
			if (defined($current->{'parameters'})) {
				my $parameters = $current->{'parameters'};
				foreach my $pk (keys %{$parameters}) {
					my %parameter = (
						'id' => $pk,
						'type' => $parameters->{$pk}->{'type'},
						'name' => $parameters->{$pk}->{'name'},
						'definition' => $parameters->{$pk}->{'definition'}
					);
					$currentResult{'parameters'}->{$pk} = \%parameter;
				}
			}
			if (defined($current->{'startactions'})) {
				$currentResult{'startactions'}=$current->{'startactions'};
			}
			if (defined($current->{'stopactions'})) {
				$currentResult{'stopactions'}=$current->{'stopactions'};
			}
			if (defined($current->{'contextmenulist'})) {
				$currentResult{'contextmenulist'}=$current->{'contextmenulist'};
			}
			if ($current->{'groups'} && scalar($current->{'groups'})>0) {
				$currentResult{'groups'} = $current->{'groups'};
			}
			$result{$playlistid} = \%currentResult;
		}
	}

	return \%result;
}

sub getNextDynamicPlayListTracks {
	my ($client, $dynamicplaylist, $limit, $offset, $parameters) = @_;
	my @result = ();
	my $dynamicplaylistID = $dynamicplaylist->{'dynamicplaylistid'};
	my $localDynamicPlaylistID = $dynamicplaylist->{'id'};

	if ((starts_with($dynamicplaylistID, 'dpldefault_') == 0) || (starts_with($dynamicplaylistID, 'dplusercustom_') == 0)) {
		$log->debug('Getting tracks for dynamic playlist: \''.$dynamicplaylist->{'name'}.'\' with ID: '.$dynamicplaylist->{'id'});
		$log->debug("limit = $limit, offset = $offset, parameters = ".Dumper($parameters));
		my $playlist = getPlayList($client, $dynamicplaylistID);
		my $localDynamicPlaylistSQLstatement = $localDynamicPlaylists->{$localDynamicPlaylistID}->{'sql'};
		my $sqlstatement = replaceParametersInSQL($localDynamicPlaylistSQLstatement, $parameters);

		my $predefinedParameters = ();
		my %player = (
			'id' => 'Player',
			'value' => "'".$client->id."'",
		);
		my %offsetParameter = (
			'id' => 'Offset',
			'value' => $offset
		);
		if (!defined($limit)) {$limit = 99999999};
		my %limitParameter = (
			'id' => 'Limit',
			'value' => $limit
		);
		my %VAstring = (
			'id' => 'VariousArtistsString',
			'value' => "'".($serverPrefs->get('variousArtistsString') || 'Various Artists')."'",
		);
		my %minTrackDuration = (
			'id' => 'TrackMinDuration',
			'value' => $prefs->get('song_min_duration'),
		);
		my %topratedMinRating = (
			'id' => 'TopRatedMinRating',
			'value' => $prefs->get('toprated_min_rating'),
		);
		my %minAlbumTracks = (
			'id' => 'MinAlbumTracks',
			'value' => $prefs->get('minalbumtracks'),
		);
		my %periodRecentlyAdded = (
			'id' => 'PeriodRecentlyAdded',
			'value' => $prefs->get('period_recentlyadded'),
		);
		my %periodRecentlyPlayed = (
			'id' => 'PeriodRecentlyPlayed',
			'value' => $prefs->get('period_recentlyplayed'),
		);
		my %periodPlayedLongAgo = (
			'id' => 'PeriodPlayedLongAgo',
			'value' => $prefs->get('period_playedlongago'),
		);
		my %excludedGenres = (
			'id' => 'ExcludedGenres',
			'value' => getExcludedGenreList(),
		);
		my %currentVirtualLibraryForClient = (
			'id' => 'CurrentVirtualLibraryForClient',
			'value' => "'".Slim::Music::VirtualLibraries->getLibraryIdForClient($client)."'",
		);

		$predefinedParameters->{'PlaylistPlayer'} = \%player;
		$predefinedParameters->{'PlaylistOffset'} = \%offsetParameter;
		$predefinedParameters->{'PlaylistLimit'} = \%limitParameter;
		$predefinedParameters->{'PlaylistVariousArtistsString'} = \%VAstring;
		$predefinedParameters->{'PlaylistTrackMinDuration'} = \%minTrackDuration;
		$predefinedParameters->{'PlaylistTopRatedMinRating'} = \%topratedMinRating;
		$predefinedParameters->{'PlaylistMinAlbumTracks'} = \%minAlbumTracks;
		$predefinedParameters->{'PlaylistPeriodRecentlyAdded'} = \%periodRecentlyAdded;
		$predefinedParameters->{'PlaylistPeriodRecentlyPlayed'} = \%periodRecentlyPlayed;
		$predefinedParameters->{'PlaylistPeriodPlayedLongAgo'} = \%periodPlayedLongAgo;
		$predefinedParameters->{'PlaylistExcludedGenres'} = \%excludedGenres;
		$predefinedParameters->{'PlaylistCurrentVirtualLibraryForClient'} = \%currentVirtualLibraryForClient;

		$sqlstatement = replaceParametersInSQL($sqlstatement, $predefinedParameters, 'Playlist');
		$log->debug('sqlstatement = '.$sqlstatement);

		my @result = ();
		my $dbh = getCurrentDBH();
		for my $sql (split(/[\n\r]/, $sqlstatement)) {
			eval {
				my $sth = $dbh->prepare($sql);
				$sth->execute() or do {
					$sql = undef;
				};
				if ($sql =~ /^\(*select+/oi) {
					my $trackURL;
					$sth->bind_col(1,\$trackURL);
					my @tracks = ();
					while ($sth->fetch()) {
						my $track = Slim::Schema->resultset('Track')->objectForUrl($trackURL);
						push @tracks, $track;
					}
					fisher_yates_shuffle(\@tracks);
					push @result, @tracks;
				}
				$sth->finish();
			};
			if ($@) {
				$log->warn("Database error: $DBI::errstr\n$@");
				return "error";
			}
		}
		$log->debug('Got '.scalar(@result).' tracks');
		return \@result;

	} else {

		$log->debug('Getting tracks for standard playlist: '.$dynamicplaylist->{'name'});
		my $playlist = objectForId('playlist', $dynamicplaylist->{'id'});
		my @tracks = ();
		if (!$prefs->get('randomsavedplaylists')) {
			my $iterator = $playlist->tracks;
			@tracks = $iterator->slice(0, $iterator->count);
		} else {
			$offset = 0;
			my $dbh = getCurrentDBH();
			my $rand = "random()";
			my $clientid=$dbh->quote($client->id);
			my $sql = "select tracks.id from playlist_track join tracks on playlist_track.track=tracks.url left join dynamicplaylist_history on tracks.id=dynamicplaylist_history.id and dynamicplaylist_history.client=$clientid where playlist_track.playlist=".$dynamicplaylist->{'id'}." and dynamicplaylist_history.id is null group by playlist_track.track order by $rand";
			if (defined($limit)) {
				$sql .= " limit $limit";
			}
			eval {
				$log->debug("Executing $sql");
				my $sth = $dbh->prepare($sql);
				$sth->execute() or do {$sql = undef;};
				if (defined($sql)) {
					my $id;
					$sth->bind_columns(undef, \$id);
					my @trackIds = ();
					while ($sth->fetch()) {
						push @trackIds, $id;
					}
					if (scalar(@trackIds) > 0) {
						@tracks = Slim::Schema->resultset('Track')->search({'id' => {'in' => \@trackIds}});
						fisher_yates_shuffle(\@tracks);
					}
				}
				$sth->finish();
			};
			if ($@) {
				$log->warn("Database error: $DBI::errstr\n$@");
				return "error";
			}
		}
		my $count = 0;
		my $itemCount = 0;
		for my $item (@tracks) {
			if ($count >= $offset) {
				$itemCount++;
				push @result, $item;
			}
			$count++;
			if (defined($limit) && $itemCount >= $limit) {
				last;
			}
		}
		$log->debug('Got '.scalar(@result).' tracks');
		return \@result;
	}
}

sub replaceParametersInSQL {
	my $sql = shift;
	my $parameters = shift;
	my $parameterType = shift;
	if (!defined($parameterType)) {
		$parameterType='PlaylistParameter';
	}

	if (defined($parameters)) {
		foreach my $key (keys %{$parameters}) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			if (!defined($value)) {
				$value='';
			}
			my $parameterid = "\'$parameterType".$parameter->{'id'}."\'";
			$log->debug('Replacing '.$parameterid.' with '.$value);
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
}

# read + parse built-in + custom dynamic playlists ##
sub getLocalDynamicPlaylists {
	my $client = shift;
	my $customlistdir_parentfolderpath = $prefs->get('customdirparentfolderpath');
	my $customlistdir = $customlistdir_parentfolderpath.'/DPL-custom-lists';
	mkdir($customlistdir, 0755) unless (-d $customlistdir);
	chdir($customlistdir) or $customlistdir = $customlistdir_parentfolderpath;

	my $pluginPlaylistFolder;
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	$log->debug('pluginDirs = '.Dumper(\@pluginDirs));
	for my $plugindir (@pluginDirs) {
		if (-d catdir($plugindir, 'DynamicPlayList', 'Playlists')) {
			$pluginPlaylistFolder = catdir($plugindir, 'DynamicPlayList', 'Playlists');
			$log->debug('pluginPlaylistFolder = '.Dumper($pluginPlaylistFolder));
		}
	}

	my @localDefDirs = ($pluginPlaylistFolder, $customlistdir);
	$log->debug('Searching for custom dynamic playlist definitions in local directories');

	for my $localDefDir (@localDefDirs) {
		if (!defined $localDefDir || !-d $localDefDir) {
			$log->debug('Skipping scan for custom definitions - directory is undefined or does not exist');
		} else {
			$log->debug('Checking dir: '.$localDefDir);

			my @dircontents = Slim::Utils::Misc::readDirectory($localDefDir, 'sql.xml', 'dorecursive');
			my $fileExtension = "\\.sql\\.xml\$";

			for my $item (@dircontents) {
				next unless $item =~ /$fileExtension/;
				next if -d $item;
				my $content = eval {read_file($item)};
				$item = basename($item);
				if ($content) {
					# If necessary convert the file data to utf8
					my $encoding = Slim::Utils::Unicode::encodingFromString($content);
					if ($encoding ne 'utf8') {
						$content = Slim::Utils::Unicode::latin1toUTF8($content);
						$content = Slim::Utils::Unicode::utf8on($content);
						$log->debug("Loading $item and converting from latin1");
					} else {
						$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
						$log->debug("Loading $item without conversion with encoding ".$encoding);
					}

					my $parsedContent = parseContent($client, $item, $content);
					if ($localDefDir eq $pluginPlaylistFolder) {
						$parsedContent->{'defaultplaylist'} = 1;
					} else {
						$parsedContent->{'customplaylist'} = 1;
					}
					$localDynamicPlaylists->{$parsedContent->{'id'}} = $parsedContent;
				}
			}
		}
	}
	#$log->debug('localDynamicPlaylists = '.Dumper($localDynamicPlaylists));
}

sub parseContent {
	my $client = shift;
	my $item = shift;
	my $content = shift;
	my $items = shift;

	my $errorMsg = undef;
	if ($content) {
		decode_entities($content);

		my @playlistDataArray = split(/[\n\r]+/, $content);
		my $name = undef;
		my $statement = '';
		my $fulltext = '';
		my @groups = ();
		my %parameters = ();
		my $menuListType = '';
		my $playlistCategory = '';
		my %startactions = ();
		my %stopactions = ();
		for my $line (@playlistDataArray) {
			#Lets add linefeed again, to make sure playlist looks ok when editing
			if (!$name) {
				$name = parsePlaylistName($line);
				if (!$name) {
					my $file = $item;
					my $fileExtension = "\\.sql\\.xml\$";
					$item =~ s{$fileExtension$}{};
					$name = $item; # playlist name = playlistid if no name found in file
				}
			}
			$line .= "\n";
			if ($name && $line !~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
				$fulltext .= $line;
			}
			chomp $line;

			# use "--PlaylistName:" as name of playlist
			#$line =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
			my $parameter = parseParameter($line);
			my $action = parseAction($line);
			my $listType = parseMenuListType($line);
			my $category = parseCategory($line);
			if ($line =~ /^\s*--\s*PlaylistGroups\s*[:=]\s*/) {
				$line =~ s/^\s*--\s*PlaylistGroups\s*[:=]\s*//io;
				if ($line) {
					my @stringGroups = split(/\,/, $line);
					foreach my $group (@stringGroups) {
						# Remove all white spaces
						$group =~ s/^\s+//;
						$group =~ s/\s+$//;
						my @subGroups = split(/\//, $group);
						push @groups,\@subGroups;
					}
				}
				$line = '';
			}
			if ($parameter) {
				$parameters{$parameter->{'id'}} = $parameter;
			}
			if ($action) {
				if ($action->{'execute'} eq 'Start') {
					$startactions{$action->{'id'}} = $action;
				} elsif ($action->{'execute'} eq 'Stop') {
					$stopactions{$action->{'id'}} = $action;
				}
			}
			if ($listType) {
				$menuListType = $listType;
			}
			if ($category) {
				$playlistCategory = $category;
			}

			# skip and strip comments & empty lines
			$line =~ s/\s*--.*?$//o;
			$line =~ s/^\s*//o;

			next if $line =~ /^--/;
			next if $line =~ /^\s*$/;

			if ($name) {
				$line =~ s/\s+$//;
				if ($statement) {
					if ($statement =~ /;$/) {
						$statement .= "\n";
					} else {
						$statement .= " ";
					}
				}
				$statement .= $line;
			}
		}

		if ($name && $statement) {
			#my $playlistid = escape($name,"^A-Za-z0-9\-_");
			my $file = $item;
			my $fileExtension = "\\.sql\\.xml\$";
			$item =~ s{$fileExtension$}{};
			my $playlistid = $item;
			$name =~ s/\'\'/\'/g;

			my %playlist = (
				'id' => $playlistid,
				'file' => $file,
				'name' => $name,
				'sql' => Slim::Utils::Unicode::utf8decode($statement,'utf8'),
				'fulltext' => Slim::Utils::Unicode::utf8decode($fulltext,'utf8')
			);

			if (scalar(@groups)>0) {
				$playlist{'groups'} = \@groups;
			}
			if (%parameters) {
				$playlist{'parameters'} = \%parameters;
				my $playLists = $items;
				foreach my $p (keys %parameters) {
					if (defined($playLists)
						&& defined($playLists->{$playlistid})
						&& defined($playLists->{$playlistid}->{'parameters'})
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p})
						&& $playLists->{$playlistid}->{'parameters'}->{$p}->{'name'} eq $parameters{$p}->{'name'}
						&& defined($playLists->{$playlistid}->{'parameters'}->{$p}->{'value'}))
					{
						$log->debug("Use already existing value PlaylistParameter$p=".$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'});
						$parameters{$p}->{'value'}=$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'};
					}
				}
			}
			if (defined $menuListType && $menuListType ne '') {
				$playlist{'menulisttype'} = $menuListType;
			}
			if (defined $playlistCategory && $playlistCategory ne '') {
				$playlist{'playlistcategory'} = $playlistCategory;
			}
			if (%startactions) {
				my @actionArray = ();
				for my $key (keys %startactions) {
					my $a = $startactions{$key};
					push @actionArray, $a;
				}
				$playlist{'startactions'} = \@actionArray;
			}
			if (%stopactions) {
				my @actionArray = ();
				for my $key (keys %stopactions) {
					my $a = $stopactions{$key};
					push @actionArray, $a;
				}
				$playlist{'stopactions'} = \@actionArray;
			}
			return \%playlist;
		}
	} else {
		if ($@) {
			$errorMsg = "Incorrect information in playlist data: $@";
			$log->warn("Unable to read playlist configuration:\n$@");
		} else {
			$errorMsg = 'Incorrect information in playlist data';
			$log->warn('Unable to to read playlist configuration');
		}
	}
	return undef;
}

sub parsePlaylistName {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistName\s*[:=]\s*/) {
		my $name = $line;
		$name =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
		$name =~ s/\s+$//;
		$name =~ s/^\s+//;
		if ($name) {
			return $name;
		} else {
			$log->info("No name found in: $line");
			$log->info("Value: name=$name");
			return undef;
		}
	}
	return undef;
}

sub parseParameter {
	my $line = shift;

	if ($line =~ /^\s*--\s*PlaylistParameter\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistParameter\s*(\d)\s*[:=]\s*([^:]+):\s*([^:]*):\s*(.*)$/;
		my $parameterId = $1;
		my $parameterType = $2;
		my $parameterName = $3;
		my $parameterDefinition = $4;

		$parameterType =~ s/^\s+//;
		$parameterType =~ s/\s+$//;

		$parameterName =~ s/^\s+//;
		$parameterName =~ s/\s+$//;

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;

		if ($parameterId && $parameterName && $parameterType) {
			my %parameter = (
				'id' => $parameterId,
				'type' => $parameterType,
				'name' => $parameterName,
				'definition' => $parameterDefinition
			);
			return \%parameter;
		} else {
			$log->warn("Error in parameter: $line");
			$log->warn("Parameter values: Id=$parameterId, Type=$parameterType, Name=$parameterName, Definition=$parameterDefinition");
			return undef;
		}
	}
	return undef;
}

sub parseAction {
	my $line = shift;
	my $actionType = shift;

	if ($line =~ /^\s*--\s*Playlist(Start|Stop)Action\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*Playlist(Start|Stop)Action\s*(\d)\s*[:=]\s*([^:]+):\s*(.*)$/;
		my $executeTime = $1;
		my $actionId = $2;
		my $actionType = $3;
		my $actionDefinition = $4;

		$actionType =~ s/^\s+//;
		$actionType =~ s/\s+$//;

		$actionDefinition =~ s/^\s+//;
		$actionDefinition =~ s/\s+$//;

		if ($actionId && $actionType && $actionDefinition) {
			my %action = (
				'id' => $actionId,
				'execute' => $executeTime,
				'type' => $actionType,
				'data' => $actionDefinition
			);
			return \%action;
		} else {
			$log->warn("No action defined or error in action: $line");
			$log->warn("Action values: Id=$actionId, Type=$actionType, Definition=$actionDefinition");
			return undef;
		}
	}
	return undef;
}

sub parseMenuListType {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistMenuListType\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistMenuListType\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $MenuListType = $1;
		$MenuListType =~ s/\s+$//;
		$MenuListType =~ s/^\s+//;

		if ($MenuListType) {
			return $MenuListType;
		} else {
			$log->info("No value or error in MenuListType: $line");
			$log->info("Option values: MenuListType=$MenuListType");
			return undef;
		}
	}
	return undef;
}

sub parseCategory {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistCategory\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistCategory\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $category = $1;
		$category =~ s/\s+$//;
		$category =~ s/^\s+//;

		if ($category) {
			return $category;
		} else {
			$log->info("No value or error in category: $line");
			$log->info("Option values: category=$category");
			return undef;
		}
	}
	return undef;
}


## DPL history ##

sub initDatabase {
	my $dbh = getCurrentDBH();
	my $st = $dbh->table_info();
	my $tblexists;
	while (my ($qual, $owner, $table, $type) = $st->fetchrow_array()) {
		if ($table eq 'dynamicplaylist_history') {
			$tblexists=1;
		}
	}
	$st->finish();
	unless ($tblexists) {
		my $sqlCreate = "CREATE TABLE IF NOT EXISTS dynamicplaylist_history (client varchar(20) NOT NULL, position INTEGER PRIMARY KEY AUTOINCREMENT, id int(10) NOT NULL UNIQUE, url text NOT NULL UNIQUE, added int(10) NOT NULL, skipped int(10) DEFAULT NULL);";
		$log->debug('Creating DPL history database table');
		eval {$dbh->do($sqlCreate)};
		if ($@) {
			msg("Couldn't create DPL history database table: [$@]");
		}
	}
	$log->debug('Creating DPL history database indexes');
	my $sqlIndex = "CREATE UNIQUE INDEX IF NOT EXISTS idClientIndex on dynamicplaylist_history (id,client);";
	eval {$dbh->do($sqlIndex)};
	if ($@) {
		msg("Couldn't index DPL history database table: [$@]");
	}
	commit($dbh);
}

sub getNoOfItemsInHistory {
	my $client = shift;
	my $result = 0;
	my $dbh = getCurrentDBH();
	eval {
		my $clientid = $dbh->quote($client->id);
		my $sql = "select count(position) from dynamicplaylist_history where dynamicplaylist_history.client=$clientid and skipped=0";
		my $sth = $dbh->prepare($sql);
		$log->debug("Executing history count SQL: $sql");
		$sth->execute() or do {
			$log->debug("Error executing: $sql");
			$sql = undef;
		};
		if (defined($sql)) {
			my $count = undef;
			$sth->bind_columns(undef, \$count);
			if ($sth->fetch()) {
				$result = $count;
			}
		}
	};
	if ($@) {
		$log->warn("Error history count: $@");
	}
	return $result;
}

sub addToPlayListHistory {
	my ($client, $track, $skipped, $addedTime) = @_;

	if (Slim::Music::Import->stillScanning && (!UNIVERSAL::can('Slim::Music::Import', 'externalScannerRunning') || Slim::Music::Import->externalScannerRunning)) {
		$log->debug('Adding track to queue: '.$track->url);
		my $item = {
			'url' => $track->url,
			'skipped' => $skipped,
			'addedTime' => $addedTime,
		};
		my $existing = $historyQueue->{$client->id};
		if (!defined($existing)) {
			my @empty = ();
			$historyQueue->{$client->id} = \@empty;
			$existing = \@empty;
		}
		push @{$existing}, $item;
		return;
	}

	my $dbh = getCurrentDBH();
	my $sth = $dbh->prepare("INSERT OR REPLACE INTO dynamicplaylist_history (client, id, url, added, skipped) values (?,".$track->id.", ?, ".$addedTime.",".$skipped.")");
	eval {
		$sth->bind_param(1, $client->id , SQL_VARCHAR);
		$sth->bind_param(2, $track->url , SQL_VARCHAR);
		$sth->execute();
		commit($dbh);
	};
	if ($@) {
		$log->warn("Database error: $DBI::errstr");
		eval {
			rollback($dbh); #just die if rollback is failing
		};
	}
	$sth->finish();
}

sub clearPlayListHistory {
	my $clients = shift;
	my $dbh = getCurrentDBH();

	if (Slim::Music::Import->stillScanning && (!UNIVERSAL::can('Slim::Music::Import', 'externalScannerRunning') || Slim::Music::Import->externalScannerRunning)) {
		if (defined($clients)) {
			foreach my $client (@{$clients}) {
				my @empty = ();
				$historyQueue->{$client->id} = \@empty;
				$deleteQueue->{$client->id} = 1;
			}
		} else {
			$historyQueue = {};
			$deleteAllQueues = 1;
		}
		return;
	}

	my $sth = undef;
	if (defined($clients)) {
		my $clientIds = '';
		foreach my $client (@{$clients}) {
			$log->debug('Deleting playlist history for player: '.$client->name);
			if ($clientIds ne '') {
				$clientIds .= ',';
			}
			$clientIds .= $dbh->quote($client->id);
		}
		my $sql = "DELETE FROM dynamicplaylist_history where client in ($clientIds)";
		$sth = $dbh->prepare($sql);
	} else {
		$sth = $dbh->prepare("DELETE FROM dynamicplaylist_history");
	}
	eval {
		$sth->execute();
		commit($dbh);
	};
	if ($@) {
		$log->warn("Database error: $DBI::errstr");
		eval {
			rollback($dbh); #just die if rollback is failing
		};
	}
	$sth->finish();
}


## titleformats ##

sub getMusicInfoSCRCustomItems {
	my $customFormats = {
		'DYNAMICPLAYLIST' => {
			'cb' => \&getTitleFormatDynamicPlaylist,
		},
		'DYNAMICORSAVEDPLAYLIST' => {
			'cb' => \&getTitleFormatDynamicPlaylist,
		},
	};
	return $customFormats;
}

sub getTitleFormatDynamicPlaylist {
	my $client = shift;
	my $song = shift;
	my $tag = shift;

	$log->debug("Entering getTitleFormatDynamicPlaylist with $client and $tag");
	my $masterClient = masterOrSelf($client);

	my $playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});

	if ($playlist) {
		$log->debug('Exiting getTitleFormatDynamicPlaylist with '.$playlist->{'name'});
		return $playlist->{'name'};
	}

	if ($tag =~ 'DYNAMICORSAVEDPLAYLIST') {
		my $playlist = Slim::Music::Info::playlistForClient($client);
		if ($playlist && $playlist->content_type ne 'cpl') {
			$log->debug('Exiting getTitleFormatDynamicPlaylist with '.$playlist->title);
			return $playlist->title;
		}
	}
	$log->debug('Exiting getTitleFormatDynamicPlaylist with undef');
	return undef;
}


## CustomSkip filters ##

sub getCustomSkipFilterTypes {
	my @result = ();

	my %recentlyaddedalbums = (
		'id' => 'dynamicplaylist_recentlyaddedalbum',
		'name' => 'Recently added album',
		'description' => 'Skip songs from albums that have been recently added to current dynamic playlist',
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => 'Songs between',
				'data' => '1=1 song,2=2 songs,2=3 songs,4=4 songs,5=5 songs,10=10 songs,20=20 songs,30=30 songs,50=50 songs',
				'value' => 10
			}
		]
	);
	push @result, \%recentlyaddedalbums;
	my %recentlyaddedartists = (
		'id' => 'dynamicplaylist_recentlyaddedartist',
		'name' => 'Recently added artist',
		'description' => 'Skip songs by artists that have been recently added to current dynamic playlist',
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => 'Songs between',
				'data' => '1=1 song,2=2 songs,2=3 songs,4=4 songs,5=5 songs,10=10 songs,20=20 songs,30=30 songs,50=50 songs',
				'value' => 10
			}
		]
	);
	push @result, \%recentlyaddedartists;
	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $sql = undef;
	my $result = 0;
	my $dbh = getCurrentDBH();
	if ($filter->{'id'} eq 'dynamicplaylist_recentlyaddedartist') {
		my $matching = 0;
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'nooftracks') {
				my $values = $parameter->{'value'};
				my $nooftracks = $values->[0] if (defined($values) && scalar(@{$values}) > 0);

				my $artist = $track->artist();
				if (defined($artist) && defined($client) && defined($nooftracks)) {
					my $artistid = $artist->id;
					my $clientid = $dbh->quote($client->id);
					my $noOfItems = getNoOfItemsInHistory($client);
					if ($noOfItems <= $nooftracks) {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join contributor_track on contributor_track.track=dynamicplaylist_history.id where contributor_track.contributor=$artistid and dynamicplaylist_history.client=$clientid";
					} else {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join contributor_track on contributor_track.track=dynamicplaylist_history.id where contributor_track.contributor=$artistid and dynamicplaylist_history.client=$clientid and dynamicplaylist_history.position > (select position from dynamicplaylist_history where dynamicplaylist_history.client=$clientid and skipped=0 order by position desc limit 1 offset $nooftracks)";
					}
				}
				last;
			}
		}
	} elsif ($filter->{'id'} eq 'dynamicplaylist_recentlyaddedalbum') {
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'nooftracks') {
				my $values = $parameter->{'value'};
				my $nooftracks = $values->[0] if (defined($values) && scalar(@{$values}) > 0);

				my $album = $track->album();

				if (defined($album) && defined($client) && defined($nooftracks)) {
					my $albumid = $album->id;
					my $clientid = $dbh->quote($client->id);
					my $noOfItems = getNoOfItemsInHistory($client);
					if ($noOfItems <= $nooftracks) {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join tracks on tracks.id=dynamicplaylist_history.id where tracks.album=$albumid and dynamicplaylist_history.client=$clientid";
					} else {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join tracks on tracks.id=dynamicplaylist_history.id where tracks.album=$albumid and dynamicplaylist_history.client=$clientid and dynamicplaylist_history.position > (select position from dynamicplaylist_history where dynamicplaylist_history.client=$clientid and skipped=0 order by position desc limit 1 offset $nooftracks)";
					}
				}
				last;
			}
		}
	}
	if (defined($sql)) {
		eval {
			my $sth = $dbh->prepare($sql);
			$log->debug("Executing skip filter SQL: $sql");
			$sth->execute() or do {
				$log->warn("Error executing: $sql");
				$sql = undef;
			};
			if (defined($sql)) {
				my $position;
				$sth->bind_columns(undef, \$position);
				if ($sth->fetch()) {
					$result = 1;
				}
			}
		};
		if ($@) {
			$log->warn("Error executing filter: $@");
		}
	}
	return $result;
}



## helpers ##

sub cliIsActive {
	my $request = shift;
	my $client = $request->client();
	if (!$request->isQuery([['dynamicplaylist'], ['isactive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		return;
	}

	$request->addResult('_isactive', active($client) );
	$request->setStatusDone();
}

sub active {
	my $client = shift;
	my $mixStatus = $client->pluginData('type');
	$log->debug('mixStatus = '.Dumper($mixStatus));
	return $mixStatus;
}

sub disableDSTM {
	my ($class, $client) = @_;
	return active($client);
}

sub getExcludedGenreList {
	my $excludegenres_namelist = $prefs->get('excludegenres_namelist');
	my $excludedgenreString = '';
	if ((defined $excludegenres_namelist) && (scalar @{$excludegenres_namelist} > 0)) {
		foreach my $thisgenre (@{$excludegenres_namelist}) {
			if ($excludedgenreString eq '') {
				$excludedgenreString = "'".$thisgenre."'";
			} else {
				$excludedgenreString = $excludedgenreString.", '".$thisgenre."'";
			}
		}
	}
	return $excludedgenreString;
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub {
			my $client = shift;
			$client->bumpRight();
		},
		'play' => sub {
			my $client = shift;
			my $button = shift;
			my $playlistId = shift;

			playRandom($client, $playlistId, 0, 1);
		},
		'continue' => sub {
			my $client = shift;
			my $button = shift;
			my $playlistId = shift;

			playRandom($client, $playlistId, 0, 1, undef, 1);
		}
	}
}

sub getDisplayName {
	return 'PLUGIN_DYNAMICPLAYLIST';
}

sub masterOrSelf {
	my $client = shift;
	if (!defined($client)) {
		return $client;
	}
	return $client->master();
}

sub validateIntOrEmpty {
	my $arg = shift;
	if (!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub fisher_yates_shuffle {
	my $myarray = shift;
	my $i = @{$myarray};
	if (scalar(@{$myarray}) > 1) {
		while (--$i) {
			my $j = int rand ($i + 1);
			@{$myarray}[$i, $j] = @{$myarray}[$j, $i];
		}
	}
}

sub objectForId {
	my $type = shift;
	my $id = shift;
	if ($type eq 'artist') {
		$type = 'Contributor';
	} elsif ($type eq 'album') {
		$type = 'Album';
	} elsif ($type eq 'genre') {
		$type = 'Genre';
	} elsif ($type eq 'track') {
		$type = 'Track';
	} elsif ($type eq 'playlist') {
		$type = 'Playlist';
	}
	return Slim::Schema->resultset($type)->find($id);
}

sub getLinkAttribute {
	my $attr = shift;
	if ($attr eq 'artist') {
		$attr = 'contributor';
	}
	return $attr.'.id';
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

sub starts_with {
	# complete_string, start_string, position
	return rindex($_[0], $_[1], 0);
	# 0 for yes, -1 for no
}

sub printPlayListItems {
	my $currentpath = shift;
	my $items = shift;
	return;
	for my $itemKey (keys %{$items}) {
		my $item = $items->{$itemKey};
		if (defined($item->{'playlist'})) {
			my $playlist = $item->{'playlist'};
			$log->debug('Got: '.$currentpath.'/'.$playlist->{'name'}.' (enabled='.$item->{'dynamicplaylistenabled'}.', '.$playlist->{'dynamicplaylistid'}.','.$playlist->{'dynamicplaylistplugin'}.')');
		} else {
			my $childs = $item->{'childs'};
			printPlayListItems($currentpath.'/'.$item->{'name'}, $childs);
		}
	}
}

*escape = \&URI::Escape::uri_escape_utf8;

sub unescape {
	my $in = shift;
	my $isParam = shift;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
}

1;
