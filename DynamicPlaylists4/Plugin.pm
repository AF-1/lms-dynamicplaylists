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

package Plugins::DynamicPlaylists4::Plugin;

use strict;
use warnings;
use utf8;
use base qw(Slim::Plugin::Base);

use Slim::Buttons::Home;
use Slim::Player::Client;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Class::Struct;
use Digest::SHA1 qw(sha1_base64);
use File::Basename;
use File::Slurp; # for read_file
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use HTML::Entities; # for parsing
use List::Util qw(first);
use POSIX qw(strftime);
use Time::HiRes qw(time);
use Digest::MD5 qw(md5_hex);

my $prefs = preferences('plugin.dynamicplaylists4');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.dynamicplaylists4',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_DYNAMICPLAYLISTS4',
});

my %stopcommands = ();
my %mixInfo = ();
my $htmlTemplate = 'plugins/DynamicPlaylists4/dynamicplaylist_list.html';
my ($playLists, $localDynamicPlaylists, $localBuiltinDynamicPlaylists, $playListTypes, $playListItems, $jiveMenu);
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
my $cache = Slim::Utils::Cache->new();

my %empty = ();
my %choiceMapping;

my ($dplc_enabled, $dstm_enabled, $apc_enabled, $material_enabled);
my %categorylangstrings;
my %customsortnames;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (main::WEBUI) {
		require Plugins::DynamicPlaylists4::Settings::Basic;
		require Plugins::DynamicPlaylists4::Settings::PlaylistSettings;
		require Plugins::DynamicPlaylists4::Settings::FavouriteSettings;
		Plugins::DynamicPlaylists4::Settings::Basic->new();
		Plugins::DynamicPlaylists4::Settings::PlaylistSettings->new();
		Plugins::DynamicPlaylists4::Settings::FavouriteSettings->new();
	}

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
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlaylists4.ChooseParameters', getFunctions(), \&setModeChooseParameters);
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlaylists4.Mixer', getFunctions(), \&setModeMixer);
	my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'favorites'} = sub {Slim::Buttons::Input::Choice::callCallback('onFavorites', @_)};
	Slim::Buttons::Common::addMode('PLUGIN.DynamicPlaylists4.Choice', \%choiceFunctions, \&Slim::Buttons::Input::Choice::setMode);
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
	Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.DynamicPlaylists4.Choice', \%choiceMapping);

	Slim::Control::Request::subscribe(\&commandCallback, [['playlist'], ['newsong', 'delete', keys %stopcommands]]);
	Slim::Control::Request::subscribe(\&powerCallback, [['power']]);
	Slim::Control::Request::subscribe(\&clientNewCallback, [['client'], ['new']]);
	Slim::Control::Request::subscribe(\&rescanDone, [['rescan'], ['done']]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'isactive'], [1, 1, 0, \&cliIsActive]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlists', '_all', '_start', '_itemsPerResponse'], [1, 1, 0, \&cliGetPlaylists]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'play'], [1, 0, 1, \&cliPlayPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'add'], [1, 0, 1, \&cliAddPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'dstmplay'], [1, 0, 1, \&cliDstmSeedListPlay]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'queue'], [1, 0, 1, \&cliQueuePlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'continue'], [1, 0, 1, \&cliContinuePlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'playlist', 'stop'], [1, 0, 0, \&cliStopPlaylist]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'browsejive', '_start', '_itemsPerResponse'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'jiveplaylistparameters', '_start', '_itemsPerResponse'], [1, 1, 1, \&cliJivePlaylistParametersHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'actionsmenu'], [1, 1, 1, \&_cliJiveActionsMenuHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'savestaticpljiveparams'], [1, 1, 1, \&_saveStaticPlaylistJiveParams]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'savestaticpljive'], [1, 0, 1, \&_saveStaticPlaylistJive]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'jivesaveasfav'], [1, 1, 1, \&_cliJiveSaveFavWithParams]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'contextmenujive'], [1, 1, 1, \&cliContextMenuJiveHandler]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'preselect'], [1, 1, 1, \&_preselectionMenuJive]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'queuelist'], [1, 1, 1, \&_queueMenuJive]);
	Slim::Control::Request::addDispatch(['dynamicplaylist', 'refreshplaylists'], [1, 0, 0, \&cliRefreshPlaylists]);
	Slim::Control::Request::addDispatch(['dynamicplaylistmultipletoggle', '_paramtype', '_item', '_value'], [1, 0, 0, \&_toggleMultipleSelectionState]);
	Slim::Control::Request::addDispatch(['dynamicplaylistmultipleall', '_paramtype', '_value'], [1, 0, 0, \&_multipleSelectAllOrNone]);

	Slim::Player::ProtocolHandlers->registerHandler(dynamicplaylist => 'Plugins::DynamicPlaylists4::ProtocolHandler');
	Slim::Player::ProtocolHandlers->registerHandler(dynamicplaylistaddonly => 'Plugins::DynamicPlaylists4::PlaylistProtocolHandler');
}

sub postinitPlugin {
	my $class = shift;
	$dplc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::DynamicPlaylistCreator::Plugin');
	main::DEBUGLOG && $log->is_debug && $log->debug('Plugin "Dynamic Playlist Creator" is enabled') if $dplc_enabled;
	$apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	main::DEBUGLOG && $log->is_debug && $log->debug('Plugin "Alternative Play Count" is enabled') if $apc_enabled;
	$material_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::MaterialSkin::Plugin');
	main::DEBUGLOG && $log->is_debug && $log->debug('Plugin "Material Skin" is enabled') if $material_enabled;
	$dstm_enabled = Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DontStopTheMusic::Plugin');
	main::DEBUGLOG && $log->is_debug && $log->debug('DSTM is enabled') if $dstm_enabled;
	Slim::Utils::Timers::setTimer(undef, Time::HiRes::time() + 3, sub {
		clearCache();
	});
	initPlayLists();
	initPlayListTypes();
	registerJiveMenu($class);
	registerStandardContextMenus();
}

sub initPrefs {
	$prefs->init({
		customdirparentfolderpath => Slim::Utils::OSDetect::dirsFor('prefs'),
		max_number_of_unplayed_tracks => 20,
		min_number_of_unplayed_tracks => 5,
		number_of_played_tracks_to_keep => 3,
		song_adding_check_delay => 20,
		song_min_duration => 90,
		toprated_min_rating => 60,
		period_playedlongago => 2,
		minartisttracks => 3,
		minalbumtracks => 3,
		dstmstartindex => 1,
		rememberactiveplaylist => 1,
		groupunclassifiedcustomplaylists => 1,
		showtimeperchar => 70,
		randomsavedplaylists => 1,
		flatlist => 0,
		structured_savedplaylists => 1,
		pluginshufflemode => 1,
		enablestaticplsaving => 1
	});
	refreshPluginPlaylistFolder();
	createCustomPlaylistFolder();

	$prefs->setValidate(sub {
		return if (!$_[1] || !(-d $_[1]) || (main::ISWINDOWS && !(-d Win32::GetANSIPathName($_[1]))) || !(-d Slim::Utils::Unicode::encode_locale($_[1])));
		my $customPlaylistFolder = catdir($_[1], 'DPL-custom-lists');
		eval {
			mkdir($customPlaylistFolder, 0755) unless (-d $customPlaylistFolder);
		} or do {
			$log->error("Could not create custom playlist folder in parent folder '$_[1]'! Please make sure that LMS has read/write permissions (755) for the parent folder.");
			return;
		};
		$prefs->set('customplaylistfolder', $customPlaylistFolder);
		return 1;
	}, 'customdirparentfolderpath');

	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 50}, 'max_number_of_unplayed_tracks');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 0, 'high' => 100}, 'number_of_played_tracks_to_keep');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 60}, 'song_adding_check_delay');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 1800}, 'song_min_duration');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 20}, 'period_playedlongago');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 10}, qw(min_number_of_unplayed_tracks minartisttracks minalbumtracks));
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 0, 'high' => 200}, 'showtimeperchar');
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 100, 'high' => 10000}, 'saveasstaticplmaxtracks');

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

	%categorylangstrings = (
		'Songs' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_TRACKS'),
		'Artists' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_ARTISTS'),
		'Albums' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_ALBUMS'),
		'Works' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_WORKS'),
		'Genres' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_GENRES'),
		'Years' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_YEARS'),
		'Playlists' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_CATNAME_PLAYLISTS'),
		'Static Playlists' => string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_WEBLIST_STATICPLAYLISTS'),
		'Not classified' => string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_GROUPNAME_NOTCLASSIFIED')
	);

	%customsortnames = (string('PLUGIN_DYNAMICPLAYLISTS4_FAVOURITES') => '00001_Favourites', 'Songs' => '00002_Songs', 'Artists' => '00003_Artists', 'Albums' => '00004_Albums', 'Works' => '00005_Works', 'Genres' => '00006_Genres', 'Years' => '00007_Years', 'Playlists' => '00008_PLaylists', 'Static Playlists' => '00009_static_LMS_playlists', 'Not classified' => '00010_not_classified', 'Context menu lists' => '00011_contextmenulists');
}


sub initPlayLists {
	my $client = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('Searching for playlists');

	$localDynamicPlaylists = () unless $client && active($client);
	main::DEBUGLOG && $log->is_debug && $log->debug('mix status = '.Data::Dump::dump(active($client))) if $client;

	readParseLocalDynamicPlaylists();
	#main::DEBUGLOG && $log->is_debug && $log->debug('localDynamicPlaylists = '.Data::Dump::dump($localDynamicPlaylists));

	my %localPlayLists = ();
	my %localPlayListItems = ();
	my %unclassifiedPlaylists = ();
	my $savedstaticPlaylists = undef;

	my @enabledplugins = Slim::Utils::PluginManager->enabledPlugins();
	for my $plugin (@enabledplugins) {
		if (UNIVERSAL::can("$plugin", 'getDynamicPlaylists') && UNIVERSAL::can("$plugin", 'getNextDynamicPlaylistTracks')) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Getting dynamic playlists for: $plugin");
			no strict 'refs';
			my $items = eval {&{"${plugin}::getDynamicPlaylists"}($client)};
			if ($@) {
				$log->error("Error getting playlists from $plugin: $@");
			}
			use strict 'refs';

			for my $item (keys %{$items}) {
				$plugins{$item} = "${plugin}";
				my $playlist = $items->{$item};
				main::DEBUGLOG && $log->is_debug && $log->debug('Got dynamic playlist: '.$playlist->{'name'});

				# skip playlists if current LMS version < required LMS version
				if ($playlist->{'minlmsversion'} && Slim::Utils::Versions->compareVersions($::VERSION, $playlist->{'minlmsversion'}) == -1) {
					$log->info('LMS version = '.$::VERSION.' -- min. required LMS version for playlist "'.$playlist->{'name'}.'" = '.$playlist->{'minlmsversion'});
					next;
				}

				$playlist->{'dynamicplaylistid'} = $item;
				$playlist->{'dynamicplaylistplugin'} = $plugin;
				my $isStaticPL;

				my $pluginshortname = $plugin;
				if (starts_with($item, 'dpldefault_') == 0) {
					$pluginshortname = 'Dynamic Playlists - '.string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_DPLBUILTIN');
				} elsif (starts_with($item, 'dplusercustom_') == 0) {
					$pluginshortname = 'Dynamic Playlists - '.string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_DPLCUSTOM');
				} elsif (starts_with($item, 'dplstaticpl_') == 0) {
					$pluginshortname = string('SETTINGS_PLUGIN_DYNAMICPLAYLISTS4_STATICPL');
					$savedstaticPlaylists = 'found saved static playlists';
					$isStaticPL = 1;
				} elsif (starts_with($item, 'dplccustom_') == 0) {
					$pluginshortname = 'Dynamic Playlist Creator';
				} else {
					$pluginshortname =~ s/^Plugins::|::Plugin+$//g;
				}
				$playlist->{'dynamicplaylistpluginshortname'} = $pluginshortname;
				$playlist->{'isStaticPL'} = $isStaticPL;

				my $enabled = $prefs->get('playlist_'.$item.'_enabled');
				$playlist->{'dynamicplaylistenabled'} = (!defined $enabled || $enabled) ? 1 : 0;
				my $favourite = $prefs->get('playlist_'.$item.'_favourite');
				$playlist->{'dynamicplaylistfavourite'} = (defined($favourite) && $favourite) ? 1 : 0;

				$playlist->{'isFavorite'} = defined(Slim::Utils::Favorites->new($client)->findUrl('dynamicplaylist://'.$playlist->{'dynamicplaylistid'}))?1:0;

				if (defined($playlist->{'parameters'})) {
					my $hasNoVolatileParam = 1;
					foreach my $p (keys %{$playlist->{'parameters'}}) {
						# mark dpls with volatile params whose value may change after delete/wipe rescan
						my %volatileParams = map { $_ => 1 } ('artist', 'album', 'genre', 'multiplegenres', 'playlist', 'multiplestaticplaylists');
						my $paramType = $playlist->{'parameters'}->{$p}->{'type'};
						if ($volatileParams{$paramType}) {
								main::DEBUGLOG && $log->is_debug && $log->debug("Playlist '".$playlist->{'name'}."' contains volatile param type '".$paramType."'");
								$hasNoVolatileParam = 0;
						}

						# Use existing value for PlaylistParameter if available
						if (defined($playLists)
							&& defined($playLists->{$item})
							&& defined($playLists->{$item}->{'parameters'})
							&& defined($playLists->{$item}->{'parameters'}->{$p})
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'name'})
							&& $playLists->{$item}->{'parameters'}->{$p}->{'name'} eq $playlist->{'parameters'}->{$p}->{'name'}
							&& defined($playLists->{$item}->{'parameters'}->{$p}->{'value'})) {

							main::DEBUGLOG && $log->is_debug && $log->debug("Use already existing value for PlaylistParameter$p = ".$playLists->{$item}->{'parameters'}->{$p}->{'value'});
							$playlist->{'parameters'}->{$p}->{'value'} = $playLists->{$item}->{'parameters'}->{$p}->{'value'};
						}
					}
					$playlist->{'hasnovolatileparams'} = $hasNoVolatileParam;
				}
				$localPlayLists{$item} = $playlist;

				if (!$playlist->{'playlistcategory'}) {
					if ($playlist->{'menulisttype'} && ($playlist->{'menulisttype'} eq 'contextmenu')) {
						$unclassifiedPlaylists{'unclassifiedContextMenuPlaylists'} = 'found unclassified CPL';
					} else {
						$unclassifiedPlaylists{'unclassifiedPlaylists'} = 'found unclassified PL';
					}
				}

				if (!$playlist->{'playlistsortname'}) {
					my $playlistSortPrefix = lc($pluginshortname);
					$playlist->{'playlistsortname'} = $playlistSortPrefix.'_'.$playlist->{'name'};
				}

				my $groups = $playlist->{'groups'};
				if (!defined($groups)) {
					my $groupunclassifiedcustomplaylists = $prefs->get('groupunclassifiedcustomplaylists');
					$groups = [['Not classified']] if $groupunclassifiedcustomplaylists;
				}
				if (!defined($groups)) {
					my @emptyArray = ();
					$groups = \@emptyArray;
				}
				if ($favourite) {
					my @favouriteGroups = ();
					for my $g (@{$groups}) {
						push @favouriteGroups, $g;
					}
					my @favouriteGroup = ();
					push @favouriteGroup, string('PLUGIN_DYNAMICPLAYLISTS4_FAVOURITES');
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
								if ($group && $group eq 'Context menu lists') {
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
									'groupsortname' => $group,
									'value' => $grouppath,
								);
								if ($enabled) {
									$enabled = $prefs->get('playlist_group_'.$grouppath.'_enabled');
									if (!defined($enabled)) {
										$enabled = 1;
									}
								}
								$currentItemGroup{'dynamicplaylistenabled'} = ($enabled && $playlist->{'dynamicplaylistenabled'}) ? 1 : 0;
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
	addAlarmPlaylists(\%localPlayLists);
	$rescan = 0;

	$playLists = \%localPlayLists;
	$playListItems = \%localPlayListItems;
	#main::INFOLOG && $log->is_info && $log->info('localPlayListItems = '.Data::Dump::dump(\%localPlayListItems));
	#main::DEBUGLOG && $log->is_debug && $log->debug('playLists = '.Data::Dump::dump($playLists));

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
					if ($parameter1->{'type'} && ($parameter1->{'type'} eq 'album' || $parameter1->{'type'} eq 'artist' || $parameter1->{'type'} eq 'year' || $parameter1->{'type'} eq 'genre' || $parameter1->{'type'} eq 'multiplegenres' || $parameter1->{'type'} eq 'multipledecades' || $parameter1->{'type'} eq 'multipleyears' || $parameter1->{'type'} eq 'multiplestaticplaylists' || $parameter1->{'type'} eq 'playlist' || $parameter1->{'type'} eq 'track' || $parameter1->{'type'} eq 'virtuallibrary')) {
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
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding '.scalar(@alarmPlaylists).' playlists to alarm handler');
		Slim::Utils::Alarm->addPlaylists('PLUGIN_DYNAMICPLAYLISTS4', \@alarmPlaylists);
	}
}

sub getPlayList {
	my ($client, $type) = @_;
	return undef unless $type;

	main::DEBUGLOG && $log->is_debug && $log->debug('Get playlist: '.$type);
	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	return undef unless $playLists;

	return $playLists->{$type};
}


# Find tracks matching parameters and add them to the playlist
sub findAndAdd {
	my ($client, $type, $offset, $limit, $addOnly, $continue, $unlimited, $forcedAddDifferentPlaylist) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("Starting random selection of max. $limit items for type: $type");
	my $started = time();
	Slim::Utils::Timers::killTimers($client, \&findAndAdd);

	my $masterClient = masterOrSelf($client);
	my $playlist = getPlayList($client, $type);
	my $isStaticPL = $playlist->{'isStaticPL'};
	main::DEBUGLOG && $log->is_debug && $log->debug('is static PL = '.Data::Dump::dump($isStaticPL));
	my $playlistTrackOrder = $playlist->{'playlisttrackorder'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistTrackOrder = '.Data::Dump::dump($playlistTrackOrder));
	my $minUnplayedTracks = $prefs->get('min_number_of_unplayed_tracks');
	my ($newTrackIDs, $filteredtrackIDs);
	my ($totalTracksCompleteInfo, $newTracksCompleteInfo) = {};
	my $totalTrackIDList = [];

	my $dplUseCache = $playlist->{'usecache'};
	$dplUseCache = undef if $forcedAddDifferentPlaylist;
	main::DEBUGLOG && $log->is_debug && $log->debug('dplUseCache = '.Data::Dump::dump($dplUseCache));

	# Get cache content if cache is used and filled
	if ($dplUseCache) {
		my $getCacheContentStartTime = time();
		$totalTrackIDList = $cache->get('dpl_totalTrackIDlist_' . $client->id) || [];
		$totalTracksCompleteInfo = $cache->get('dpl_totalTracksCompleteInfo_' . $client->id) || {};
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting cache content - exec time = '.(time() - $getCacheContentStartTime).' secs') if (scalar(@{$totalTrackIDList}) > 0 && keys %{$totalTracksCompleteInfo} > 0);
	}

	if (scalar(@{$totalTrackIDList}) > 0) {
		# dynamic playlists that use cache should not contain SQLite limit
		main::DEBUGLOG && $log->is_debug && $log->debug('Using (remaining) '.scalar(@{$totalTrackIDList}).' cached track IDs');
	} elsif (!$client->pluginData('cacheFilled') || $forcedAddDifferentPlaylist) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Cache '.($dplUseCache ? 'empty' : 'not used').'. Getting track IDs');
		my $noOfRetriesToGetUnplayedTracks = $dplUseCache ? 1 : 20;
		my $i = 1;
		while ($i <= $noOfRetriesToGetUnplayedTracks) {
			my $iterationStartTime = time();
			main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: total trackIDs so far = ".scalar(@{$totalTrackIDList}).' -- limit = '.$limit.' -- offset = '.$offset);

			# Get track IDs
			my $getTrackIDsForPlaylistStartTime = time();
			($newTrackIDs, $newTracksCompleteInfo) = getTrackIDsForPlaylist($masterClient, $playlist, $limit, $offset + scalar(@{$totalTrackIDList}));

			if ($newTrackIDs && $newTrackIDs eq 'error') {
				$log->error('Error trying to find tracks. Please check your playlist definition.');
				last;
			}

			main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: returned ".(defined $newTrackIDs ? scalar(@{$newTrackIDs}) : 0).' tracks in '.(time()-$getTrackIDsForPlaylistStartTime). ' seconds');

			if (!defined $newTrackIDs || scalar(@{$newTrackIDs}) == 0) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i didn't return any track IDs");
				$i++;
				next;
			}

			# Filter track IDs
			unless ($dplUseCache) {
				#main::DEBUGLOG && $log->is_debug && $log->debug('newTrackIDs = '.Data::Dump::dump($newTrackIDs));
				my $filterTrackIDsStartTime = time();
				$newTrackIDs = filterTrackIDs($masterClient, $newTrackIDs, $totalTrackIDList, $forcedAddDifferentPlaylist ? 1 : 0);
				main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: returned ".(scalar @{$newTrackIDs}).((scalar @{$newTrackIDs}) == 1 ? ' item' : ' items').' after filtering. Filtering took '.(time()-$filterTrackIDsStartTime).' seconds');
				#main::DEBUGLOG && $log->is_debug && $log->debug('newTrackIDs after filtering = '.Data::Dump::dump($newTrackIDs));
			}

			# Add new tracks to total track vars
			my $addingNewTracksToTotalVars = time();
			if (scalar(@{$totalTrackIDList}) == 0) {
				$totalTrackIDList = $newTrackIDs;
			} else {
				main::DEBUGLOG && $log->is_debug && $log->debug('totaltracks > 0');
				push (@{$totalTrackIDList}, @{$newTrackIDs});
			}

			if (keys %{$newTracksCompleteInfo} > 0) {
				$totalTracksCompleteInfo = $newTracksCompleteInfo if keys %{$newTracksCompleteInfo} > 0;
			} else {
				$totalTracksCompleteInfo = { %{$totalTracksCompleteInfo}, %{$newTracksCompleteInfo} } if keys %{$newTracksCompleteInfo} > 0;
			}
			main::DEBUGLOG && $log->is_debug && $log->debug('Adding new tracks to total tracks vars exec time = '.(time() - $addingNewTracksToTotalVars).' secs');
			main::DEBUGLOG && $log->is_debug && $log->debug('Total track IDs found so far = '.scalar(@{$totalTrackIDList}));

			# store totalTracksCompleteInfo in cache if cache is used
			if ($dplUseCache) {
				my $storingCacheCompleteInfoStartTime = time();
				$cache->set('dpl_totalTracksCompleteInfo_' . $client->id, $totalTracksCompleteInfo, 'never');
				main::DEBUGLOG && $log->is_debug && $log->debug('Storing complete info hash in cache exec time = '.(time() - $storingCacheCompleteInfoStartTime).' secs');
			}

			# stop or get more tracks
			if ($unlimited) {
				if (scalar(@{$totalTrackIDList}) >= $minUnplayedTracks) {
					main::DEBUGLOG && $log->is_debug && $log->debug('Unlimited option: totalTrackIDs '.scalar(@{$totalTrackIDList}).' >= '.$minUnplayedTracks.' minUnplayedTracks');
					last;
				}
			} else {
				# if fetching tracks takes a long time but we already have more than the minimum number of unplayed tracks
				# let's start playback and get the rest of the tracks later
				if ((time() - $iterationStartTime) > 5 && scalar(@{$totalTrackIDList}) >= $minUnplayedTracks && scalar(@{$totalTrackIDList}) < $limit) {
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 15, \&findAndAdd, $type, $offset, $limit - scalar(@{$totalTrackIDList}), 1, 0);
					main::DEBUGLOG && $log->is_debug && $log->debug('Getting tracks took '.(time() - $iterationStartTime).' secs so far. Will start playlist with '.scalar(@{$totalTrackIDList}).' tracks and fetch '.($limit - scalar(@{$totalTrackIDList})).' tracks later');
					last;
				}
				last if scalar(@{$totalTrackIDList}) >= $limit;
			}
			$i++;
			my $idleStartTime = time();
			main::idleStreams();
			main::DEBUGLOG && $log->is_debug && $log->debug('idleStreams time = '.(time() - $idleStartTime).' secs');
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Total exec time so far = '.(time() - $started).' secs');

	if (scalar(@{$totalTrackIDList}) == 0) {
		main::INFOLOG && $log->is_info && $log->info('Have not found any (other) tracks that match your search parameters for dynamic playlist "'.$playlist->{'name'}.'" (query time = '.(time()-$started).' seconds).');
		return 0;
	}

	## shuffle all track IDs
	unless ($dplUseCache && $client->pluginData('cacheFilled') || $playlistTrackOrder && ($playlistTrackOrder eq 'ordered' || $playlistTrackOrder eq 'ordereddescrandom' || $playlistTrackOrder eq 'orderedascrandom') || $isStaticPL && $prefs->get('randomsavedplaylists') == 0) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Shuffling ALL track IDs for cache');
		my $shuffledIDlist = shuffleIDlist($totalTrackIDList, $totalTracksCompleteInfo);
		@{$totalTrackIDList} = @{$shuffledIDlist};

		$client->pluginData('cacheFilled' => 1) if $dplUseCache;
	}

	## limit results if necessary
	my $randomIDs2add;
	@{$randomIDs2add} = @{$totalTrackIDList};

	if (scalar(@{$totalTrackIDList}) > $limit) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Limiting the number of new tracks to be added to the specified limit ($limit)");
		my $limitingExecStartTime = time();

		if ($dplUseCache) {
			# get track ids from cache
			@{$randomIDs2add} = splice @{$totalTrackIDList}, 0, $limit;
			$cache->set('dpl_totalTrackIDlist_' . $client->id, $totalTrackIDList, 'never');
		} else {
			@{$randomIDs2add} = @{$totalTrackIDList}[0..($limit - 1)];
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Limiting exec time: '.(time() - $limitingExecStartTime).' secs');
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Removing cache because last batch of new track IDs in cache ('.scalar(@{$totalTrackIDList}).") <= limit ($limit)");
		$cache->remove('dpl_totalTrackIDlist_'.$client->id) if $dplUseCache;
	}

	## add new tracks (cache or force-added) to DPL history in case we get a forced add for a different dynamic playlist while the current one is still active
	if ($dplUseCache || $forcedAddDifferentPlaylist) {
		my $addToHistoryStartTime = time();
		for my $trackID (@{$randomIDs2add}) {
			my $addedTime = time();
			addToPlayListHistory($client, $trackID, $addedTime);
			my @players = Slim::Player::Sync::slaves($client);
			foreach my $player (@players) {
				addToPlayListHistory($player, $trackID, $addedTime);
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding new tracks from cache to DPL history exec time: '.(time() - $addToHistoryStartTime).' secs');
	}

	## shuffle limited track ID selection
	unless ($playlistTrackOrder && $playlistTrackOrder eq 'ordered' || $isStaticPL && $prefs->get('randomsavedplaylists') == 0) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Shuffling limited track ID selection');
		my $shuffledIDlist = shuffleIDlist($randomIDs2add, $totalTracksCompleteInfo);
		@{$randomIDs2add} = @{$shuffledIDlist};
	}

	# sort shuffled track ID selection by play count
	if ($dplUseCache && $playlistTrackOrder && ($playlistTrackOrder eq 'ordereddescrandom' || $playlistTrackOrder eq 'orderedascrandom')) {
		my $sortingByPlayCountExecStartTime = time();
		my $playCountSortOrder = $playlistTrackOrder eq 'ordereddescrandom' ? 2 : 1; # 1 = asc, 2 = desc
		$randomIDs2add = sortByPlayCount($randomIDs2add, $totalTracksCompleteInfo, $playCountSortOrder);
		main::DEBUGLOG && $log->is_debug && $log->debug('Sorting new batch of tracks by play count exec time: '.(time() - $sortingByPlayCountExecStartTime).' secs');
	}

	## add tracks to client playlist
	my $noOfTotalItems = scalar(@{$randomIDs2add}); # get no of total items before shifting first track

	my $firstTrackID = shift @{$randomIDs2add};
	if ($firstTrackID) {
		main::DEBUGLOG && $log->is_debug && $log->debug((($addOnly || $continue) ? 'Adding ' : 'Playing ')."$type with first trackid ".($firstTrackID));
		my $addingExecStartTime = time();
		# Replace the current playlist with the first item / track or add it to end
		my $request = $client->execute(['playlist', (($addOnly && $addOnly != 2) || $continue) ? 'addtracks' : 'loadtracks', sprintf('%s=%d', getLinkAttribute('track'), $firstTrackID)]);
		$request->source('PLUGIN_DYNAMICPLAYLISTS4');

		# Add the remaining items to the end
		if (!defined $limit || $limit > 1 || scalar(@{$randomIDs2add}) >= 1) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Adding '.scalar(@{$randomIDs2add}).' tracks to the end of the playlist.');
			if(scalar(@{$randomIDs2add}) >= 1) {
				foreach my $id (@{$randomIDs2add}) {
					$request = $client->execute(['playlist', 'addtracks', sprintf('%s=%d', getLinkAttribute('track'), $id)]);
					$request->source('PLUGIN_DYNAMICPLAYLISTS4');
				}
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding tracks to client playlist exec time: '.(time() - $addingExecStartTime).' secs');
	}
	main::INFOLOG && $log->is_info && $log->info('Got '.$noOfTotalItems.($noOfTotalItems == 1 ? ' track' : ' tracks').' for dynamic playlist "'.$playlist->{'name'}.'" in '.(time()-$started)." seconds.\n\n");
	return $noOfTotalItems;
}

sub shuffleIDlist {
	my ($idList, $totalTracksCompleteInfo) = @_;

	# pluginshufflemode: 1 = normal shuffle, 2 = balanced shuffle, 3 = disabled
	if ($prefs->get('pluginshufflemode') == 3) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Not shuffling tracks. Globally disabled');
	} else {
		my $shuffleExecTime = time();
		if ($prefs->get('pluginshufflemode') == 2 && keys %{$totalTracksCompleteInfo} > 0) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Using balanced shuffle mode with primary artist info from completeInfo hash');
			$idList = Slim::Player::Playlist::balancedShuffle([ map { [$_, $totalTracksCompleteInfo->{$_}->{'primary_artist'}] } @{$idList} ]);
		} elsif ($prefs->get('pluginshufflemode') == 2 && scalar(@{$idList}) <= 8000) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Using balanced shuffle mode without completeInfo hash if total number of ids <= 8000)');
			$idList = Slim::Player::Playlist::balancedShuffle([map { [$_, Slim::Schema->rs('Track')->single({'id' => $_})->artistid] } @{$idList} ]);
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Using normal shuffle mode');
			Slim::Player::Playlist::fischer_yates_shuffle($idList);
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Shuffle exec time: '.(time() - $shuffleExecTime).' secs');
	}
	return \@{$idList};
}

sub sortByPlayCount {
	my ($idList, $totalTracksCompleteInfo, $sortOrder) = @_;
	my $sorter = $sortOrder > 1 ? # 1 = asc, 2 = desc
		sub { ($totalTracksCompleteInfo->{$b}->{'playCount'} || 0) <=> ($totalTracksCompleteInfo->{$a}->{'playCount'} || 0) }
		: sub { ($totalTracksCompleteInfo->{$a}->{'playCount'} || 0) <=> ($totalTracksCompleteInfo->{$b}->{'playCount'} || 0) };
	my @sortedArr = sort $sorter @{$idList};
	return \@sortedArr;
}

sub filterTrackIDs {
	my ($client, $newTrackIDs, $totalTrackIDList, $dontAddToHistory) = @_;

	# filter for dupes in new items
	my $dedupeNewTrackIDsStartTime = time();
	if ($newTrackIDs && ref $newTrackIDs && scalar @{$newTrackIDs}) {
		my $seen ||= {};
		$newTrackIDs = [grep {!$seen->{$_}++} @{$newTrackIDs}];
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Deduping new track IDs exec time: '.(time() - $dedupeNewTrackIDsStartTime).' secs');

	# dedupe new items against total items
	if (defined $totalTrackIDList && scalar(@{$totalTrackIDList}) > 0) {
		my $dedupeAgainstAllTrackIDsStartTime = time();
		my %seen;
		@seen{map $_, @$totalTrackIDList} = ();
		$newTrackIDs = [
			grep {!exists $seen{$_}} @$newTrackIDs
		];
		main::DEBUGLOG && $log->is_debug && $log->debug('Deduping new against all track IDs exec time: '.(time() - $dedupeAgainstAllTrackIDsStartTime).' secs');
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Found these new non-dupe tracks: '.Data::Dump::dump(\@{$newTrackIDs}));

	# add new non-dupe tracks to DPL client history
	# unless it's a saved static PL or a forced add for a different dpl than the currently active one
	unless ($dontAddToHistory) {
		my $addToHistoryStartTime = time();
		for my $trackID (@{$newTrackIDs}) {
			my $addedTime = time();
			addToPlayListHistory($client, $trackID, $addedTime);
			my @players = Slim::Player::Sync::slaves($client);
			foreach my $player (@players) {
				addToPlayListHistory($player, $trackID, $addedTime);
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding new tracks to DPL history exec time: '.(time() - $addToHistoryStartTime).' secs');
	}

	return \@{$newTrackIDs};
}

sub playRandom {
	# If addOnly, then track(s) are appended to end. Otherwise, a new playlist is created.
	my ($client, $type, $addOnly, $showFeedback, $forcedAdd, $continue) = @_;
	my $masterClient = masterOrSelf($client);

	Slim::Utils::Timers::killTimers($client, \&playRandom);

	# Playlist name for (showBriefly) status message
	my $playlist = getPlayList($client, $type);
	my $playlistName = $playlist ? $playlist->{'name'} : '';

	# showTime per character so long messages get more time to scroll
	my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
	main::DEBUGLOG && $log->is_debug && $log->debug('playRandom called with type '.$type);

	$masterClient->pluginData('type' => $type);
	main::DEBUGLOG && $log->is_debug && $log->debug('pluginData type for '.$masterClient->name.' = '.$masterClient->pluginData('type'));
	main::DEBUGLOG && $log->is_debug && $log->debug('client pref type = '.$mixInfo{$masterClient}->{'type'}) if $mixInfo{$masterClient}->{'type'};

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
	if (($addOnly && $addOnly == 2) || !$mixInfo{$masterClient} || ($mixInfo{$masterClient} && keys %{$mixInfo{$masterClient}} == 0) || ($mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} ne $type && !$forcedAdd)) {
		$continue = undef;
		my @players = Slim::Player::Sync::slaves($masterClient);
		push @players, $masterClient;
		clearPlayListHistory(\@players);
		clearCache(\@players);

		# if dynamic playlist is set to repeat, record number of completed repeats
		$masterClient->pluginData('repeatcounter' => 1) if $playlist->{'repeat'};

		# Executing actions related to new mix
		if (!$addOnly) {
			my $startactions = undef;
			if ($type && $type ne 'disable') {
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
					main::DEBUGLOG && $log->is_debug && $log->debug('Executing action: '.$action->{'type'}.', '.$action->{'data'});
					my @parts = split(/ /, $action->{'data'});
					my $request = $client->execute(\@parts);
					$request->source('PLUGIN_DYNAMICPLAYLISTS4');
				}
			}
		}
	}
	my $offset = $mixInfo{$masterClient}->{'offset'};
	if (!$mixInfo{$masterClient}->{'type'} || $mixInfo{$masterClient}->{'type'} ne $type || (!$addOnly && !$continue)) {
		$offset = 0;
	}

	my $PlaylistTrackCount = Slim::Player::Playlist::count($client);
	my $songIndex = Slim::Player::Source::streamingSongIndex($client);
	my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
	$songsRemaining = 0 if $songsRemaining < 0;

	## Work out how many items need adding
	## If dpl has playlistLimitOption, use it. Otherwise fallback to pref values.
	my $numItems = 0;
	my $maxLimit = 2000; # prevents faulty playlist definitions from accidentally adding complete libraries
	my ($unlimited, $forcedAddDifferentPlaylist);
	my $minNumberUnplayedSongs = $prefs->get('min_number_of_unplayed_tracks');
	my $maxNumberUnplayedTracks = $prefs->get('max_number_of_unplayed_tracks');
	my $playlistLimitOption = $playlist->{'playlistlimitoption'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistLimitOption = '.Data::Dump::dump($playlistLimitOption));

	if (defined($playlistLimitOption)) {
		if ($playlistLimitOption eq 'unlimited') {
			$maxNumberUnplayedTracks = $maxLimit;
			$unlimited = 1;
		} else {
			$playlistLimitOption = isInt($playlist->{'playlistlimitoption'}, 1, $maxLimit, 1, 1);
			$minNumberUnplayedSongs = ($playlistLimitOption && $playlistLimitOption < $prefs->get('min_number_of_unplayed_tracks')) ? $playlistLimitOption : $prefs->get('min_number_of_unplayed_tracks');
			$maxNumberUnplayedTracks = $playlistLimitOption ? $playlistLimitOption : $prefs->get('max_number_of_unplayed_tracks');
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('requested dpl = '.$type);
	main::DEBUGLOG && $log->is_debug && $log->debug('complete client mixinfo dump = '.Data::Dump::dump($mixInfo{$masterClient}));
	if ($mixInfo{$masterClient} && $mixInfo{$masterClient}->{'type'}) { main::DEBUGLOG && $log->is_debug && $log->debug('currently active dpl = '.Data::Dump::dump($mixInfo{$masterClient}->{'type'})); }

	if ($type && $type ne 'disable' && (!$mixInfo{$masterClient} || ($mixInfo{$masterClient} && keys %{$mixInfo{$masterClient}} == 0) || ($mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} ne $type) || $songsRemaining < $minNumberUnplayedSongs)) {
		# Add new tracks if there aren't enough after the current track
		if ((!$addOnly && !$continue) || ($addOnly && $addOnly == 2)) {
			$numItems = $maxNumberUnplayedTracks;
			main::DEBUGLOG && $log->is_debug && $log->debug('Play or DSTM play -- numItems = maxNumberUnplayedTracks = '.$numItems);
		} elsif ($songsRemaining < $minNumberUnplayedSongs) {
			$numItems = $maxNumberUnplayedTracks - $songsRemaining;
			main::DEBUGLOG && $log->is_debug && $log->debug("$songsRemaining unplayed songs remaining < $minNumberUnplayedSongs minimum unplayed songs => adding ".$numItems.' new items');
		} elsif ($addOnly && $forcedAdd) {
			if ($mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} ne $type) {
				$forcedAddDifferentPlaylist = 1;
				$numItems = $maxNumberUnplayedTracks - $songsRemaining;
				$numItems = 1 if $numItems == 0;
				main::DEBUGLOG && $log->is_debug && $log->debug("Adding $numItems new tracks from a dynamic playlist other than the currently active dynamic playlist if add button is pushed (forcedAdd) while songs remaining ($songsRemaining) > minNumberUnplayedSongs ($minNumberUnplayedSongs)");
			} else {
				$numItems = 1;
				main::DEBUGLOG && $log->is_debug && $log->debug("Adding single track of currently active dynamic playlist if add button is pushed (forcedAdd) while songs remaining ($songsRemaining) > minNumberUnplayedSongs ($minNumberUnplayedSongs)");
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("$songsRemaining items remaining > minNumberUnplayedSongs ($minNumberUnplayedSongs). Not adding new tracks");
		}
	}

	my $count = 0;
	$numItems = 0 if $numItems < 0;

	main::DEBUGLOG && $log->is_debug && $log->debug("\nCurrent client playlist before adding new tracks:\ntracks in total: ".Slim::Player::Playlist::count($client)."\nsongs remaining: $songsRemaining\nsongIndex: $songIndex\nMIN. number of unplayed songs to be added: $minNumberUnplayedSongs\nMAX. number of new unplayed tracks to be added: $maxNumberUnplayedTracks\nActual number of tracks to be added (numItems): $numItems");

	if ($numItems) {
		if (!$addOnly || $addOnly == 2) {
			if (Slim::Player::Source::playmode($client) ne 'stop') {
				if (UNIVERSAL::can('Slim::Utils::Alarm', 'getCurrentAlarm')) {
					my $alarm = Slim::Utils::Alarm->getCurrentAlarm($client);
					if (!defined($alarm) || !$alarm->active()) {
						my $request = $client->execute(['stop']);
						$request->source('PLUGIN_DYNAMICPLAYLISTS4');
					}
				} else {
					my $request = $client->execute(['stop']);
					$request->source('PLUGIN_DYNAMICPLAYLISTS4');
				}
			}
			if (!$client->power()) {
				my $request = $client->execute(['power', '1']);
				$request->source('PLUGIN_DYNAMICPLAYLISTS4');
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
				$continue,
				$unlimited,
				$forcedAddDifferentPlaylist);
		main::DEBUGLOG && $log->is_debug && $log->debug('number of added items = '.$count);

		$offset += $count;

		# Display status message(s) if $showTimePerChar > 0
		if ($showTimePerChar > 0) {
			if ($count > 0) {
				# Do a show briefly the first time things are added, or every time a new album/artist/year is added
				if (!$addOnly || ($type && $mixInfo{$masterClient}->{'type'} && $type ne $mixInfo{$masterClient}->{'type'})) {
					# Don't do showBrieflys if visualiser screensavers are running as the display messes up
					my $statusmsg = string($addOnly ? 'ADDING_TO_PLAYLIST' : 'PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING');
					$statusmsg = string('PLUGIN_DYNAMICPLAYLISTS4_DSTM_PLAY_STATUSMSG') if $addOnly == 2;
					if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
						$client->showBriefly({'line' => [$statusmsg,
											 $playlistName]}, getMsgDisplayTime($statusmsg.$playlistName));
					}
					if ($material_enabled) {
						my $materialMsg = $statusmsg.' '.$playlistName;
						Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$materialMsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($materialMsg)]);
					}
				}
			} elsif ($showFeedback) {
					if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
						$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING_FAILED'),
											 string('PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING_FAILED_LONG').' '.$playlistName]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING_FAILED').string('PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING_FAILED_LONG').$playlistName));
					}
					if ($material_enabled) {
						my $materialMsg = string('PLUGIN_DYNAMICPLAYLISTS4_NOW_PLAYING_FAILED_LONG').' '.$playlistName;
						Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$materialMsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($materialMsg)]);
					}
			}
		}
		# Never show random as modified, since it's a living playlist
		$client->currentPlaylistModified(0);
	}

	if ($continue) {
		my $request = $client->execute(['pause', '0']);
		$request->source('PLUGIN_DYNAMICPLAYLISTS4');
	}

	if ($type && $type eq 'disable') {
		main::DEBUGLOG && $log->is_debug && $log->debug('cyclic mode ended');
		# Display status message(s) if $showTimePerChar > 0
		if ($showTimePerChar > 0) {
			# Don't do showBrieflys if visualiser screensavers are running as the display messes up
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
				$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4'), string('PLUGIN_DYNAMICPLAYLISTS4_DISABLED')]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4').string('PLUGIN_DYNAMICPLAYLISTS4_DISABLED')));
			}
			if ($material_enabled) {
				my $materialMsg = string('PLUGIN_DYNAMICPLAYLISTS4_DISABLED');
				Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$materialMsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($materialMsg)]);
			}
		}
		stateStop($masterClient);
		my @players = Slim::Player::Sync::slaves($masterClient);
		push @players, $masterClient;
		foreach my $player (@players) {
			stateStop($player);
		}
		clearPlayListHistory(\@players);
		clearCache(\@players);

	} else {
		if (!$numItems || $numItems == 0 || $count > 0) {
			if (!$addOnly) {
				# Record current mix type and the time it was started.
				# Do this last to prevent menu items changing too soon
				stateNew($masterClient, $type, $playlist);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateNew($player, $type, $playlist);
				}
			}
			if ($mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} eq $type) {
				stateOffset($masterClient, $offset);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateOffset($player, $offset);
				}
			}
		} else {
			unless ($forcedAddDifferentPlaylist && $mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} ne $type) {
				my $stopDPL = 1;

				# add queued dpl
				my $dplQueue = $client->pluginData('dplQueue') || [];
				if (scalar @{$dplQueue} > 0) {
					my $nextDPL = shift @{$dplQueue};
					main::INFOLOG && $log->is_info && $log->info('Adding queued dynamic playlist: '.$nextDPL->{'title'});
					$client->execute(['playlist', 'add', $prefs->get('silencetrackurl')]);
					$client->execute(['playlist', 'add', $nextDPL->{'url'}, $nextDPL->{'title'}]);
				}

				# if repeat ('never stop') is enabled, delete cache/history to add played tracks, otherwise stop
				if (scalar @{$dplQueue} == 0 && $playlist->{'repeat'}) {
					my $repeatCounter = $masterClient->pluginData('repeatcounter') || 1;
					main::INFOLOG && $log->is_info && $log->info('Repeat enabled for current dynamic playlist: '.$playlistName.'. Repeat counter = '.$repeatCounter);
					$repeatCounter++;
					$masterClient->pluginData('repeatcounter' => $repeatCounter);

					my @players = Slim::Player::Sync::slaves($client);
					push @players, $masterClient;

					main::DEBUGLOG && $log->is_debug && $log->debug('Deleting cache/history so we can add tracks that have already been played.');
					clearPlayListHistory(\@players);
					clearCache(\@players);
					foreach my $player (@players) {
						$prefs->client($player)->remove('offset');
					}

					# limit attempts to add new tracks so we don't end up with an infinite loop in case there are no more tracks for a dynamic playlist set to repeat
					main::DEBUGLOG && $log->is_debug && $log->debug('Trying to get new tracks for next repeat of current dynamic playlist: '.$playlistName);
					for (my $i = 0; $i < 2; $i++) {
						my $restartCount = findAndAdd($client, $type, $offset, $numItems, $addOnly, $continue, $unlimited, $forcedAddDifferentPlaylist);
						if ($restartCount > 0) {
							$stopDPL = 0;
							last;
						}
					}
				}
				if ($stopDPL) {
					main::INFOLOG && $log->is_info && $log->info('Stopping current dynamic playlist: '.$playlistName);
					if (defined($stopactions)) {
						for my $action (@{$stopactions}) {
							if (defined($action->{'type'}) && lc($action->{'type'}) eq 'cli' && defined($action->{'data'})) {
								main::DEBUGLOG && $log->is_debug && $log->debug('Executing action: '.$action->{'type'}.', '.$action->{'data'});
								my @parts = split(/ /, $action->{'data'});
								my $request = $client->execute(\@parts);
								$request->source('PLUGIN_DYNAMICPLAYLISTS4');
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
		}
	}
	# if mode is addonly and client playlist trackcount before adding = 0,
	# you probably want to create a one-time static playlist or DSTM seed playlist instead of adding tracks to an existing playlist
	# so let's not keep these tracks in DPL history
	if ($addOnly && ($PlaylistTrackCount == 0)) {
		$masterClient->pluginData('type' => '');
		my @players = Slim::Player::Sync::slaves($masterClient);
		push @players, $masterClient;
		clearPlayListHistory(\@players);
		clearCache(\@players);
	}

	# play DSTM seed list
	if ($addOnly && $addOnly == 2) {
		my $dstmProvider = preferences('plugin.dontstopthemusic')->client($client)->get('provider') || '';
		main::DEBUGLOG && $log->is_debug && $log->debug('dstmProvider = '.$dstmProvider);

		if ($dstmProvider) {
			my $clientPlaylistLength = Slim::Player::Playlist::count($client);
			if ($clientPlaylistLength > 0) {
				stateStop($masterClient);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateStop($player);
				}

				my $dstmStartIndex = $prefs->get('dstmstartindex'); # 0 = last song, 1 = current or first song if no current song
				my $firstSongIndex = (Slim::Player::Source::streamingSongIndex($client) || 0);
				$firstSongIndex = $firstSongIndex + 1 if ($clientPlaylistLength > $firstSongIndex && $firstSongIndex > 0);

				my $startSongIndex = $dstmStartIndex ? $firstSongIndex : $clientPlaylistLength - 1;
				main::DEBUGLOG && $log->is_debug && $log->debug('Adding tracks as DSTM seed list. Start playback of song with playlist index '.$startSongIndex);

				$client->execute(['playlist', 'index', $startSongIndex]);
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Can't start DSTM. No DSTM provider enabled.");
			# Display status message(s) if $showTimePerChar > 0
			if ($showTimePerChar > 0) {
				my $statusmsg = string('PLUGIN_DYNAMICPLAYLISTS4_DSTM_PLAY_FAILED_LONG');
				if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
					$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4_DSTM_PLAY_FAILED'),
										 $statusmsg]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4_DSTM_PLAY_FAILED').$statusmsg));
				}
				if ($material_enabled) {
					Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$statusmsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($statusmsg)]);
				}
			}
		}
	}
}

sub handlePlayOrAdd {
	my ($client, $item, $add) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug(($add ? 'Add' : 'Play')." $item");

	my $masterClient = masterOrSelf($client);

	# Clear any current mix type in case user is restarting an already playing mix
	stateStop($masterClient);
	my @players = Slim::Player::Sync::slaves($client);
	foreach my $player (@players) {
		stateStop($player);
	}

	playRandom($client, $item, $add, 1, 1);
}

sub addParameterValues {
	my ($client, $listRef, $parameter, $parameterValues, $playlist, $limitingParamSelVLID) = @_;

	if (!$parameter->{'type'}) {
		$log->warn('Missing parameter type!');
		return;
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Getting values for '.$parameter->{'name'}.' of type '.$parameter->{'type'});
	my $sql = undef;
	my $unknownString = string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_UNKNOWN');
	if (lc($parameter->{'type'}) eq 'album') {
		if ($limitingParamSelVLID) {
			$sql = "select id, title, substr(titlesort,1,1) from albums join library_album on library_album.album = albums.id and library_album.library = '$limitingParamSelVLID' order by titlesort";
		} else {
			$sql = "select id, title, substr(titlesort,1,1) from albums order by titlesort";
		}
	} elsif (lc($parameter->{'type'}) eq 'artist') {
		if ($limitingParamSelVLID) {
			$sql = "select id, name, substr(namesort,1,1) from contributors join library_contributor on library_contributor.contributor = contributors.id and library_contributor.library = '$limitingParamSelVLID' where namesort is not null order by namesort";
		} else {
			$sql = "select id, name, substr(namesort,1,1) from contributors where namesort is not null order by namesort";
		}
	} elsif (lc($parameter->{'type'}) eq 'genre') {
		if ($limitingParamSelVLID) {
			$sql = "select id, name, substr(namesort,1,1) from genres join library_genre on genres.id = library_genre.genre and library_genre.library = '$limitingParamSelVLID' order by namesort";
		} else {
			$sql = "select id, name, substr(namesort,1,1) from genres order by namesort";
		}
	} elsif (lc($parameter->{'type'}) eq 'year') {
		if ($limitingParamSelVLID) {
			$sql = "select year, case when ifnull(year, 0) > 0 then year else '$unknownString' end from tracks join library_track on library_track.track = tracks.id and library_track.library = '$limitingParamSelVLID' group by year order by year desc";
		} else {
			$sql = "select year, case when ifnull(year, 0) > 0 then year else '$unknownString' end from tracks group by year order by year desc";
		}
	} elsif (lc($parameter->{'type'}) eq 'playlist') {
		if ($limitingParamSelVLID) {
			$sql = "select playlist_track.playlist, tracks.title, substr(tracks.titlesort,1,1) from tracks, playlist_track join library_track on library_track.track = tracks.id and library_track.library = '$limitingParamSelVLID' where tracks.id = playlist_track.playlist and playlist_track.track = tracks.url group by playlist_track.playlist order by titlesort";
		} else {
			$sql = "select playlist_track.playlist, tracks.title, substr(tracks.titlesort,1,1) from tracks, playlist_track where tracks.id = playlist_track.playlist group by playlist_track.playlist order by titlesort";
		}
	} elsif (lc($parameter->{'type'}) eq 'track') {
		$sql = "select tracks.id, case when (albums.title is null or albums.title = '') then '' else albums.title || ' -- ' end || case when tracks.tracknum is null then '' else tracks.tracknum || '. ' end || tracks.title, substr(tracks.titlesort,1,1) from tracks, albums where tracks.album = albums.id and audio = 1 group by tracks.id order by albums.titlesort, albums.disc, tracks.tracknum";
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
							$name = string($name) || $name;
							$listitem{'name'} = $name;
						} else {
							$listitem{'name'} = $id;
						}
						if (defined($sortlink)) {
							$listitem{'sortlink'} = $sortlink;
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
			main::DEBUGLOG && $log->is_debug && $log->debug('virtual library listRef array = '.Data::Dump::dump($listRef));

	} elsif (lc($parameter->{'type'}) eq 'multiplegenres') {
		my $genres = getGenres($client, $limitingParamSelVLID);
		foreach my $genre (getSortedGenres($client, $limitingParamSelVLID)) {
			push @{$listRef}, $genres->{$genre};
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('multiplegenres listRef array = '.Data::Dump::dump($listRef));

	} elsif (lc($parameter->{'type'}) eq 'multipledecades') {
		my $decades = getDecades($client, $limitingParamSelVLID);
		foreach my $decade (getSortedDecades($client, $limitingParamSelVLID)) {
			push @{$listRef}, $decades->{$decade};
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('multipledecades listRef array = '.Data::Dump::dump($listRef));

	} elsif (lc($parameter->{'type'}) eq 'multipleyears') {
		my $years = getYears($client, $limitingParamSelVLID);
		foreach my $year (getSortedYears($client, $limitingParamSelVLID)) {
			push @{$listRef}, $years->{$year};
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('multipleyears listRef array = '.Data::Dump::dump($listRef));

	} elsif (lc($parameter->{'type'}) eq 'multiplestaticplaylists') {
		my $staticPlaylists = getStaticPlaylists($client, $limitingParamSelVLID);
		foreach my $staticPlaylist (getSortedStaticPlaylists($client, $limitingParamSelVLID)) {
			push @{$listRef}, $staticPlaylists->{$staticPlaylist};
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('multiplestaticplaylists listRef array = '.Data::Dump::dump($listRef));

	} elsif (lc($parameter->{'type'}) eq 'custom' || lc($parameter->{'type'}) =~ /^custom(.+)$/) {
		if (defined($parameter->{'definition'}) && lc($parameter->{'definition'}) =~ /^select/) {
			$sql = $parameter->{'definition'};

			# replace placeholders in pre-play user-input if necessary
			my $predfinedParameters = getInternalParameters($client, $playlist, undef, undef);
			$sql = replaceParametersInSQL($sql, $predfinedParameters, 'Playlist');
			main::DEBUGLOG && $log->is_debug && $log->debug('sql = '.$sql);

			for (my $i = 1; $i < $parameter->{'id'}; $i++) {
				my $value = undef;
				if (defined($parameterValues)) {
					$value = $parameterValues->{$i};
				} else {
					my $parameter = $client->modeParam('dynamicplaylist_parameter_'.$i);
					$value = $parameter->{'id'};
				}
				my $parameterid = "\'PlaylistParameter".$i."\'";
				main::DEBUGLOG && $log->is_debug && $log->debug('Replacing '.$parameterid.' with '.$value);
				$sql =~ s/$parameterid/$value/g;
			}
		}
	}

	if (defined($sql)) {
		my $dbh = Slim::Schema->dbh;
		my $paramType = lc($parameter->{'type'});
		main::DEBUGLOG && $log->is_debug && $log->debug('parameter type = '.lc($parameter->{'type'}));
		eval {
			my $sth = $dbh->prepare($sql);
			main::DEBUGLOG && $log->is_debug && $log->debug("Executing value list: $sql");
			$sth->execute() or do {
				$log->error("Error executing: $sql");
				$sql = undef;
			};
			if (defined($sql)) {
				my $id;
				my $name;
				my $sortlink = undef;
				if ($paramType eq 'customdecade' || $paramType eq 'year' || $paramType eq 'customyear') {
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
				main::DEBUGLOG && $log->is_debug && $log->debug('Added '.scalar(@{$listRef}).' items to value list');
			}
			$sth->finish();
		};
		if ($@) {
			$log->error("Database error: $DBI::errstr");
		}
	}
}

sub getTrackIDsForPlaylist {
	my ($client, $playlist, $limit, $offset) = @_;

	my $id = $playlist->{'dynamicplaylistid'};
	my $plugin = $plugins{$id};
	main::DEBUGLOG && $log->is_debug && $log->debug("Calling: $plugin with: id = $id, limit = $limit, offset = $offset");
	my ($result, $tracksCompleteInfo);
	no strict 'refs';
	if (UNIVERSAL::can("$plugin", 'getNextDynamicPlaylistTracks')) {
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
		main::DEBUGLOG && $log->is_debug && $log->debug('parameterHash = '.Data::Dump::dump(\%parameterHash));
		main::DEBUGLOG && $log->is_debug && $log->debug("Calling: $plugin :: getNextDynamicPlaylistTracks");
		($result, $tracksCompleteInfo) = eval {&{"${plugin}::getNextDynamicPlaylistTracks"}($client, $playlist, $limit, $offset, \%parameterHash)};
		if ($@) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Error getting tracks from $plugin: $@");
			return 'error';
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Found '.scalar(@{$result}).(scalar(@{$result}) == 1 ? ' trackID ' : ' trackIDs ').'for playlist \''.$playlist->{'name'}.'\'');
		}
	}

	use strict 'refs';
	#main::DEBUGLOG && $log->is_debug && $log->debug('result = '.Data::Dump::dump($result));
	return $result, $tracksCompleteInfo;
}


### client states ###

sub stateOffset {
	my ($client, $offset) = @_;

	$mixInfo{$client}->{'offset'} = $offset;
	$prefs->client($client)->set('offset', $offset);
}

sub stateNew {
	my ($client, $type, $playlist) = @_;

	Slim::Utils::Timers::killTimers($client, \&findAndAdd);
	$mixInfo{$client}->{'type'} = $type;
	$prefs->client($client)->set('playlist', $type);
	if (defined($playlist->{'parameters'})) {
		$prefs->client($client)->remove('playlist_parameters');
		my %storeParams = ();
		for my $p (keys %{$playlist->{'parameters'}}) {
			if (defined($playlist->{'parameters'}->{$p})) {
				$storeParams{$p} = $playlist->{'parameters'}->{$p}->{'value'};
			}
		}
		$prefs->client($client)->set('playlist_parameters', \%storeParams);
		main::DEBUGLOG && $log->is_debug && $log->debug("stateNew with dpl type '".$type."' and params: ".Data::Dump::dump(\%storeParams));
	} else {
		$prefs->client($client)->remove('playlist_parameters');
		main::DEBUGLOG && $log->is_debug && $log->debug("stateNew with dpl type '".$type."'");
	}
}

sub stateContinue {
	my ($client, $type, $offset, $parameters) = @_;

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
		main::DEBUGLOG && $log->is_debug && $log->debug("stateContinue with dpl type '".$type."'".(defined($offset) ? ", offset ".$offset : "")." and params: ".Data::Dump::dump($parameters));
	} else {
		$prefs->client($client)->remove('playlist_parameters');
		main::DEBUGLOG && $log->is_debug && $log->debug("stateContinue with dpl type '".$type."'".(defined($offset) ? " and offset ".$offset : ""));
	}
}

sub stateStop {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&findAndAdd);
	main::DEBUGLOG && $log->is_debug && $log->debug('stateStop');
	$mixInfo{$client} = undef;
	$prefs->client($client)->remove('playlist');
	$prefs->client($client)->remove('playlist_parameters');
	$prefs->client($client)->remove('offset');
	# delete previous multiple selection
	$client->pluginData('selected_genres' => []);
	$client->pluginData('selected_decades' => []);
	$client->pluginData('temp_decadelist' => {});
	$client->pluginData('selected_years' => []);
	$client->pluginData('selected_staticplaylists' => []);
	my $masterClient = masterOrSelf($client);
	$masterClient->pluginData('type' => '');
	$masterClient->pluginData('repeatcounter' => '');
}


### web pages ###

sub webPages {
	my $class = shift;
	my %pages = (
		'dynamicplaylist_list\.html' => \&handleWebList,
		'dynamicplaylist_mix\.html' => \&handleWebMix,
		'dynamicplaylist_mixparameters\.html' => \&handleWebMixParameters,
		'dynamicplaylist_preselectionmenu\.html' => \&_preselectionMenuWeb,
		'dynamicplaylist_dplqueue\.html' => \&_dplQueueMenuWeb,
		'dynamicplaylist_staticnoparams\.html' => \&_saveAsStaticNoParamsWeb,
	);

	my $value = $htmlTemplate;

	for my $page (keys %pages) {
		Slim::Web::Pages->addPageFunction($page, $pages{$page});
	}

	Slim::Web::Pages->addPageLinks('browse', {'PLUGIN_DYNAMICPLAYLISTS4' => $value});
	Slim::Web::Pages->addPageLinks('icons', {'PLUGIN_DYNAMICPLAYLISTS4' => 'plugins/DynamicPlaylists4/html/images/dpl_icon_svg.png'});
}

sub handleWebList {
	my ($client, $params) = @_;
	my $masterClient = masterOrSelf($client);

	# Pass on the current pref values and now playing info
	initPlayLists($client);
	initPlayListTypes();

	# active dynamic playlist ?
	my $playlist = undef;
	if (defined($client) && defined($mixInfo{$masterClient}) && defined($mixInfo{$masterClient}->{'type'})) {
		$playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
	}
	my $name = undef;
	if ($playlist) {
		$name = $playlist->{'name'};
		$params->{'activeClientMixName'} = $name;
		$params->{'activeClientName'} = $client->name;
		main::DEBUGLOG && $log->is_debug && $log->debug('active dynamic playlist for client "'.$client->name.'" = '.$name);
	}

	if (defined($params->{'group1'})) {
		my $group = unescape($params->{'group1'});
		if ($group =~/\//) {
			my @groups = split(/\//, $group);
			my $i = 1;
			for my $grp (@groups) {
				$params->{'group'.$i} = escape($grp);
				$i++;
			}
		}
	}

	my $dstmProvider = $dstm_enabled ? preferences('plugin.dontstopthemusic')->client($client)->get('provider') : '';
	$params->{'pluginDynamicPlaylists4dstmPlay'} = 'cando' if ($dstm_enabled && $dstmProvider);

	# limit display of preselection & dpl queue to top level
	if (!defined($params->{'group1'})) {
		my $preselectionListArtists = $client->pluginData('cachedArtists') || {};
		my $preselectionListAlbums = $client->pluginData('cachedAlbums') || {};
		main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedArtists' (web) = ".Data::Dump::dump($preselectionListArtists));
		main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedAlbums' (web) = ".Data::Dump::dump($preselectionListAlbums));
		$params->{'pluginDynamicPlaylists4preselectionListArtists'} = 'display' if (keys %{$preselectionListArtists} > 0);
		$params->{'pluginDynamicPlaylists4preselectionListAlbums'} = 'display' if (keys %{$preselectionListAlbums} > 0);

		my $dplQueue = $client->pluginData('dplQueue') || [];
		$params->{'pluginDynamicPlaylists4dplQueue'} = 'display' if (scalar @{$dplQueue} > 0);
	}

	$params->{'paramsdplsaveenabled'} = $prefs->get('paramsdplsaveenabled');
	$params->{'pluginDynamicPlaylists4staticPLsavingEnabled'} = $prefs->get('enablestaticplsaving');
	$params->{'pluginDynamicPlaylists4DPLqueueingEnabled'} = $prefs->get('enabledplqueueing');

	$params->{'pluginDynamicPlaylists4Context'} = getPlayListContext($client, $params, $playListItems, 1);
	$params->{'pluginDynamicPlaylists4Groups'} = getPlayListGroupsForContext($client, $params, $playListItems, 1);
	$params->{'pluginDynamicPlaylists4PlayLists'} = getPlayListsForContext($client, $params, $playListItems, 1, $params->{'playlisttype'});

	return Slim::Web::HTTP::filltemplatefile($htmlTemplate, $params);
}

sub handleWebMix {
	my ($client, $params) = @_;
	if (defined $client && $params->{'type'}) {
		if ($params->{'type'} && $params->{'type'} eq 'disable') {
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
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering handleWebMixParameters');
	my $parameterId = 1;
	my @parameters = ();
	my $playlist = getPlayList($client, $params->{'type'});
	my $playlistParams = $playlist->{'parameters'};
	$params->{'currentgroup'} = escape($params->{'group'});
	main::DEBUGLOG && $log->is_debug && $log->debug('currentGroup = '.Data::Dump::dump($params->{'currentgroup'}));

	my @groupPath = ();
	my @groupResult = ();
	$params->{'pluginDynamicPlaylists4Groups'} = getPlayListGroups(\@groupPath, $playListItems, \@groupResult);
	main::DEBUGLOG && $log->is_debug && $log->debug('pluginDynamicPlaylists4Groups = '.Data::Dump::dump($params->{'pluginDynamicPlaylists4Groups'}));

	my $i = 1;
	while (defined($params->{'dynamicplaylist_parameter_'.$i})) {
		$parameterId = $parameterId + 1;
		my $parameter = $playlist->{'parameters'}->{$i};
		my %value;
		if ($parameter && $parameter->{'type'} && $parameter->{'type'} eq 'multipledecades') {

			# add years to decades
			my @decadeValues = split(/,/, $params->{'dynamicplaylist_parameter_'.$i});
			my @yearsArray;

			foreach my $decade (@decadeValues) {
				push @yearsArray, $decade;
				unless ($decade == 0) {
					for (1..9) {
						push @yearsArray, $decade + $_;
					}
				}
			}
			my $multipleDecadesString = join (',', @yearsArray);
			main::DEBUGLOG && $log->is_debug && $log->debug('multiple decades string with years (web) = '.Data::Dump::dump($multipleDecadesString));
			%value = (
				'id' => $multipleDecadesString
			);
		} else {
			%value = (
				'id' => $params->{'dynamicplaylist_parameter_'.$i}
			);
		}

		$client->modeParam('dynamicplaylist_parameter_'.$i, \%value);
		main::DEBUGLOG && $log->is_debug && $log->debug("Storing parameter $i = ".$value{'id'});
		$i++;
	}

	# get VLID to limit displayed parameters options to those in VL if necessary
	my $limitingParamSelVLID = checkForLimitingVL($client, \@parameters, $playlist);

	if (defined($playlist->{'parameters'}->{$parameterId})) {
		my (%selectedGenres, %selectedDecades, %selectedYears, %selectedStaticPlaylists) = ();

		for(my $i = 1; $i < $parameterId; $i++) {
			my @parameterValues = ();
			my $parameter = $playlist->{'parameters'}->{$i};

			addParameterValues($client, \@parameterValues, $parameter, undef, $playlist, $limitingParamSelVLID);

			my %webParameter = (
				'parameter' => $parameter,
				'values' => \@parameterValues,
				'value' => $params->{'dynamicplaylist_parameter_'.$i}
			);

			if ($parameter->{'type'} && ($parameter->{'type'} eq 'multiplegenres' || $parameter->{'type'} eq 'multipledecades' || $parameter->{'type'} eq 'multipleyears' || $parameter->{'type'} eq 'multiplestaticplaylists')) {
				if ($parameter->{'type'} eq 'multiplegenres') {
					my @selectedGenresArray = split (',', $params->{'dynamicplaylist_parameter_'.$i});
					%selectedGenres = map { $_ => 1 } @selectedGenresArray;
				}
				if ($parameter->{'type'} eq 'multipledecades') {
					my @selectedDecadesArray = split (',', $params->{'dynamicplaylist_parameter_'.$i});
					%selectedDecades = map { $_ => 1 } @selectedDecadesArray;
				}
				if ($parameter->{'type'} eq 'multipleyears') {
					my @selectedYearsArray = split (',', $params->{'dynamicplaylist_parameter_'.$i});
					%selectedYears = map { $_ => 1 } @selectedYearsArray;
				}
				if ($parameter->{'type'} eq 'multiplestaticplaylists') {
					my @selectedStaticPlaylistsArray = split (',', $params->{'dynamicplaylist_parameter_'.$i});
					%selectedStaticPlaylists = map { $_ => 1 } @selectedStaticPlaylistsArray;
				}
			}
			push @parameters, \%webParameter;
		}

		# get VLID to limit displayed parameters options to those in VL if necessary
		$limitingParamSelVLID = checkForLimitingVL($client, \@parameters, $playlist);

		my $parameter = $playlist->{'parameters'}->{$parameterId};
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting values for: '.$parameter->{'name'});
		my @parameterValues = ();
		addParameterValues($client, \@parameterValues, $parameter, undef, $playlist, $limitingParamSelVLID);
		my %currentParameter = (
			'parameter' => $parameter,
			'values' => \@parameterValues
		);
		push @parameters, \%currentParameter;

		if ($parameter->{'type'} && ($parameter->{'type'} eq 'multiplegenres' || $parameter->{'type'} eq 'multipledecades' || $parameter->{'type'} eq 'multipleyears' || $parameter->{'type'} eq 'multiplestaticplaylists')) {
			$params->{'currentparam'} = $parameter->{'type'};
		}

		# multiple genres list
		if (defined (first {$_->{'type'} eq 'multiplegenres'} values %{$playlistParams})) {
			my $genrelist = getGenres($client, $limitingParamSelVLID);
			if (keys %selectedGenres > 0) {
				foreach my $genre (keys %{$genrelist}) {
					my $id = $genrelist->{$genre}->{'id'};
					if ($selectedGenres{$id}) {
						$genrelist->{$genre}->{'selected'} = 1;
					}
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug('genre list = '.Data::Dump::dump($genrelist));
			$params->{'genrelist'} = $genrelist;

			my $genrelistsorted = [getSortedGenres($client, $limitingParamSelVLID)];
			main::DEBUGLOG && $log->is_debug && $log->debug('genrelistsorted (just names) = '.Data::Dump::dump($genrelistsorted));
			$params->{'genrelistsorted'} = $genrelistsorted;
		}

		# multiple decades list
		if (defined (first {$_->{'type'} eq 'multipledecades'} values %{$playlistParams})) {
			my $decadelist = getDecades($client, $limitingParamSelVLID);
			if (keys %selectedDecades > 0) {
				foreach my $decade (keys %{$decadelist}) {
					my $id = $decadelist->{$decade}->{'id'};
					if ($selectedDecades{$id}) {
						$decadelist->{$decade}->{'selected'} = 1;
					}
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug('decade list = '.Data::Dump::dump($decadelist));
			$params->{'decadelist'} = $decadelist;

			my $decadelistsorted = [getSortedDecades($client, $limitingParamSelVLID)];
			main::DEBUGLOG && $log->is_debug && $log->debug('decadelistsorted = '.Data::Dump::dump($decadelistsorted));
			$params->{'decadelistsorted'} = $decadelistsorted;
		}

		# multiple years list
		if (defined (first {$_->{'type'} eq 'multipleyears'} values %{$playlistParams})) {
			my $yearlist = getYears($client, $limitingParamSelVLID);
			if (keys %selectedYears > 0) {
				foreach my $year (keys %{$yearlist}) {
					my $id = $yearlist->{$year}->{'id'};
					if ($selectedYears{$id}) {
						$yearlist->{$year}->{'selected'} = 1;
					}
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug('year list = '.Data::Dump::dump($yearlist));
			$params->{'yearlist'} = $yearlist;

			my $yearlistsorted = [getSortedYears($client, $limitingParamSelVLID)];
			main::DEBUGLOG && $log->is_debug && $log->debug('yearlistsorted = '.Data::Dump::dump($yearlistsorted));
			$params->{'yearlistsorted'} = $yearlistsorted;
		}

		# multiple static playlists list
		if (defined (first {$_->{'type'} eq 'multiplestaticplaylists'} values %{$playlistParams})) {
			my $staticplaylistlist = getStaticPlaylists($client, $limitingParamSelVLID);
			if (keys %selectedStaticPlaylists > 0) {
				foreach my $staticPlaylist (keys %{$staticplaylistlist}) {
					my $id = $staticplaylistlist->{$staticPlaylist}->{'id'};
					if ($selectedStaticPlaylists{$id}) {
						$staticplaylistlist->{$staticPlaylist}->{'selected'} = 1;
					}
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug('static playlist list = '.Data::Dump::dump($staticplaylistlist));
			$params->{'staticplaylistlist'} = $staticplaylistlist;

			my $staticplaylistlistsorted = [getSortedStaticPlaylists($client, $limitingParamSelVLID)];
			main::DEBUGLOG && $log->is_debug && $log->debug('staticplaylistlistsorted (just names) = '.Data::Dump::dump($staticplaylistlistsorted));
			$params->{'staticplaylistlistsorted'} = $staticplaylistlistsorted;
		}

		$params->{'pluginDynamicPlaylists4Playlist'} = $playlist;
		$params->{'pluginDynamicPlaylists4PlaylistId'} = $params->{'type'};
		$params->{'pluginDynamicPlaylists4AddOnly'} = $params->{'addOnly'};
		$params->{'pluginDynamicPlaylists4MixParameters'} = \@parameters;
		my $currentPlaylistId = getCurrentPlayList($client);
		if (defined($currentPlaylistId)) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Setting current playlist id to '.$currentPlaylistId);
			my $currentPlaylist = getPlayList($client, $currentPlaylistId);
			if (defined($currentPlaylist)) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Setting current playlist to '.$currentPlaylist->{'name'});
				$params->{'pluginDynamicPlaylists4NowPlaying'} = $currentPlaylist->{'name'};
			}
		}
		if (!exists $playlist->{'parameters'}->{($parameterId + 1)}) {
			$params->{'lastparameter'} = 'islastparam';
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting handleWebMixParameters');
		return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlaylists4/dynamicplaylist_mixparameters.html', $params);
	} else {

		# save as favorite
		if ($params->{'addOnly'} == 99) {
			my $title = $params->{'dpl_customfavtitle'} || $playlist->{'name'};
			$title = Slim::Utils::Misc::cleanupFilename($title);
			my $url = $params->{'dpl_favaddonly'} ? ('dynamicplaylistaddonly://'.$playlist->{'dynamicplaylistid'}.'?') : ('dynamicplaylist://'.$playlist->{'dynamicplaylistid'}.'?');
			for (my $i = 1; $i < $parameterId; $i++) {
				$url .= 'p'.$i.'='.$client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
				$url .= '&' unless $i == $parameterId - 1;
			}
			my $isFav = Slim::Utils::Favorites->new($client)->findUrl($url);
			if ($isFav) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Not adding dynamic playlist to LMS favorites. Is already favorite.')
			} else {
				main::DEBUGLOG && $log->is_debug && $log->debug('Saving this url to LMS favorites: '.$url);
				$client->execute(['favorites', 'add', 'url:'.$url, 'title:'.$title, 'type:audio']);
			}

		# queue dynamic playlist
		} elsif ($params->{'addOnly'} == 88) {
			# build url
			my $url = 'dynamicplaylist://'.$playlist->{'dynamicplaylistid'}.'?';
			for (my $i = 1; $i < $parameterId; $i++) {
				$url .= 'p'.$i.'='.$client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
				$url .= '&' unless $i == $parameterId - 1;
			}
			_queuePlaylist($client, $url, $playlist);

		# save as static playlist
		} elsif ($params->{'addOnly'} == 77) {
			my $staticPLname = $params->{'dpl_customstaticplname'} || $playlist->{'name'};
			$staticPLname = Slim::Utils::Misc::cleanupFilename($staticPLname);

			my $staticPLmaxTrackLimit = $params->{'dpl_customstaticplmaxtracklimit'} || 200;
			$staticPLmaxTrackLimit = 4000 if $staticPLmaxTrackLimit > 4000;
			$staticPLmaxTrackLimit = 100 if $staticPLmaxTrackLimit < 100;

			my $sortOrder = $params->{'dpl_customstaticplsortorder'} || 1;

			for (my $i = 1; $i < $parameterId; $i++) {
				$playlist->{'parameters'}->{$i}->{'value'} = $client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
			}
			saveAsStaticPlaylist($client, $params->{'type'}, $staticPLmaxTrackLimit, $staticPLname, $sortOrder);

		} else {
			for (my $i = 1; $i < $parameterId; $i++) {
				$playlist->{'parameters'}->{$i}->{'value'} = $client->modeParam('dynamicplaylist_parameter_'.$i)->{'id'};
			}

			unless ($params->{'addOnly'} == 1) {
				my $masterClient = masterOrSelf($client);

				# Clear any current mix type in case user is restarting an already playing mix
				stateStop($masterClient);
				my @players = Slim::Player::Sync::slaves($client);
				foreach my $player (@players) {
					stateStop($player);
				}
			}

			playRandom($client, $params->{'type'}, $params->{'addOnly'}, 1, 1);
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting handleWebMixParameters');
		return handleWebList($client, $params);
	}
}

sub getPlayListContext {
	my ($client, $params, $currentItems, $level) = @_;
	my @result = ();
	my $displayname;
	main::DEBUGLOG && $log->is_debug && $log->debug("Get playlist context for level: $level");

	if (defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting group: '.$group);
		my $item = $currentItems->{'dynamicplaylistgroup_'.$group};
		if (defined($item) && !defined($item->{'playlist'})) {
			my $currentUrl = '&group'.$level.'='.escape($group);
			if (($level == 1) && ($categorylangstrings{$group})) {
				$displayname = $categorylangstrings{$group};
			} else {
				$displayname = $group;
			}
			my %resultItem = (
				'url' => $currentUrl,
				'name' => $group,
				'displayname' => $displayname,
				'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'},
				'contextname' => escape($group),
			);
			main::DEBUGLOG && $log->is_debug && $log->debug('Adding context: '.$group);
			push @result, \%resultItem;

			if (defined($item->{'childs'})) {
				my $childResult = getPlayListContext($client, $params, $item->{'childs'}, $level + 1);
				for my $child (@{$childResult}) {
					$child->{'url'} = $currentUrl.$child->{'url'};
					main::DEBUGLOG && $log->is_debug && $log->debug('Adding child context: '.$child->{'name'});
					push @result, $child;
				}
			}
		}
	}
	return \@result;
}

sub getPlayListGroupsForContext {
	my ($client, $params, $currentItems, $level) = @_;
	my @result = ();

	if ($prefs->get('flatlist') || $params->{'flatlist'}) {
		return \@result;
	}

	if (defined($params->{'group'.$level})) {
		my $group = unescape($params->{'group'.$level});
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting group: '.$group);
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
				my ($sortname, $displayname);
				if (($level == 1) && ($customsortnames{$item->{'name'}})) {
					$sortname = $customsortnames{$item->{'name'}};
				} else {
					$sortname = $item->{'name'};
				}
				if (($level == 1) && ($categorylangstrings{$item->{'name'}})) {
					$displayname = $categorylangstrings{$item->{'name'}};
				} else {
					$displayname = $item->{'name'};
				}
				my %resultItem = (
					'url' => $currentUrl,
					'name' => $item->{'name'},
					'displayname' => $displayname,
					'groupsortname' => $sortname,
					'dynamicplaylistenabled' => $item->{'dynamicplaylistenabled'}
				);
				main::DEBUGLOG && $log->is_debug && $log->debug('Adding group: '.$itemKey);
				push @result, \%resultItem;
			}
		}
	}
	@result = sort {lc($a->{'groupsortname'}) cmp lc($b->{'groupsortname'})} @result;
	return \@result;
}

sub getPlayListsForContext {
	my ($client, $params, $currentItems, $level, $playlisttype) = @_;
	my @result = ();

	my $isContextMenu = $params->{'iscontextmenu'} || 0;
	main::DEBUGLOG && $log->is_debug && $log->debug('params iscontextmenu = '.$isContextMenu.' -- level = '.Data::Dump::dump($level));
	main::DEBUGLOG && $log->is_debug && $log->debug('playlisttype = '.Data::Dump::dump($playlisttype));
	main::DEBUGLOG && $log->is_debug && $log->debug('params flatlist = '.Data::Dump::dump($params->{'flatlist'}));

	if ($prefs->get('flatlist') || $params->{'flatlist'}) {
		foreach my $itemKey (keys %{$playLists}) {
			my $playlist = $playLists->{$itemKey};
			if (!defined($playlisttype) || (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype)))) {
				my $dplMenuListType = $playlist->{'menulisttype'} || '';
				unless ($isContextMenu == 1 && $dplMenuListType ne 'contextmenu') {
					main::DEBUGLOG && $log->is_debug && $log->debug('Adding playlist: '.$itemKey);
					push @result, $playlist;
				}
			}
		}
	} else {
		if (defined($params->{'group'.$level})) {
			my $group = unescape($params->{'group'.$level});
			main::DEBUGLOG && $log->is_debug && $log->debug('Getting group: '.$group);
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
						my $dplMenuListType = $playlist->{'menulisttype'} || '';
						unless ($isContextMenu == 1 && $dplMenuListType ne 'contextmenu') {
							main::DEBUGLOG && $log->is_debug && $log->debug('Adding playlist: '.$itemKey);
							push @result, $playlist;
						}
					}
				}
			}
		}
	}
	@result = sort {lc($a->{'playlistsortname'}) cmp lc($b->{'playlistsortname'})} @result;
	#main::INFOLOG && $log->is_info && $log->info('result = '.Data::Dump::dump(\@result));
	return \@result;
}

sub getPlayListGroups {
	my ($path, $items, $result) = @_;

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

			my ($sortname, $displayname);
			if (($groupName eq '') && ($customsortnames{$item->{'name'}})) {
				$sortname = $customsortnames{$item->{'name'}}.'/';
			} else {
				if (starts_with($groupName, 'Static Playlists/') == 0) {
					my $groupSortName = $groupName;
					$groupSortName =~ s/Static Playlists/00009_static_LMS_playlists/g;
					$sortname = $groupSortName.$item->{'name'}.'/';
				} else {
					$sortname = $groupName.$item->{'name'}.'/';
				}
			}
			if (($groupName eq '') && ($categorylangstrings{$item->{'name'}})) {
				$displayname = $categorylangstrings{$item->{'name'}};
			} else {
				if (starts_with($groupName, 'Static Playlists/') == 0) {
					my $statPL_localized = string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_WEBLIST_STATICPLAYLISTS');
					$groupName =~ s/Static Playlists/$statPL_localized/g;
				}
				$displayname = $groupName.$item->{'name'};
			}

			my %resultItem = (
				'id' => escape($groupId.'_'.$item->{'name'}),
				'url' => '&group1='.escape($item->{'name'}),
				'name' => $groupName.$item->{'name'}.'/',
				'displayname' => $displayname,
				'groupsortname' => $sortname,
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
		my @temp = sort {lc($a->{'groupsortname'}) cmp lc($b->{'groupsortname'})} @{$result};
		$result = \@temp;
		main::DEBUGLOG && $log->is_debug && $log->debug('Got sorted array: '.$result);
	}
	return $result;
}

sub getCurrentPlayList {
	my $client = shift;
	my $masterClient = masterOrSelf($client);

	if (defined($client) && $mixInfo{$masterClient}) {
		return $mixInfo{$masterClient}->{'type'};
	}
	return undef;
}

sub savePlayListGroups {
	my ($items, $params, $path) = @_;

	foreach my $itemKey (keys %{$items}) {
		my $item = $items->{$itemKey};
		if (!defined($item->{'playlist'}) && defined($item->{'name'})) {
			my $groupid = escape($path).'_'.escape($item->{'name'});
			my $playlistid = 'playlist_'.$groupid;
			if ($params->{$playlistid}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Saving: playlist_group_'.$groupid.'_enabled = 1');
				$prefs->set('playlist_group_'.$groupid.'_enabled', 1);
			} else {
				main::DEBUGLOG && $log->is_debug && $log->debug('Saving: playlist_group_'.$groupid.'_enabled = 0');
				$prefs->set('playlist_group_'.$groupid.'_enabled', 0);
			}
			if (defined($item->{'childs'})) {
				savePlayListGroups($item->{'childs'}, $params, $path.'_'.$item->{'name'});
			}
		}
	}
}


### jive ###

sub registerJiveMenu {
	my ($class, $client) = @_;

	my @menuItems = (
		{
			text => Slim::Utils::Strings::string('PLUGIN_DYNAMICPLAYLISTS4'),
			weight => 78,
			id => 'dynamicplaylists4',
			menuIcon => 'plugins/DynamicPlaylists4/html/images/dpl_icon_svg.png',
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

sub cliJiveHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliJiveHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['browsejive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveHandler');
		return;
	}

	initPlayLists($client);
	initPlayListTypes();

	my $params = $request->getParamsCopy();

	for my $k (keys %{$params}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Executing CLI browsejive command');

	# delete previous multiple selection
	$client->pluginData('selected_genres' => []);
	$client->pluginData('selected_decades' => []);
	$client->pluginData('temp_decadelist' => {});
	$client->pluginData('selected_years' => []);
	$client->pluginData('selected_staticplaylists' => []);

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

	my $cnt = 0;

	# get menu level and check if active dynamic playlist
	my $masterClient = masterOrSelf($client);
	my $playlist = undef;
	if (defined($client) && defined($mixInfo{$masterClient}) && defined($mixInfo{$masterClient}->{'type'})) {
		$playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});
	}

	# display active dynamic playlist
	if ($playlist && $nextGroup == 1) {
		my $text = $client->string('PLUGIN_DYNAMICPLAYLISTS4_ACTIVEDPL').' '.$playlist->{'name'};
		main::DEBUGLOG && $log->is_debug && $log->debug('active dynamic playlist for client "'.$client->name.'" = '.$playlist->{'name'});
		$request->addResultLoop('item_loop', $cnt, 'text', $text);
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'action', 'none');
		$cnt++;

		# add option to stop adding songs
		my %itemParams = (
			'playlistid' => 'disable',
		);
		my $stopAddingAction = {
			'go' => {
				'player' => 0,
				'cmd' => ['dynamicplaylist', 'playlist', 'stop'],
				'params' => \%itemParams,
				'itemsParams' => 'params',
			},
		};
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'refresh');
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
		$request->addResultLoop('item_loop', $cnt, 'actions', $stopAddingAction);
		$request->addResultLoop('item_loop', $cnt, 'text', '* '.$client->string('PLUGIN_DYNAMICPLAYLISTS4_DISABLE').' *');
		$cnt++;
	}

	# currently preselected artists/albums list link
	if ($nextGroup == 1) {
		my $preselectionListArtists = $client->pluginData('cachedArtists') || {};
		my $preselectionListAlbums = $client->pluginData('cachedAlbums') || {};
		main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedArtists' (jive) = ".Data::Dump::dump($preselectionListArtists));
		main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedAlbums' (jive) = ".Data::Dump::dump($preselectionListAlbums));

		if (keys %{$preselectionListArtists} > 0) {
			my $preselActions = {
				'go' => {
					player => 0,
					cmd => ['dynamicplaylist', 'preselect'],
					params => {
						'objecttype' => 'artist',
					},
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $preselActions);
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_CACHED_ARTISTS_LIST'));
			$cnt++;
		}
		if (keys %{$preselectionListAlbums} > 0) {
			my $preselActions = {
				'go' => {
					player => 0,
					cmd => ['dynamicplaylist', 'preselect'],
					params => {
						'objecttype' => 'album',
					},
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $preselActions);
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_CACHED_ALBUMS_LIST'));
			$cnt++;
		}
	}

	# currently queued dpl list
	if ($prefs->get('enabledplqueueing') && $nextGroup == 1) {
		my $dplQueue = $client->pluginData('dplQueue') || [];
		main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'dplQueue' (jive) = ".Data::Dump::dump($dplQueue));
		if (scalar @{$dplQueue} > 0) {
			my $queueActions = {
				'go' => {
					player => 0,
					cmd => ['dynamicplaylist', 'queuelist'],
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $queueActions);
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_DPLQUEUE_CURRENTLYQUEUED'));
			$cnt++;
		}
	}

	# dpl groups
	foreach my $item (@{$menuGroupResult}) {
		if ($item->{'dynamicplaylistenabled'}) {
			my $name;
			my $id;
			if ($item->{'displayname'}) {
				$name = $item->{'displayname'};
			} else {
				$name = $item->{'name'};
			}
			$id = escape($item->{'name'});

			my %itemParams = ();
			foreach my $p (keys %baseParams) {
				if ($p =~ /^group/) {
					$itemParams{$p} = $baseParams{$p}
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
		if ($item->{'dynamicplaylistenabled'} && (!defined($item->{'menulisttype'}) || $item->{'menulisttype'} ne 'contextmenu')) {
			my $name = $item->{'name'};
			my $id = $item->{'dynamicplaylistid'};
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
					'go' => {
						'cmd' => ['dynamicplaylist', 'actionsmenu'],
						'params' => \%itemParams,
						'itemsParams' => 'params',
					},
					'play' => undef,
					'add' => undef,
				};
				$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
				$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			}
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $cnt, 'text', $name);
			$cnt++;
		}
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveHandler');
}

sub cliJivePlaylistParametersHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliJivePlaylistParametersHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['jiveplaylistparameters']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	my $playlistId = $request->getParam('playlistid');
	if (!defined($playlistId)) {
		$log->warn('playlistid parameter required');
		$request->setStatusBadParams();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}
	my $playlist = getPlayList($client, $playlistId);
	if (!defined($playlist)) {
		$log->warn("Playlist $playlistId can't be found");
		$request->setStatusBadParams();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}

	my $params = $request->getParamsCopy();

	my %baseParams = (
		'playlistid' => $playlistId,
	);
	for my $k (keys %{$params}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			$baseParams{$k} = $params->{$k};
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
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
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
		return;
	}

	my $start = $request->getParam('_start') || 0;
	main::DEBUGLOG && $log->is_debug && $log->debug('Executing CLI jiveplaylistparameters command');

	my $parameter= $playlist->{'parameters'}->{$nextParameterId};
	main::DEBUGLOG && $log->is_debug && $log->debug('parameter = '.Data::Dump::dump($parameter));
	my @listRef = ();

	# get VLID to limit displayed parameters options to those in VL if necessary
	my $limitingParamSelVLID = checkForLimitingVL($client, $parameters, $playlist, 1);

	if ($parameter->{'type'} && ($parameter->{'type'} eq 'multiplegenres' || $parameter->{'type'} eq 'multipledecades' || $parameter->{'type'} eq 'multipleyears' || $parameter->{'type'} eq 'multiplestaticplaylists')) {
		addParameterValues($client, \@listRef, $parameter, $parameters, $playlist, $limitingParamSelVLID);
		my $nextParamMultipleSelectionString;

		## first: add three items: next param/actionsmenu, select all, select none
		my $cnt = 0;

		# next param or actionsmenu
		if ($parameter->{'type'} && $parameter->{'type'} eq 'multipledecades') {
			# add years to decades
			$nextParamMultipleSelectionString = getMultipleSelectionString($client, $parameter->{'type'}, 1);
			main::DEBUGLOG && $log->is_debug && $log->debug('nextParamMultipleSelectionString (decades) = '.Data::Dump::dump($nextParamMultipleSelectionString));
		} else {
			$nextParamMultipleSelectionString = getMultipleSelectionString($client, $parameter->{'type'});
			main::DEBUGLOG && $log->is_debug && $log->debug('nextParamMultipleSelectionString = '.Data::Dump::dump($nextParamMultipleSelectionString));
		}

		$baseParams{'dynamicplaylist_parameter_'.$nextParameterId} = $nextParamMultipleSelectionString;

		my $actions_continue;
		if (exists $playlist->{'parameters'}->{($nextParameterId + 1)}) {
			$actions_continue = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'jiveplaylistparameters'],
					'params' => \%baseParams,
					'itemsParams' => 'params',
				},
			};
		} else {
			$actions_continue = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'actionsmenu'],
					'params' => \%baseParams,
					'itemsParams' => 'params',
				},
			};
		}

		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_NEXT'));
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_continue);
		$cnt++;

		# select all
		my $actions_selectall = {
			'go' => {
				'player' => 0,
				'cmd' => ['dynamicplaylistmultipleall', $parameter->{'type'}, 1],
			},
		};
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_selectall);
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'refresh');
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_SELECT_ALL'));
		$cnt++;

		# select none
		my $actions_selectnone = {
			'go' => {
				'player' => 0,
				'cmd' => ['dynamicplaylistmultipleall', $parameter->{'type'}, 0],
			},
		};
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_selectnone);
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'refresh');
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_SELECT_NONE'));
		$cnt++;


		## create multiple selection items
		my $count = scalar(@listRef);
		my $itemsPerResponse = $request->getParam('_itemsPerResponse') || $count;
		my $offsetCount = 3;

		# Material does not display checkboxes in MyMusic. Use unicode character name prefix instead.
		my $materialCaller = 1 if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->source) && $request->source eq 'JSONRPC');
		my $iPengCaller = 1 if (defined($request->source) && $request->source =~ /iPeng/);
		my $checkboxSelected = $iPengCaller ? HTML::Entities::decode_entities('&#9632;&#xa0;&#xa0;') : HTML::Entities::decode_entities('&#9724;&#xa0;&#xa0;');
		my $checkboxEmpty = $iPengCaller ? HTML::Entities::decode_entities('&#9633;&#xa0;&#xa0;') : HTML::Entities::decode_entities('&#9723;&#xa0;&#xa0;');

		foreach my $item (@listRef) {
			if ($cnt >= $start && $offsetCount < $itemsPerResponse) {
				my $actions;
				if ($materialCaller || $iPengCaller) {
					$actions = {
								go => {
									player => 0,
									cmd => ['dynamicplaylistmultipletoggle', $parameter->{'type'}, $item->{'id'}, $item->{'selected'} ? 0 : 1],
								},
							};
					$request->addResultLoop('item_loop', $offsetCount, 'text', ($item->{'selected'} ? $checkboxSelected : $checkboxEmpty).$item->{'name'});
				} else {
					$actions = {
								on => {
									player => 0,
									cmd => ['dynamicplaylistmultipletoggle', $parameter->{'type'}, $item->{'id'}, 1],
								},
								off => {
									player => 0,
									cmd => ['dynamicplaylistmultipletoggle', $parameter->{'type'}, $item->{'id'}, 0],
								}
							};
					$request->addResultLoop('item_loop', $offsetCount, 'text', $item->{'name'});
					$request->addResultLoop('item_loop', $offsetCount, 'checkbox', $item->{'selected'} ? 1 : 0);
				}

				$request->addResultLoop('item_loop', $offsetCount, 'actions', $actions);
				$request->addResultLoop('item_loop', $offsetCount, 'type', 'redirect');
				$request->addResultLoop('item_loop', $offsetCount, 'nextWindow', 'refresh');
				$offsetCount++;
			}
			$cnt++;
		}

		# Material always displays last selection as window title. Add correct window title as textarea
		if ($materialCaller || $iPengCaller) {
			$request->addResult('window', {textarea => $parameter->{'name'}});
		} else {
			$request->addResult('window', {text => $parameter->{'name'}});
		}

		$request->addResult('offset', $start);
		$request->addResult('count', $cnt);

	} else {
		addParameterValues($client, \@listRef, $parameter, $parameters, $playlist, $limitingParamSelVLID);

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
			main::DEBUGLOG && $log->is_debug && $log->debug('ready to play, no more params to add');
			main::DEBUGLOG && $log->is_debug && $log->debug('baseParams = '.Data::Dump::dump(\%baseParams));
			my $baseMenu = {
				'actions' => {
					'go' => {
						'cmd' => ['dynamicplaylist', 'actionsmenu'],
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
					$request->addResultLoop('item_loop', $offsetCount, 'type', 'redirect');
				}
				$offsetCount++;
			}
			$cnt++;
		}
		if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->{'_source'}) && $request->{'_source'} eq 'JSONRPC') {
			$request->addResult('window', {textarea => $parameter->{'name'}});
		} else {
			$request->addResult('window', {text => $parameter->{'name'}});
		}
		$request->addResult('offset', $start);
		$request->addResult('count', $cnt);
	}

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJivePlaylistParametersHandler');
}

sub cliContextMenuJiveHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliContextMenuJiveHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['contextmenujive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContextMenuJiveHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContextMenuJiveHandler');
		return;
	}

	if (!$playListTypes || $rescan) {
		initPlayLists($client);
	}
	my $params = $request->getParamsCopy();
	for my $k (keys %{$params}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
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
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Executing CLI mixjive command');

	my $useContextMenu = $request->getParam('useContextMenu') || 0;
	main::DEBUGLOG && $log->is_debug && $log->debug('useContextMenu = '.$useContextMenu);
	my $cnt = 0;
	if (defined($playlisttype)) {
		foreach my $flatItem (sort keys %{$playLists}) {
			my $playlist = $playLists->{$flatItem};
			my $dplMenuListType = $playlist->{'menulisttype'} || '';
			main::DEBUGLOG && $log->is_debug && $log->debug('menulisttype for playlist "'.$playlist->{'dynamicplaylistid'}.' = '.$dplMenuListType);
			next if ($useContextMenu == 1 && $dplMenuListType ne 'contextmenu');
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
							'go' => {
								'cmd' => ['dynamicplaylist', 'actionsmenu'],
								'params' => \%itemParams,
								'itemsParams' => 'params',
							},
						};
						$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
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
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContextMenuJiveHandler');
}

sub _cliJiveActionsMenuHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliJiveActionsMenuHandler');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['actionsmenu']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveActionsMenuHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveActionsMenuHandler');
		return;
	}

	if (!$playLists || $rescan) {
		initPlayLists($client);
	}
	my $params = $request->getParamsCopy();
	main::DEBUGLOG && $log->is_debug && $log->debug('params = '.Data::Dump::dump($params));

	$request->addResult('window', {
		menustyle => 'album',
		text => string('PLUGIN_DYNAMICPLAYLISTS4_PLAY_OR_ADD'),
	});
	my $cnt = 0;

	## Play
	my $actions_play = {
		'do' => {
			'cmd' => ['dynamicplaylist', 'playlist', 'play'],
			'params' => $params,
			'itemsParams' => 'params',
		},
		'play' => {
			'cmd' => ['dynamicplaylist', 'playlist', 'play'],
			'params' => $params,
			'itemsParams' => 'params',
		},
	};
	$request->addResultLoop('item_loop', $cnt, 'actions', $actions_play);
	$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
	$request->addResultLoop('item_loop', $cnt, 'params', $params);
	$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'nowPlaying');
	$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_PLAY'));
	$cnt++;

	## Add
	my $actions_add = {
		'do' => {
			'cmd' => ['dynamicplaylist', 'playlist', 'add'],
			'params' => $params,
			'itemsParams' => 'params',
		},
		'add' => {
			'cmd' => ['dynamicplaylist', 'playlist', 'add'],
			'params' => $params,
			'itemsParams' => 'params',
		},

	};
	$request->addResultLoop('item_loop', $cnt, 'actions', $actions_add);
	$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
	$request->addResultLoop('item_loop', $cnt, 'params', $params);
	$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'nowPlaying');
	$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_ADD'));
	$cnt++;

	## Queue dynamic playlist
	if ($prefs->get('enabledplqueueing')) {
		my $actions_queue = {
			'go' => {
				'cmd' => ['dynamicplaylist', 'playlist', 'queue'],
				'params' => $params,
				'itemsParams' => 'params',
			},
		};
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_queue);
		$request->addResultLoop('item_loop', $cnt, 'params', $params);
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_QUEUE_DPL'));
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'home');
		$cnt++;
	}

	## Add playlist / DSTM seed list and play - if DSTM = enabled and DSTM provider selected
	my $dstmProvider = preferences('plugin.dontstopthemusic')->client($client)->get('provider') || '';
	main::DEBUGLOG && $log->is_debug && $log->debug('dstmProvider = '.$dstmProvider);

	if ($dstm_enabled && $dstmProvider) {
		my $actions_dstm_add = {
			'do' => {
				'cmd' => ['dynamicplaylist', 'playlist', 'dstmplay'],
				'params' => $params,
				'itemsParams' => 'params',
			},
			'play' => {
				'cmd' => ['dynamicplaylist', 'playlist', 'dstmplay'],
				'params' => $params,
				'itemsParams' => 'params',
			},
		};
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_dstm_add);
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
		$request->addResultLoop('item_loop', $cnt, 'params', $params);
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'nowPlaying');
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_DSTM_PLAY'));
		$cnt++;
	}

	## prep for fav saving - check if (volatile) params
	# count params
	my %dplParams;
	for my $k (keys %{$params}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			$dplParams{$k} = $params->{$k};
		}
	}
	my $paramCount = scalar keys %dplParams;

	# check for volatile params
	my $playlistID = $params->{'playlistid'};
	my $hasNoVolatileParams = $playLists->{$playlistID}->{'hasnovolatileparams'};

	if ($prefs->get('enablestaticplsaving') || $paramCount == 0 || ($paramCount > 0 && ($prefs->get('paramsdplsaveenabled') || $hasNoVolatileParams))) {
		# space/empty line
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'text', ' ');
		$request->addResultLoop('item_loop', $cnt, 'type', 'text');
		$cnt++;
	}


	## save dpl as static pl
	if ($prefs->get('enablestaticplsaving')) {
		my $actions_saveasstaticpl = {
			'go' => {
				'cmd' => ['dynamicplaylist', 'savestaticpljiveparams'],
				'params' => $params,
				'itemsParams' => 'params',
			}
		};
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveasstaticpl);
		$request->addResultLoop('item_loop', $cnt, 'params', $params);
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_SAVEASSTATICPL_TITLE'));
		$cnt++;
	}


	## save dpl as fav
	# if we have params, display if params = non-volatile or pref setting = enabled

	if ($paramCount == 0 || ($paramCount > 0 && ($prefs->get('paramsdplsaveenabled') || $hasNoVolatileParams))) {

		my $materialCaller = 1 if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->{'_source'}) && $request->{'_source'} eq 'JSONRPC');
		my $input = {
			initialText => $playLists->{$playlistID}->{'name'},
			len => 1,
			allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
		};

		my $playlistName = $playLists->{$playlistID}->{'name'};
		my $paramAppendix = '';
		if ($paramCount > 0) {
			for (my $i = 1; $i <= $paramCount; $i++) {
				$paramAppendix .= 'p'.$i.'='.$params->{'dynamicplaylist_parameter_'.$i};
				$paramAppendix .= '&' unless $i == $paramCount;
			}
			$playlistName = '__TAGGEDINPUT__';
		}

		# Save dpl as fav (play)
		my $hasParams = 1 if $paramCount > 0 && $paramAppendix ne '';
		my $favUrl = ($paramCount > 0 && $paramAppendix ne '') ? 'dynamicplaylist://'.$playlistID.'?'.$paramAppendix : 'dynamicplaylist://'.$playlistID;
		my $actions_saveFavName = {
			go => {
				player => 0,
				cmd => ['dynamicplaylist', 'jivesaveasfav'],
				params => {
					playlistName => $playlistName,
					url => $favUrl,
					hasParams => $hasParams
				},
				itemsParams => 'params',
			},
		};
		if ($materialCaller && $paramCount > 0) {
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_SAVEASFAV_MATERIAL'));
		} else {
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_SAVEASFAV'));
		}
		$request->addResultLoop('item_loop', $cnt, 'input', $input) if $paramCount > 0;
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay') unless $paramCount > 0;
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveFavName);
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'home');
		$cnt++;

		# Save dpl as fav (add)
		my $favUrlAddOnly = ($paramCount > 0 && $paramAppendix ne '') ? 'dynamicplaylistaddonly://'.$playlistID.'?'.$paramAppendix : 'dynamicplaylistaddonly://'.$playlistID;
		my $actions_saveFavNameAddOnly = {
			go => {
				player => 0,
				cmd => ['dynamicplaylist', 'jivesaveasfav'],
				params => {
					playlistName => $playlistName,
					url => $favUrlAddOnly,
					addOnly => 1,
					hasParams => $hasParams
				},
				itemsParams => 'params',
			},
		};
		if ($materialCaller && $paramCount > 0) {
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_SAVEASFAV_ADDONLY_MATERIAL'));
		} else {
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_SAVEASFAV_ADDONLY'));
		}
		$request->addResultLoop('item_loop', $cnt, 'input', $input) if $paramCount > 0;
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay') unless $paramCount > 0;
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveFavNameAddOnly);
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'home');
		$cnt++;
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveActionsMenuHandler');
	$request->setStatusDone();
}

sub _cliJiveSaveFavWithParams {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliJiveSaveFavWithParams');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['jivesaveasfav']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveSaveFavWithParams');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveSaveFavWithParams');
		return;
	}

	my $params = $request->getParamsCopy();
	my $title = $params->{'playlistName'};
	$title = $title.' ('.string('PLUGIN_DYNAMICPLAYLISTS4_SAVEDASFAV_ADDONLY_SUFFIX').')' if $params->{'addOnly'};
	my $url = $params->{'url'};
	my $isFav = Slim::Utils::Favorites->new(undef)->hasUrl($url);
	my $statusmsg = '';

	if ($isFav) {
		$statusmsg = $params->{'hasParams'} ? string('PLUGIN_DYNAMICPLAYLISTS4_FAVEXISTS_PARAMS') : string('PLUGIN_DYNAMICPLAYLISTS4_FAVEXISTS');
		main::INFOLOG && $log->is_info && $log->info('Not adding dynamic playlist to LMS favorites. This URL is already a favorite: '.$url);
	} else {
		$statusmsg = $params->{'addOnly'} ? string('PLUGIN_DYNAMICPLAYLISTS4_SAVEDASFAV_ADDONLY') : string('PLUGIN_DYNAMICPLAYLISTS4_SAVEDASFAV');
		main::DEBUGLOG && $log->is_debug && $log->debug('Saving this url to LMS favorites: '.$url);
		$client->execute(['favorites', 'add', 'url:'.$url, 'title:'.$title, 'type:audio']);
	}

	my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
	if ($showTimePerChar > 0) {
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4'),
								 $statusmsg]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4').$statusmsg));
		}
		if ($material_enabled) {
			Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$statusmsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($statusmsg)]);
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliJiveSaveFavWithParams');
	$request->setStatusDone();
}


## context menus

sub registerStandardContextMenus {
	Slim::Menu::AlbumInfo->registerInfoProvider(dynamicplaylists4 => (
		after => 'addalbum',
		func => sub {
			if (scalar(@_) < 6) {
				return objectInfoHandler(@_, undef, 'album');
			} else {
				return objectInfoHandler(@_, 'album');
			}
		},
	));
	Slim::Menu::ArtistInfo->registerInfoProvider(dynamicplaylists4 => (
		after => 'addartist',
		func => sub {
			return objectInfoHandler(@_, undef, 'artist');
		},
	));
	Slim::Menu::YearInfo->registerInfoProvider(dynamicplaylists4 => (
		after => 'addyear',
		func => sub {
			return objectInfoHandler(@_, undef, 'year');
		},
	));
	Slim::Menu::PlaylistInfo->registerInfoProvider(dynamicplaylists4 => (
		after => 'addplaylist',
		func => sub {
			return objectInfoHandler(@_, 'playlist');
		},
	));
	Slim::Menu::GenreInfo->registerInfoProvider(dynamicplaylists4 => (
		after => 'addgenre',
		func => sub {
			return objectInfoHandler(@_, undef, 'genre');
		},
	));

	Slim::Menu::AlbumInfo->registerInfoProvider(dynamicplaylists4cacheobj => (
		after => 'dynamicplaylists4',
		func => sub {
			if (scalar(@_) < 6) {
				return registerPreselectionMenu(@_, undef, 'album');
			} else {
				return registerPreselectionMenu(@_, 'album');
			}
		},
	));
	Slim::Menu::ArtistInfo->registerInfoProvider(dynamicplaylists4cacheobj => (
		after => 'dynamicplaylists4',
		func => sub {
			return registerPreselectionMenu(@_, undef, 'artist');
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
	my ($workID, $grouping);
	if ($objectType eq 'genre' || $objectType eq 'artist') {
		$objectName = $obj->name;
		$objectId = $obj->id;
	} elsif ($objectType eq 'album' || $objectType eq 'playlist') {
		if ($objectType eq 'album' && defined($filter->{'work_id'})) {
			return undef; # no context menu for works
		}
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

	if ($playListTypes->{$objectType} && ($objectType ne 'artist' || Slim::Schema->variousArtistsObject->id ne $objectId)) {
		my $jive = {};

		if ($tags->{menuMode}) {
			my $actions = {
				go => {
					player => 0,
					cmd => ['dynamicplaylist', 'contextmenujive'],
					params => {
						$parameterId => $objectId,
						useContextMenu => 1,
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
			name => $client->string('PLUGIN_DYNAMICPLAYLISTS4'),
			favorites => 0,

			player => {
				mode => 'PLUGIN.DynamicPlaylists4.Mixer',
				modeParams => {
					'dynamicplaylist_parameter_1' => $paramItem,
					'playlisttype' => $objectType,
					'flatlist' => 1,
					'extrapopmode' => 1,
				},
			},
			web => {
				group => 'mixers',
				url => 'plugins/DynamicPlaylists4/dynamicplaylist_list.html?playlisttype='.$objectType.'&flatlist=1&dynamicplaylist_parameter_1='.$objectId.'&iscontextmenu='.$iscontextmenu,
				item => $obj,
			},
		};
	}
	return undef;
}


## CLI common ##

sub cliGetPlaylists {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliGetPlaylists');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotQuery([['dynamicplaylist'], ['playlists']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliGetPlaylists');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliGetPlaylists');
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
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliGetPlaylists');
}

sub cliPlayPlaylist {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliPlayPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['play']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliPlayPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliPlayPlaylist');
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
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	my $masterClient = masterOrSelf($client);

	# Clear any current mix type in case user is restarting an already playing mix
	stateStop($masterClient);
	my @players = Slim::Player::Sync::slaves($client);
	foreach my $player (@players) {
		stateStop($player);
	}

	playRandom($client, $playlistId, 0, 1);

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliPlayPlaylist');
}

sub cliContinuePlaylist {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliContinuePlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['continue']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContinuePlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContinuePlaylist');
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
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 0, 1, undef, 1);

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliContinuePlaylist');
}

sub cliAddPlaylist {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliAddPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['add']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliAddPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliAddPlaylist');
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
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 1, 1, 1);

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliAddPlaylist');
}

sub cliDstmSeedListPlay {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliDstmSeedListPlay');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['dstmplay']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliDstmSeedListPlay');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliDstmSeedListPlay');
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
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});
				$playLists->{$playlistId}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	playRandom($client, $playlistId, 2, 1, 1);

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliDstmSeedListPlay');
}

sub cliQueuePlaylist {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliQueuePlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['queue']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliQueuePlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliQueuePlaylist');
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
	return if !$playlistId;

	my $url = 'dynamicplaylist://'.$playlistId;

	my $params = $request->getParamsCopy();

	my $paramCount = 1;
	for my $k (keys %{$params}) {
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			my $parameterId = $1;
			if (exists $playLists->{$playlistId}->{'parameters'}->{$1}) {
				$url .= $paramCount == 1 ? '?' : '&';
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});

				$url .= 'p'.$parameterId.'='.$params->{$k};
				$paramCount++;
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	_queuePlaylist($client, $url, $playLists->{$playlistId});

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliQueuePlaylist');
}

sub cliStopPlaylist {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliStopPlaylist');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['playlist'], ['stop']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliStopPlaylist');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliStopPlaylist');
		return;
	}

	playRandom($client, 'disable');

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliStopPlaylist');
}

sub cliRefreshPlaylists {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering cliRefreshPlaylists');
	my $request = shift;
	my $client = $request->client();

	if ($request->isNotCommand([['dynamicplaylist'], ['refreshplaylists']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliRefreshPlaylists');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliRefreshPlaylists');
		return;
	}

	initPlayLists($client);
	initPlayListTypes();

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting cliRefreshPlaylists');
}


### IP3k / VFD devices ###

sub setModeMixer {
	my ($client, $method) = @_;

	# delete previous multiple selection
	$client->pluginData('selected_genres' => []);
	$client->pluginData('selected_decades' => []);
	$client->pluginData('temp_decadelist' => {});
	$client->pluginData('selected_years' => []);
	$client->pluginData('selected_staticplaylists' => []);

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	my $masterClient = masterOrSelf($client);
	my @listRef = ();
	initPlayLists($client);
	initPlayListTypes();
	my $playlisttype = $client->modeParam('playlisttype');
	my $showFlat = $prefs->get('flatlist');
	if ($showFlat || defined($client->modeParam('flatlist'))) {
		foreach my $flatItem (sort { ($playLists->{$a}->{'playlistsortname'} || '') cmp ($playLists->{$b}->{'playlistsortname'} || ''); } keys %{$playLists}) {
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
		foreach my $menuItemKey (sort { ($playListItems->{$a}->{'playlistsortname'} || '') cmp ($playListItems->{$b}->{'playlistsortname'} || ''); } keys %{$playListItems}) {
			if ($playListItems->{$menuItemKey}->{'dynamicplaylistenabled'}) {
				if (!defined($playlisttype)) {
					if (!defined $playListItems->{$menuItemKey}->{'playlist'} && $customsortnames{$playListItems->{$menuItemKey}->{'name'}}) {
						$playListItems->{$menuItemKey}->{'groupsortname'} = $customsortnames{$playListItems->{$menuItemKey}->{'name'}};
						if ($categorylangstrings{$playListItems->{$menuItemKey}->{'name'}}) {
							$playListItems->{$menuItemKey}->{'displayname'} = $categorylangstrings{$playListItems->{$menuItemKey}->{'name'}};
						} else {
							$playListItems->{$menuItemKey}->{'displayname'} = $playListItems->{$menuItemKey}->{'name'};
						}
					} else {
						$playListItems->{$menuItemKey}->{'playlist'}->{'groupsortname'} = $playListItems->{$menuItemKey}->{'playlist'}->{'name'};
					}
					push @listRef, $playListItems->{$menuItemKey};
			} else {
					if (defined($playListItems->{$menuItemKey}->{'playlist'})) {
						my $playlist = $playListItems->{$menuItemKey}->{'playlist'};
						if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{'1'}) && ($playlist->{'parameters'}->{'1'}->{'type'} eq $playlisttype || ($playlist->{'parameters'}->{'1'}->{'type'} =~ /^custom(.+)$/ && $1 eq $playlisttype))) {
							if ($playlist->{'name'}) {
								$playlist->{'groupsortname'} = $playlist->{'name'};
							}
							push @listRef, $playListItems->{$menuItemKey};
						}
					} else {
						if ($customsortnames{$playListItems->{$menuItemKey}->{'name'}}) {
							$playListItems->{$menuItemKey}->{'groupsortname'} = $customsortnames{$playListItems->{$menuItemKey}->{'name'}};
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
		if (defined($a->{'groupsortname'}) && defined($b->{'groupsortname'})) {
			return lc($a->{'groupsortname'}) cmp lc($b->{'groupsortname'});
		}
		if (defined($a->{'groupsortname'}) && !defined($b->{'groupsortname'})) {
			return lc($a->{'groupsortname'}) cmp lc($b->{'playlist'}->{'groupsortname'});
		}
		if (!defined($a->{'groupsortname'}) && defined($b->{'groupsortname'})) {
			return lc($a->{'playlist'}->{'groupsortname'}) cmp lc($b->{'groupsortname'});
		}
		return lc($a->{'playlist'}->{'groupsortname'}) cmp lc($b->{'playlist'}->{'groupsortname'})
	} @listRef;

	# use PLUGIN.DynamicPlaylists4.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_DYNAMICPLAYLISTS4} {count}',
		listRef => \@listRef,
		name => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName => 'PLUGIN.DynamicPlaylists4',
		onPlay => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i = 1;
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
					my $i = 1;
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
			if (defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} && $item->{'playlist'}->{'dynamicplaylistid'} eq 'disable') {
				handlePlayOrAdd($client, $item->{'playlist'}->{'dynamicplaylistid'}, 0);
			} elsif (defined($item->{'childs'})) {
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlaylists4.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
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
		onFavorites => sub {
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
	my $i = 1;
	while (defined($client->modeParam('dynamicplaylist_parameter_'.$i))) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
		$i++;
	}
	if (defined($client->modeParam('extrapopmode'))) {
		$params{'extrapopmode'} = $client->modeParam('extrapopmode');
	}

	# if we have an active mode, temporarily add the disable option to the list.
	if ($mixInfo{$masterClient} && $mixInfo{$masterClient}->{'type'} && $mixInfo{$masterClient}->{'type'} ne '') {
		push @{$params{listRef}}, \%disable;
	}

	Slim::Buttons::Common::pushMode($client, 'PLUGIN.DynamicPlaylists4.Choice', \%params);
}

sub addFavorite {
	my ($client, $item, $hotkey) = @_;
	if (Slim::Utils::Favorites->enabled && defined($item->{'playlist'}) && $item->{'playlist'}->{'dynamicplaylistid'} ne 'disable' && !defined($item->{'playlist'}->{'parameters'})) {
		my $url = 'dynamicplaylist://'.$item->{'playlist'}->{'dynamicplaylistid'};
		my $favs = Slim::Utils::Favorites->new($client);
		my ($index, $hk) = $favs->findUrl($url);
		my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
		if (!defined($index)) {
			if (defined $hotkey) {
				my $oldindex = $favs->hasHotkey($hotkey);
				$favs->setHotkey($oldindex, undef) if defined $oldindex;
				my $newindex = $favs->add($url, $item->{'playlist'}->{'name'}, 'audio');
				$favs->setHotkey($newindex, $hotkey);
			} else {
				my (undef, $hotkey) = $favs->add($url, $item->{'playlist'}->{'name'}, 'audio', undef, 'hotkey');
			}

			# Display status message(s) if $showTimePerChar > 0
			if ($showTimePerChar > 0) {
				$client->showBriefly({
					'line' => [$client->string('FAVORITES_ADDING'), $item->{'playlist'}->{'name'}]
				}, getMsgDisplayTime(string('FAVORITES_ADDING').$item->{'playlist'}->{'name'}));
			}
		} elsif (defined($hotkey)) {
			$favs->setHotkey($index, undef);
			$favs->setHotkey($index, $hotkey);

			# Display status message(s) if $showTimePerChar > 0
			if ($showTimePerChar > 0) {
				$client->showBriefly({
					'line' => [$client->string('FAVORITES_ADDING'), $item->{'playlist'}->{'name'}]
				}, getMsgDisplayTime(string('FAVORITES_ADDING').$item->{'playlist'}->{'name'}));
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Already exists as a favorite');
		}
	} else {
		$log->warn('Favorites not supported on this item');
	}
}

sub setMode {
	my ($class, $client, $method) = @_;
	setModeMixer($client, $method);
}

sub enterSelectedGroup {
	my ($client, $listRef, $selectedGroups) = @_;
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
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlaylists4.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
				return 1;
			}
		}
	}
	return undef;
}

sub setModeChooseParameters {
	my ($client, $method) = @_;

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

	# get VLID to limit displayed parameters options to those in VL if necessary
	my $limitingParamSelVLID = checkForLimitingVL($client, undef, $playlist, 2);

	my $parameter = $playlist->{'parameters'}->{$parameterId};
	my @listRef = ();
	addParameterValues($client, \@listRef, $parameter, undef, $playlist, $limitingParamSelVLID);
	my $sorted = '0';
	if (scalar(@listRef) > 0) {
		my $firstItem = $listRef[0];
		if (defined($firstItem->{'sortlink'})) {
			$sorted = 'L';
		}
	}
	my $name = $parameter->{'name'};
	my %params;

	if (!$parameter->{'type'}) {
		$log->warn('Missing parameter type!');
		return;
	}

	if ($parameter->{'type'} eq 'multiplegenres' || $parameter->{'type'} eq 'multipledecades' || $parameter->{'type'} eq 'multipleyears' || $parameter->{'type'} eq 'multiplestaticplaylists') {
		my @listRef;
		my $header = '';

		# Continue or play
		if (exists $playlist->{'parameters'}->{($parameterId + 1)}) {
			@listRef = ({
				name => $client->string('PLUGIN_DYNAMICPLAYLISTS4_NEXT'),
				paramType => $parameter->{'type'},
				value => 0,
			});
		} else {
			@listRef = ({
				name => $client->string('PLUGIN_DYNAMICPLAYLISTS4_PLAY'),
				paramType => $parameter->{'type'},
				value => 0,
			});
		}

		# Select all or none
		push @listRef, ({
			name => $client->string('PLUGIN_DYNAMICPLAYLISTS4_SELECT_ALLORNONE'),
			paramType => $parameter->{'type'},
			selectAll => 1,
			value => 1,
		});

		# Add individual selection items
		if ($parameter->{'type'} eq 'multiplegenres') {
			$header = '{PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES}';
			my $genres = getGenres($client, $limitingParamSelVLID);
			foreach my $genre (getSortedGenres($client, $limitingParamSelVLID)) {
				$genres->{$genre}->{'value'} = $genres->{$genre}->{'id'};
				$genres->{$genre}->{'paramType'} = $parameter->{'type'};
				push @listRef, $genres->{$genre};
			}
		}
		if ($parameter->{'type'} eq 'multipledecades') {
			$header = '{PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES}';
			my $decades = getDecades($client, $limitingParamSelVLID);
			foreach my $decade (getSortedDecades($client, $limitingParamSelVLID)) {
				$decades->{$decade}->{'value'} = $decade;
				$decades->{$decade}->{'paramType'} = $parameter->{'type'};
				push @listRef, $decades->{$decade};
			}
		}
		if ($parameter->{'type'} eq 'multipleyears') {
			$header = '{PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTYEARS}';
			my $years = getYears($client, $limitingParamSelVLID);
			foreach my $year (getSortedYears($client, $limitingParamSelVLID)) {
				$years->{$year}->{'value'} = $year;
				$years->{$year}->{'paramType'} = $parameter->{'type'};
				push @listRef, $years->{$year};
			}
		}
		if ($parameter->{'type'} eq 'multiplestaticplaylists') {
			$header = '{PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPLAYLISTS}';
			my $staticPlaylists = getStaticPlaylists($client, $limitingParamSelVLID);
			foreach my $staticPlaylist (getSortedStaticPlaylists($client, $limitingParamSelVLID)) {
				$staticPlaylists->{$staticPlaylist}->{'value'} = $staticPlaylists->{$staticPlaylist}->{'id'};
				$staticPlaylists->{$staticPlaylist}->{'paramType'} = $parameter->{'type'};
				push @listRef, $staticPlaylists->{$staticPlaylist};
			}
		}

		%params = (
			header => $header,
			headerAddCount => 1,
			listRef => \@listRef,
			modeName => 'PLUGIN.DynamicPlaylists4.ChooseParameters',
			overlayRef => \&getGenreOverlay,
			onRight => \&_toggleMultipleSelectionStateIP3k,
			onPlay => \&_toggleMultipleSelectionStateIP3k,
			onAdd => \&_toggleMultipleSelectionStateIP3k,

			dynamicplaylist_nextparameter => $parameterId,
			dynamicplaylist_selectedplaylist => $playlist,
			dynamicplaylist_addonly => $client->modeParam('dynamicplaylist_addonly')
		);

	} else {
		%params = (
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
			modeName => 'PLUGIN.DynamicPlaylists4.ChooseParameters',
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
	}
	for(my $i = 1; $i < $parameterId; $i++) {
		$params{'dynamicplaylist_parameter_'.$i} = $client->modeParam('dynamicplaylist_parameter_'.$i);
	}
	if (defined($client->modeParam('extrapopmode'))) {
		$params{'extrapopmode'} = $client->modeParam('extrapopmode');
	}

	Slim::Buttons::Common::pushMode($client, 'INPUT.Choice', \%params);
}

sub getSetModeDataForSubItems {
	my ($client, $currentItem, $items) = @_;

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
		if (defined($a->{'playlistsortname'}) && defined($b->{'playlistsortname'})) {
			return lc($a->{'playlistsortname'}) cmp lc($b->{'playlistsortname'});
		}
		if (defined($a->{'playlist'}->{'playlistsortname'}) && defined($b->{'playlist'}->{'playlistsortname'})) {
			return lc($a->{'playlist'}->{'playlistsortname'}) cmp lc($b->{'playlist'}->{'playlistsortname'});
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
		header => '{PLUGIN_DYNAMICPLAYLISTS4} {count}',
		listRef => \@listRefSub,
		name => \&getDisplayText,
		overlayRef => \&getOverlay,
		modeName => 'PLUGIN.DynamicPlaylists4'.$currentItem->{'value'},
		onPlay => sub {
			my ($client, $item) = @_;
			if (defined($item->{'playlist'})) {
				my $playlist = $item->{'playlist'};
				if (defined($playlist->{'parameters'})) {
					my %parameterValues = ();
					my $i = 1;
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
					my $i = 1;
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
				Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlaylists4.Choice', getSetModeDataForSubItems($client, $item, $item->{'childs'}));
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
				requestFirstParameter($client, $item->{'playlist'}, 0, \%parameterValues);
			} else {
				$client->bumpRight();
			}
		},
		onFavorites => sub {
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
	my ($client, $item, $parameterId, $playlist, $addOnly) = @_;

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
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlaylists4.ChooseParameters', \%nextParameter);
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
	my ($client, $playlist, $addOnly, $params) = @_;

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
	$nextParameters{'dynamicplaylist_nextparameter'} = $i;

	if (defined($playlist->{'parameters'}) && defined($playlist->{'parameters'}->{$nextParameters{'dynamicplaylist_nextparameter'}})) {
		Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.DynamicPlaylists4.ChooseParameters', \%nextParameters);
	} else {
		for($i = 1; $i < $nextParameters{'dynamicplaylist_nextparameter'}; $i++) {
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
	my ($client, $noOfSteps) = @_;
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
		my $displayname;
		if ($item->{'displayname'}) {
			$name = $item->{'displayname'};
		} else {
			$name = $item->{'name'} || '';
		}
		if ($name eq '' && defined($item->{'playlist'})) {
			$name = $item->{'playlist'}->{'name'};
			$id = $item->{'playlist'}->{'dynamicplaylistid'};
		}
	}

	# if showing the current mode, show altered string
	if ($mixInfo{$masterClient} && defined($mixInfo{$masterClient}->{'type'}) && $id && $id eq $mixInfo{$masterClient}->{'type'}) {
		return $name.' ('.string('PLUGIN_DYNAMICPLAYLISTS4_PLAYING').')';

	# if a mode is active, handle the temporarily added disable option
	} elsif ($id && $id eq 'disable' && $mixInfo{$masterClient}) {
		return string('PLUGIN_DYNAMICPLAYLISTS4_PRESS_RIGHT');
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

sub getGenreOverlay {
	my ($client, $item) = @_;

	if ($item->{'name'} && ($item->{'name'} eq $client->string('PLUGIN_DYNAMICPLAYLISTS4_NEXT') || $item->{'name'} eq $client->string('PLUGIN_DYNAMICPLAYLISTS4_PLAY'))) {
		return [undef, $client->symbols('rightarrow')];
	} else {
		my $value = 0;
		if (!$item->{'paramType'}) {
			$log->warn('Missing parameter type!');
			return;
		}
		if ($item->{'paramType'} eq 'multiplegenres') {
			my $genres = getGenres($client);
			if ($item->{'selectAll'}) {
				# This item should be ticked if all the genres are selected
				my $genresSelected = 0;
				for my $genre (keys %{$genres}) {
					if ($genres->{$genre}->{'selected'}) {
						$genresSelected++;
					}
				}
				$value = $genresSelected == scalar keys %{$genres};
				$item->{'selected'} = $value;
			} else {
				$value = $genres->{$item->{'id'}}->{'selected'};
			}
		}
		if ($item->{'paramType'} eq 'multipledecades') {
			my $decades = getDecades($client);
			if ($item->{'selectAll'}) {
				# This item should be ticked if all the genres are selected
				my $decadesSelected = 0;
				for my $decade (keys %{$decades}) {
					if ($decades->{$decade}->{'selected'}) {
						$decadesSelected++;
					}
				}
				$value = $decadesSelected == scalar keys %{$decades};
				$item->{'selected'} = $value;
			} else {
				$value = $decades->{$item->{'id'}}->{'selected'};
			}
		}
		if ($item->{'paramType'} eq 'multipleyears') {
			my $years = getYears($client);
			if ($item->{'selectAll'}) {
				# This item should be ticked if all the genres are selected
				my $yearsSelected = 0;
				for my $year (keys %{$years}) {
					if ($years->{$year}->{'selected'}) {
						$yearsSelected++;
					}
				}
				$value = $yearsSelected == scalar keys %{$years};
				$item->{'selected'} = $value;
			} else {
				$value = $years->{$item->{'id'}}->{'selected'};
			}
		}
		if ($item->{'paramType'} eq 'multiplestaticplaylists') {
			my $staticPlaylists = getStaticPlaylists($client);
			if ($item->{'selectAll'}) {
				# This item should be ticked if all the genres are selected
				my $staticPlaylistsSelected = 0;
				for my $staticPlaylist (keys %{$staticPlaylists}) {
					if ($staticPlaylists->{$staticPlaylist}->{'selected'}) {
						$staticPlaylistsSelected++;
					}
				}
				$value = $staticPlaylistsSelected == scalar keys %{$staticPlaylists};
				$item->{'selected'} = $value;
			} else {
				$value = $staticPlaylists->{$item->{'id'}}->{'selected'};
			}
		}
		return [undef, Slim::Buttons::Common::checkBoxOverlay($client, $value)];
	}
}

sub getChooseParametersOverlay {
	my ($client, $item) = @_;
	return [undef, $client->symbols('rightarrow')];
}



### features ###

## save dpl as static playlist ##

sub saveAsStaticPlaylist {
	my ($client, $type, $staticPLmaxTrackLimit, $staticPLname, $sortOrder) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('Killing existing timers for saving static PL to prevent multiple calls');
	Slim::Utils::Timers::killOneTimer(undef, \&saveAsStaticPlaylist);

	main::DEBUGLOG && $log->is_debug && $log->debug("Creating static playlist with max. $staticPLmaxTrackLimit items for type: $type");
	my $started = time();

	my $masterClient = masterOrSelf($client);
	my $playlist = getPlayList($client, $type);
	my ($newTrackIDs, $filteredtrackIDs);
	my ($totalTracksCompleteInfo, $newTracksCompleteInfo) = {};
	my $totalTrackIDList = [];
	my $noOfRetriesToGetUnplayedTracks = 20;

	my $i = 1;
	my ($noMatchResults, $noPostFilterResults) = 0;
	while ($i <= $noOfRetriesToGetUnplayedTracks) {
		my $iterationStartTime = time();
		main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: total trackIDs so far = ".scalar(@{$totalTrackIDList}).' -- staticPLmaxTrackLimit = '.$staticPLmaxTrackLimit);

		# Get track IDs
		my $getTrackIDsForPlaylistStartTime = time();
		($newTrackIDs, $newTracksCompleteInfo) = getTrackIDsForPlaylist($masterClient, $playlist, $staticPLmaxTrackLimit, 0);

		if ($newTrackIDs && $newTrackIDs eq 'error') {
			$log->error('Error trying to find tracks. Please check your playlist definition.');
			last;
		}

		main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: returned ".(defined $newTrackIDs ? scalar(@{$newTrackIDs}) : 0).' tracks in '.(time() - $getTrackIDsForPlaylistStartTime). ' seconds');

		# stop if search returns no results at all (5x)
		if (!defined $newTrackIDs || scalar(@{$newTrackIDs}) == 0) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i didn't return any track IDs");
			$i++;
			$noMatchResults++;
			$noMatchResults >= 5 ? last : next;
		}

		# Filter track IDs
		my $filterTrackIDsStartTime = time();
		$newTrackIDs = filterTrackIDs($masterClient, $newTrackIDs, $totalTrackIDList, 1);
		main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: returned ".(scalar @{$newTrackIDs}).((scalar @{$newTrackIDs}) == 1 ? ' item' : ' items').' after filtering. Filtering took '.(time() - $filterTrackIDsStartTime).' seconds');

		# Add new tracks to total track vars
		my $addingNewTracksToTotalVars = time();
		if (scalar(@{$totalTrackIDList}) == 0) {
			$totalTrackIDList = $newTrackIDs;
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('totaltracks > 0');
			push (@{$totalTrackIDList}, @{$newTrackIDs});
		}

		if (keys %{$newTracksCompleteInfo} > 0) {
			$totalTracksCompleteInfo = $newTracksCompleteInfo if keys %{$newTracksCompleteInfo} > 0;
		} else {
			$totalTracksCompleteInfo = { %{$totalTracksCompleteInfo}, %{$newTracksCompleteInfo} } if keys %{$newTracksCompleteInfo} > 0;
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding new tracks to total tracks vars exec time = '.(time() - $addingNewTracksToTotalVars).' secs');
		main::DEBUGLOG && $log->is_debug && $log->debug('Total track IDs found so far = '.scalar(@{$totalTrackIDList}));

		# stop if search AFTER filtering returns no results (5x)
		if (defined $newTrackIDs && scalar(@{$newTrackIDs}) == 0) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Iteration $i: didn't return any items after filtering");
			$i++;
			$noPostFilterResults++;
			main::idleStreams();
			$noPostFilterResults >= 5 ? last : next;
		}

		$i++;
		main::idleStreams();

		last if scalar(@{$totalTrackIDList}) >= $staticPLmaxTrackLimit;
	}

	if (scalar(@{$totalTrackIDList}) == 0) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Found no tracks matching your search parameter or playlist definition for dynamic playlist "'.$playlist->{'name'}.'" (query time = '.(time()-$started).' seconds).');
		return 0;
	}

	## limit results if necessary
	if (scalar(@{$totalTrackIDList}) > $staticPLmaxTrackLimit) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Limiting the number of new tracks to be added to the specified limit ($staticPLmaxTrackLimit)");
		my $limitingExecStartTime = time();
		@{$totalTrackIDList} = @{$totalTrackIDList}[0..($staticPLmaxTrackLimit - 1)];
		main::DEBUGLOG && $log->is_debug && $log->debug('Limiting exec time: '.(time() - $limitingExecStartTime).' secs');
	}

	## shuffle all track IDs?
	my $playlistTrackOrder = $playlist->{'playlisttrackorder'};
	unless ($sortOrder > 1 || $playlistTrackOrder && ($playlistTrackOrder eq 'ordered' || $playlistTrackOrder eq 'ordereddescrandom' || $playlistTrackOrder eq 'orderedascrandom')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Shuffling all track IDs');
		my $shuffledIDlist = shuffleIDlist($totalTrackIDList, $totalTracksCompleteInfo);
		@{$totalTrackIDList} = @{$shuffledIDlist};
	}

	## Get tracks for ids
	my @totalTracks;
	my $getTracksForIDsStartTime = time();
	foreach (@{$totalTrackIDList}) {
		push @totalTracks, Slim::Schema->rs('Track')->single({'id' => $_});
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Getting track objects for track IDs took '.(time()-$getTracksForIDsStartTime). ' seconds');
	main::idleStreams();

	# Sort tracks?
	if (scalar(@totalTracks) > 1 && $sortOrder > 1) {
		my $sortStartTime= time();
		if ($sortOrder == 2) {
			# sort order: artist > album > disc no. > track no.
			@totalTracks = sort {lc($a->artist->namesort) cmp lc($b->artist->namesort) || lc($a->album->namesort) cmp lc($b->album->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @totalTracks;
		} elsif ($sortOrder == 3) {
			# sort order: album > artist > disc no. > track no.
			@totalTracks = sort {lc($a->album->namesort) cmp lc($b->album->namesort) || lc($a->artist->namesort) cmp lc($b->artist->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @totalTracks;
		} elsif ($sortOrder == 4) {
			# sort order: album > disc no. > track no.
			@totalTracks = sort {lc($a->album->namesort) cmp lc($b->album->namesort) || ($a->disc || 0) <=> ($b->disc || 0) || ($a->tracknum || 0) <=> ($b->tracknum || 0)} @totalTracks;
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Sorting tracks took '.(time()-$sortStartTime).' seconds');
		main::idleStreams();
	}

	## Save tracks as static playlist ###

	# if PL with same name exists, add epoch time to PL name
	my $newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();
	if ($newStaticPL) {
		my $timestamp = strftime "%Y-%m-%d--%H-%M-%S", localtime time;
		$staticPLname = $staticPLname.'_'.$timestamp;
	}
	$newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();
	Slim::Control::Request::executeRequest(undef, ['playlists', 'new', 'name:'.$staticPLname]) if !$newStaticPL;
	$newStaticPL = Slim::Schema->search('Playlist', {'title' => $staticPLname })->first();

	my $setTracksStartTime = time();
	$newStaticPL->setTracks(\@totalTracks);
	main::DEBUGLOG && $log->is_debug && $log->debug("setTracks took ".(time()-$setTracksStartTime).' seconds');
	$newStaticPL->update;
	main::idleStreams();

	my $scheduleWriteOfPlaylistStartTime = time();
	Slim::Player::Playlist::scheduleWriteOfPlaylist(undef, $newStaticPL);
	main::DEBUGLOG && $log->is_debug && $log->debug("scheduleWriteOfPlaylist took ".(time()-$scheduleWriteOfPlaylistStartTime).' seconds');

	main::INFOLOG && $log->is_info && $log->info('Saved static playlist "'.$staticPLname.'" with '.scalar(@totalTracks).(scalar(@totalTracks) == 1 ? ' track' : ' tracks').' using playlist definition "'.$playlist->{'name'}.'". Task completed after '.(time()-$started)." seconds.\n\n");

	# display message when task is finished
	my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
	if ($showTimePerChar > 0) {
		my $statusmsg = string('PLUGIN_DYNAMICPLAYLISTS4_SAVINGSTATICPL_DONE').': '.$staticPLname;
		if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
			$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4'),
								 $statusmsg]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4').$statusmsg));
		}
		if ($material_enabled) {
			Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$statusmsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($statusmsg)]);
		}
	}
	return;
}

sub _saveAsStaticNoParamsWeb {
	my ($client, $params) = @_;
	my $playlist = getPlayList($client, $params->{'type'});
	$params->{'staticplname'} = $playlist->{'name'};
	$params->{'lastparameter'} = 'islastparam';
	$params->{'addOnly'} = 77;
	$params->{'pluginDynamicPlaylists4AddOnly'} = 77;
	$params->{'pluginDynamicPlaylists4PlaylistId'} = $params->{'type'};
	$params->{'pluginDynamicPlaylists4noParamsStaticPLsave'} = 1;
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlaylists4/dynamicplaylist_mixparameters.html', $params);
}

sub _saveStaticPlaylistJiveParams {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering _saveStaticPlaylistJiveParams');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['dynamicplaylist'], ['savestaticpljiveparams']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJiveParams');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJiveParams');
		return;
	}

	my $params = $request->getParamsCopy();
	main::DEBUGLOG && $log->is_debug && $log->debug('params = '.Data::Dump::dump($params));


	# get playlist id and dpl params
	my $playlistID = $request->getParam('playlistid');
	my %baseParams = (
		'playlistid' => $playlistID
	);
	for my $k (keys %{$params}) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		if ($k =~ /^dynamicplaylist_parameter_(.*)|sortorder|staticplmaxtracklimit|playlistname$/) {
			$baseParams{$k} = $params->{$k};
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('baseparams = '.Data::Dump::dump(\%baseParams));

	# get/set static pl params
	my $sortOrder = $request->getParam('sortorder');
	my $staticPLmaxTrackLimit = $request->getParam('staticplmaxtracklimit');
	my $staticPLname = $request->getParam('staticplaylistname');

	my $cnt = 0;
	my $materialCaller = 1 if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->{'_source'}) && $request->{'_source'} eq 'JSONRPC');

	if (!$sortOrder) {
		$request->addResult('window', {
			menustyle => 'album',
			text => string('PLUGIN_DYNAMICPLAYLISTS4_NEWSTATICPLSORTORDER'),
		});

		for (my $i = 1; $i < 5; $i++) {
			my %itemParams = (
				'sortorder' => $i
			);
			my %newbaseParams = (%baseParams, %itemParams);

			my $actions_saveasstaticpl_sort = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'savestaticpljiveparams'],
					'params' => \%newbaseParams,
					'itemsParams' => 'params',
				}
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveasstaticpl_sort);
			$request->addResultLoop('item_loop', $cnt, 'params', $params);
			$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
			$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_NEWSTATICPLSORTORDER_SORT'.$i));
			$cnt++;
		}
	}

	if ($sortOrder && !$staticPLmaxTrackLimit) {
		$request->addResult('window', {
			menustyle => 'album',
			text => string('PLUGIN_DYNAMICPLAYLISTS4_NEWSTATICPLMAXTRACKLIMIT'),
		});
		my @jiveTrackLimitChoices = (100,200,500,1000,1500,2000,3000,4000);
		my $input = {
			initialText => $playLists->{$playlistID}->{'name'},
			title => $client->string('PLUGIN_DYNAMICPLAYLISTS4_ENTERNEWSTATICPLNAME'),
			len => 1,
			allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
		};
		while (my ($index, $limit) = each(@jiveTrackLimitChoices)) {
			my %itemParams = (
				'staticplmaxtracklimit' => $limit,
			);
			unless ($materialCaller) {
				$itemParams{'staticplaylistname'} = '__TAGGEDINPUT__';
			}

			my %newbaseParams = (%baseParams, %itemParams);

			my $cmd = $materialCaller ? 'savestaticpljiveparams' : 'savestaticpljive';
			my $actions_saveasstaticpl_tracklimit = {
				'go' => {
					'cmd' => ['dynamicplaylist', $cmd],
					'params' => \%newbaseParams,
					'itemsParams' => 'params',
				}
			};
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveasstaticpl_tracklimit);
			$request->addResultLoop('item_loop', $cnt, 'input', $input) unless $materialCaller;
			$request->addResultLoop('item_loop', $cnt, 'params', $params);
			$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
			$request->addResultLoop('item_loop', $cnt, 'text', "$limit");
			$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'home') unless $materialCaller;
			$cnt++;
		}
	}

	if ($materialCaller && $sortOrder && $staticPLmaxTrackLimit && !$staticPLname) {
		$request->addResult('window', {
			menustyle => 'album',
			text => string('PLUGIN_DYNAMICPLAYLISTS4_ENTERNEWSTATICPLNAME'),
		});
		my $input = {
			initialText => $playLists->{$playlistID}->{'name'},
			len => 1,
			allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
		};

		$baseParams{'staticplaylistname'} = '__TAGGEDINPUT__';

		my $actions_saveasstaticpl_plname = {
			'go' => {
				'cmd' => ['dynamicplaylist', 'savestaticpljive'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			}
		};
		$request->addResultLoop('item_loop', $cnt, 'actions', $actions_saveasstaticpl_plname);
		$request->addResultLoop('item_loop', $cnt, 'input', $input);
		$request->addResultLoop('item_loop', $cnt, 'params', $params);
		$request->addResultLoop('item_loop', $cnt, 'text', string('PLUGIN_DYNAMICPLAYLISTS4_ENTERNEWSTATICPLNAME'));
		$request->addResultLoop('item_loop', $cnt, 'type', 'redirect');
		$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'home');
		$cnt++;
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJiveParams');
	$request->setStatusDone();
}

sub _saveStaticPlaylistJive {
	main::DEBUGLOG && $log->is_debug && $log->debug('Entering _saveStaticPlaylistJive');
	my $request = shift;
	my $client = $request->client();

	if (!$request->isCommand([['dynamicplaylist'], ['savestaticpljive']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJive');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJive');
		return;
	}

	# get playlist id
	my $playlistID = $request->getParam('playlistid');
	if (!defined($playlistID)) {
		$playlistID = $request->getParam('_p3');
		if (!defined($playlistID)) {
			$playlistID = $request->getParam('_p0');
		}
	}
	if ($playlistID =~ /^?playlistid:(.+)$/) {
		$playlistID = $1;
	}

	# get dpl params
	my $params = $request->getParamsCopy();
	main::DEBUGLOG && $log->is_debug && $log->debug('params = '.Data::Dump::dump($params));
	for my $k (keys %{$params}) {
		if ($k =~ /^dynamicplaylist_parameter_(.*)$/) {
			my $parameterId = $1;
			if (exists $playLists->{$playlistID}->{'parameters'}->{$1}) {
				main::DEBUGLOG && $log->is_debug && $log->debug("Using: $k = ".$params->{$k});
				$playLists->{$playlistID}->{'parameters'}->{$1}->{'value'} = $params->{$k};
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k});
		}
	}

	my $sortOrder = $request->getParam('sortorder');
	my $staticPLmaxTrackLimit = $request->getParam('staticplmaxtracklimit');
	my $staticPLname = $request->getParam('staticplaylistname') || $playLists->{$playlistID}->{'name'};

	if ($sortOrder && $staticPLmaxTrackLimit && $staticPLname) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Saving static playlist with these parameters: type = '.$playlistID.' -- sortOder = '.$sortOrder.' -- staticPLmaxTrackLimit = '.$staticPLmaxTrackLimit.' -- staticPlaylistName = '.$staticPLname);
		my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
		if ($showTimePerChar > 0) {
			my $statusmsg = string('PLUGIN_DYNAMICPLAYLISTS4_SAVINGSTATICPL_INPROGRESS');
			if (Slim::Buttons::Common::mode($client) !~ /^SCREENSAVER./) {
				$client->showBriefly({'line' => [string('PLUGIN_DYNAMICPLAYLISTS4'),
									 $statusmsg]}, getMsgDisplayTime(string('PLUGIN_DYNAMICPLAYLISTS4').$statusmsg));
			}
			if ($material_enabled) {
				Slim::Control::Request::executeRequest(undef, ['material-skin', 'send-notif', 'type:info', 'msg:'.$statusmsg, 'client:'.$client->id, 'timeout:'.getMsgDisplayTime($statusmsg)]);
			}
		}
		$staticPLname = Slim::Utils::Misc::cleanupFilename($staticPLname);
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1, \&saveAsStaticPlaylist, $playlistID, $staticPLmaxTrackLimit, $staticPLname, $sortOrder);
	} else {
		$log->warn('Missing parameter value(s). Got sortOrder = '.Data::Dump::dump($sortOrder).' -- maxtracklimit = '.Data::Dump::dump($staticPLmaxTrackLimit).' -- playlist name = '.Data::Dump::dump($staticPLname));
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _saveStaticPlaylistJive');
	$request->setStatusDone();
}


## multiple selection ##

sub _toggleMultipleSelectionState {
	my $request = shift;
	my $client = $request->client();
	my $paramType = $request->getParam('_paramtype');
	my $item = $request->getParam('_item'); # item: genre, decade, year or static playlist
	my $value = $request->getParam('_value');
	my @selected = ();

	if (!$paramType) {
		$log->warn('Missing parameter type!');
		return;
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Received input: paramType = '.$paramType.' -- item = '.$item.' -- value = '.$value);

	if ($paramType eq 'multiplegenres') {
		my $genres = getGenres($client);
		$genres->{$item}->{'selected'} = $value;
		for my $genre (keys %{$genres}) {
			push @selected, $genre if $genres->{$genre}->{'selected'} == 1;
		}
		$client->pluginData('selected_genres' => [@selected]);
		main::DEBUGLOG && $log->is_debug && $log->debug('pluginData cached for selected genres = '.Data::Dump::dump($client->pluginData('selected_genres')));
	}
	if ($paramType eq 'multipledecades') {
		my $decades = getDecades($client);
		$decades->{$item}->{'selected'} = $value;
		for my $decade (keys %{$decades}) {
			push @selected, $decade if $decades->{$decade}->{'selected'} == 1;
		}
		$client->pluginData('selected_decades' => [@selected]);
		main::DEBUGLOG && $log->is_debug && $log->debug('pluginData cached for selected decades = '.Data::Dump::dump($client->pluginData('selected_decades')));
	}
	if ($paramType eq 'multipleyears') {
		my $years = getYears($client);
		$years->{$item}->{'selected'} = $value;
		for my $year (keys %{$years}) {
			push @selected, $year if $years->{$year}->{'selected'} == 1;
		}
		$client->pluginData('selected_years' => [@selected]);
		main::DEBUGLOG && $log->is_debug && $log->debug('pluginData cached for selected years = '.Data::Dump::dump($client->pluginData('selected_years')));
	}
	if ($paramType eq 'multiplestaticplaylists') {
		my $staticPlaylists = getStaticPlaylists($client);
		$staticPlaylists->{$item}->{'selected'} = $value;
		for my $staticPlaylist (keys %{$staticPlaylists}) {
			push @selected, $staticPlaylist if $staticPlaylists->{$staticPlaylist}->{'selected'} == 1;
		}
		$client->pluginData('selected_staticplaylists' => [@selected]);
		main::DEBUGLOG && $log->is_debug && $log->debug('pluginData cached for selected static playlists = '.Data::Dump::dump($client->pluginData('selected_staticplaylists')));
	}
	$request->setStatusDone();
}

sub _toggleMultipleSelectionStateIP3k {
	my ($client, $item) = @_;

	if ($item->{'name'} && ($item->{'name'} eq $client->string('PLUGIN_DYNAMICPLAYLISTS4_NEXT') || $item->{'name'} eq $client->string('PLUGIN_DYNAMICPLAYLISTS4_PLAY'))) {
		my $parameterId = $client->modeParam('dynamicplaylist_nextparameter');
		my $playlist = $client->modeParam('dynamicplaylist_selectedplaylist');
		my $multipleSelectionString;
		if ($item->{'paramType'} eq 'multipledecades') {
			$multipleSelectionString = getMultipleSelectionString($client, $item->{'paramType'}, 1);
		} else {
			$multipleSelectionString = getMultipleSelectionString($client, $item->{'paramType'});
		}
		$item->{'value'} = $multipleSelectionString;
		$item->{'id'} = $multipleSelectionString;
		requestNextParameter($client, $item, $parameterId, $playlist);
	} else {
		my @selected = ();
		if (!$item->{'paramType'}) {
			$log->warn('Missing parameter type!');
			return;
		}

		if ($item->{'paramType'} eq 'multiplegenres') {
			my $genres = getGenres($client);
			if ($item->{'selectAll'}) {
				$item->{'selected'} = ! $item->{'selected'};
				# Select/deselect every genre
				foreach my $genre (keys %{$genres}) {
					$genres->{$genre}->{'selected'} = $item->{'selected'};
				}
			} else {
				# Toggle the selected state of the current item
				$genres->{$item->{'id'}}->{'selected'} = ! $genres->{$item->{'id'}}->{'selected'};
			}

			for my $genre (keys %{$genres}) {
				push @selected, $genre if $genres->{$genre}->{'selected'} == 1;
			}
			$client->pluginData('selected_genres' => [@selected]);
			main::DEBUGLOG && $log->is_debug && $log->debug('cached client data for multiple selected genres = '.Data::Dump::dump($client->pluginData('selected_genres')));
		}
		if ($item->{'paramType'} eq 'multipledecades') {
			my $decades = getDecades($client);
			if ($item->{'selectAll'}) {
				$item->{'selected'} = ! $item->{'selected'};
				# Select/deselect every genre
				foreach my $decade (keys %{$decades}) {
					$decades->{$decade}->{'selected'} = $item->{'selected'};
				}
			} else {
				# Toggle the selected state of the current item
				$decades->{$item->{'id'}}->{'selected'} = ! $decades->{$item->{'id'}}->{'selected'};
			}

			for my $decade (keys %{$decades}) {
				push @selected, $decade if $decades->{$decade}->{'selected'} == 1;
			}
			$client->pluginData('selected_decades' => [@selected]);
			main::DEBUGLOG && $log->is_debug && $log->debug('cached client data for multiple selected decades = '.Data::Dump::dump($client->pluginData('selected_decades')));
		}
		if ($item->{'paramType'} eq 'multipleyears') {
			my $years = getYears($client);
			if ($item->{'selectAll'}) {
				$item->{'selected'} = ! $item->{'selected'};
				# Select/deselect every genre
				foreach my $year (keys %{$years}) {
					$years->{$year}->{'selected'} = $item->{'selected'};
				}
			} else {
				# Toggle the selected state of the current item
				$years->{$item->{'id'}}->{'selected'} = ! $years->{$item->{'id'}}->{'selected'};
			}

			for my $year (keys %{$years}) {
				push @selected, $year if $years->{$year}->{'selected'} == 1;
			}
			$client->pluginData('selected_years' => [@selected]);
			main::DEBUGLOG && $log->is_debug && $log->debug('cached client data for multiple selected years = '.Data::Dump::dump($client->pluginData('selected_years')));
		}
		if ($item->{'paramType'} eq 'multiplestaticplaylists') {
			my $staticPlaylists = getStaticPlaylists($client);
			if ($item->{'selectAll'}) {
				$item->{'selected'} = ! $item->{'selected'};
				# Select/deselect every genre
				foreach my $staticPlaylist (keys %{$staticPlaylists}) {
					$staticPlaylists->{$staticPlaylist}->{'selected'} = $item->{'selected'};
				}
			} else {
				# Toggle the selected state of the current item
				$staticPlaylists->{$item->{'id'}}->{'selected'} = ! $staticPlaylists->{$item->{'id'}}->{'selected'};
			}

			for my $staticPlaylist (keys %{$staticPlaylists}) {
				push @selected, $staticPlaylist if $staticPlaylists->{$staticPlaylist}->{'selected'} == 1;
			}
			$client->pluginData('selected_staticplaylists' => [@selected]);
			main::DEBUGLOG && $log->is_debug && $log->debug('cached client data for multiple static playlists = '.Data::Dump::dump($client->pluginData('selected_staticplaylists')));
		}
		$client->update;
	}
}

sub _multipleSelectAllOrNone {
	my $request = shift;
	my $client = $request->client();
	my $paramType = $request->getParam('_paramtype');
	my $value = $request->getParam('_value');
	my @selected = ();

	if (!$paramType) {
		$log->warn('Missing parameter type!');
		return;
	}
	if ($paramType eq 'multiplegenres') {
		my $genres = getGenres($client);

		for my $genre (keys %{$genres}) {
			$genres->{$genre}->{'selected'} = $value;
			if ($value == 1) {
				push @selected, $genre;
			}
		}
		$client->pluginData('selected_genres' => [@selected]);
	}
	if ($paramType eq 'multipledecades') {
		my $decades = getDecades($client);

		for my $decade (keys %{$decades}) {
			$decades->{$decade}->{'selected'} = $value;
			if ($value == 1) {
				push @selected, $decade;
			}
		}
		$client->pluginData('selected_decades' => [@selected]);
	}
	if ($paramType eq 'multipleyears') {
		my $years = getYears($client);

		for my $year (keys %{$years}) {
			$years->{$year}->{'selected'} = $value;
			if ($value == 1) {
				push @selected, $year;
			}
		}
		$client->pluginData('selected_years' => [@selected]);
	}
	if ($paramType eq 'multiplestaticplaylists') {
		my $staticPlaylists = getStaticPlaylists($client);

		for my $staticPlaylist (keys %{$staticPlaylists}) {
			$staticPlaylists->{$staticPlaylist}->{'selected'} = $value;
			if ($value == 1) {
				push @selected, $staticPlaylist;
			}
		}
		$client->pluginData('selected_staticplaylists' => [@selected]);
	}
	$request->setStatusDone();
}

sub getGenres {
	my ($client, $limitingParamSelVLID) = @_;
	my $genres = {};
	my $query = ['genres', 0, 999_999];

	my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	$library_id = $limitingParamSelVLID if !$library_id; # active VL on client takes precedence over VL from dynamic playlist
	push @{$query}, 'library_id:'.$library_id if $library_id;

	my $request = Slim::Control::Request::executeRequest($client, $query);

	my $selectedGenres = $client->pluginData('selected_genres') || [];
	my %selected = map { $_ => 1 } @{$selectedGenres};
	my $i = 0;
	foreach my $genre ( @{ $request->getResult('genres_loop') || [] } ) {
		my $genreid = $genre->{id};
		$genres->{$genreid} = {
			'name' => $genre->{genre},
			'id' => $genreid,
			'selected' => $selected{$genreid} ? 1 : 0,
			'sort' => $i++,
		};
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('genres for multiple genre selection = '.Data::Dump::dump($genres));
	return $genres;
}

sub getSortedGenres {
	my ($client, $limitingParamSelVLID) = @_;
	my $genres = getGenres($client, $limitingParamSelVLID);
	return sort { $genres->{$a}->{'sort'} <=> $genres->{$b}->{'sort'}; } keys %{$genres};
}

sub getDecades {
	my ($client, $limitingParamSelVLID) = @_;
	my $dbh = Slim::Schema->dbh;
	my $decades = {};
	my $decadesQueryResult = $client->pluginData('temp_decadelist') || {};
	$decadesQueryResult = {} if $limitingParamSelVLID;

	if (scalar keys %{$decadesQueryResult} == 0) {
		my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
		$library_id = $limitingParamSelVLID if !$library_id; # active VL on client takes precedence over VL from dynamic playlist
		my $unknownString = string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_UNKNOWN');

		my $sql_decades;
		if ($library_id) {
			$sql_decades = "select cast(((ifnull(tracks.year,0)/10)*10) as int) as decade,case when tracks.year>0 then cast(((tracks.year/10)*10) as int)||'s' else '$unknownString' end as decadedisplayed from tracks join library_track on library_track.track = tracks.id and library_track.library = '$library_id' where tracks.audio = 1 group by decade order by decade desc";
		} else {
			$sql_decades = "select cast(((ifnull(tracks.year,0)/10)*10) as int) as decade,case when tracks.year>0 then cast(((tracks.year/10)*10) as int)||'s' else '$unknownString' end as decadedisplayed from tracks where tracks.audio = 1 group by decade order by decade desc";
		}

		my ($decade, $decadeDisplayName);
		eval {
			my $sth = $dbh->prepare($sql_decades);
			$sth->execute() or do {
				$sql_decades = undef;
			};
			$sth->bind_columns(undef, \$decade, \$decadeDisplayName);

			while ($sth->fetch()) {
				$decadesQueryResult->{$decade} = $decadeDisplayName;
			}
			$sth->finish();
			main::DEBUGLOG && $log->is_debug && $log->debug('decadesQueryResult = '.Data::Dump::dump($decadesQueryResult));
			$client->pluginData('temp_decadelist' => $decadesQueryResult);
			main::DEBUGLOG && $log->is_debug && $log->debug('caching new temp_decadelist = '.Data::Dump::dump($client->pluginData('temp_decadelist')));
		};
		if ($@) {
			$log->error("Database error: $DBI::errstr\n$@");
			return 'error';
		}
	}

	my $selectedDecades = $client->pluginData('selected_decades') || [];
	my %selected = map { $_ => 1 } @{$selectedDecades};
	foreach my $decade (keys %{$decadesQueryResult || ()}) {
		my $name = $decadesQueryResult->{$decade};
		$decades->{$decade} = {
			'name' => $name,
			'id' => $decade,
			'selected' => $selected{$decade} ? 1 : 0,
		};
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('decades for multiple decades selection = '.Data::Dump::dump($decades));
	return $decades;
}

sub getSortedDecades {
	my ($client, $limitingParamSelVLID) = @_;
	my $decades = getDecades($client, $limitingParamSelVLID);
	return sort { $decades->{$b}->{'id'} <=> $decades->{$a}->{'id'}; } keys %{$decades};
}

sub getYears {
	my ($client, $limitingParamSelVLID) = @_;
	my $years = {};
	my $query = ['years', 0, 999_999];

	my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	$library_id = $limitingParamSelVLID if !$library_id; # active VL on client takes precedence over VL from dynamic playlist
	push @{$query}, 'library_id:'.$library_id if $library_id;

	my $request = Slim::Control::Request::executeRequest($client, $query);

	my $selectedYears = $client->pluginData('selected_years') || [];
	my %selected = map { $_ => 1 } @{$selectedYears};
	foreach my $year ( @{ $request->getResult('years_loop') || [] } ) {
		my $thisYear = $year->{'year'};
		$years->{$thisYear} = {
			'name' => $thisYear,
			'id' => $thisYear,
			'selected' => $selected{$thisYear} ? 1 : 0,
		};
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('years for multiple decades selection = '.Data::Dump::dump($years));
	return $years;
}

sub getSortedYears {
	my ($client, $limitingParamSelVLID) = @_;
	my $years = getYears($client, $limitingParamSelVLID);
	return sort { $years->{$b}->{'id'} <=> $years->{$a}->{'id'}; } keys %{$years};
}

sub getStaticPlaylists {
	my ($client, $limitingParamSelVLID) = @_;
	my $staticPlaylists = {};
	my $query = ['playlists', '0', '999_999', 'tags:x'];

	my $library_id = Slim::Music::VirtualLibraries->getLibraryIdForClient($client);
	$library_id = $limitingParamSelVLID if !$library_id; # active VL on client takes precedence over VL from dynamic playlist
	push @{$query}, 'library_id:'.$library_id if $library_id;
	my $request = Slim::Control::Request::executeRequest($client, $query);

	my $selectedStaticPlaylists = $client->pluginData('selected_staticplaylists') || [];
	my %selected = map { $_ => 1 } @{$selectedStaticPlaylists};
	foreach my $staticPlaylist ( @{ $request->getResult('playlists_loop') || [] } ) {
		my $staticPlaylistID = $staticPlaylist->{id};
		$staticPlaylists->{$staticPlaylistID} = {
			'name' => $staticPlaylist->{'playlist'},
			'id' => $staticPlaylistID,
			'selected' => $selected{$staticPlaylistID} ? 1 : 0,
		};
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('playlists for multiple static playlist selection = '.Data::Dump::dump($staticPlaylists));
	return $staticPlaylists;
}

sub getSortedStaticPlaylists {
	my ($client, $limitingParamSelVLID) = @_;
	my $staticPlaylists = getStaticPlaylists($client, $limitingParamSelVLID);
	return sort { lc($staticPlaylists->{$a}->{'name'}) cmp lc($staticPlaylists->{$b}->{'name'}); } keys %{$staticPlaylists};
}

sub getMultipleSelectionString {
	my ($client, $paramType, $includeYears) = @_;
	my $multipleSelectionString;
	main::DEBUGLOG && $log->is_debug && $log->debug('paramType = '.$paramType);

	if (!$paramType) {
		$log->warn('Missing parameter type!');
		return;
	}
	if ($paramType eq 'multiplegenres') {
		my $selectedGenres = $client->pluginData('selected_genres') || [];
		main::DEBUGLOG && $log->is_debug && $log->debug('selectedGenres = '.Data::Dump::dump($selectedGenres));
		my @IDsSelectedGenres = ();
		if (scalar (@{$selectedGenres}) > 0) {
			foreach my $genreID (@{$selectedGenres}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Selected genre: '.Slim::Schema->resultset('Genre')->single( {'id' => $genreID })->name.' (ID: '.$genreID.')');
				push @IDsSelectedGenres, $genreID;
			}
		}
		$multipleSelectionString = join (',', @IDsSelectedGenres);
	}
	if ($paramType eq 'multipledecades') {
		my $selectedDecades = $client->pluginData('selected_decades') || [];
		main::DEBUGLOG && $log->is_debug && $log->debug('selectedDecades = '.Data::Dump::dump($selectedDecades));
		my @selectedDecadesArray = ();
		if (scalar (@{$selectedDecades}) > 0) {
			foreach my $decade (@{$selectedDecades}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Selected decade: '.$decade);
				push @selectedDecadesArray, $decade;
			}
		}
		if ($includeYears) {
			my @yearsArray;
			foreach my $decade (@selectedDecadesArray) {
				push @yearsArray, $decade;
				unless ($decade == 0) {
					for (1..9) {
						push @yearsArray, $decade + $_;
					}
				}
			}
			$multipleSelectionString = join (',', @yearsArray);
		} else {
			$multipleSelectionString = join (',', @selectedDecadesArray);
		}
	}
	if ($paramType eq 'multipleyears') {
		my $selectedYears = $client->pluginData('selected_years') || [];
		main::DEBUGLOG && $log->is_debug && $log->debug('selectedYears = '.Data::Dump::dump($selectedYears));
		my @selectedYearsArray = ();
		if (scalar (@{$selectedYears}) > 0) {
			foreach my $year (@{$selectedYears}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Selected decade: '.$year);
				push @selectedYearsArray, $year;
			}
		}
		$multipleSelectionString = join (',', @{$selectedYears});
	}
	if ($paramType eq 'multiplestaticplaylists') {
		my $selectedStaticPlaylists = $client->pluginData('selected_staticplaylists') || [];
		main::DEBUGLOG && $log->is_debug && $log->debug('selectedStaticPlaylists = '.Data::Dump::dump($selectedStaticPlaylists));
		my @IDsSelectedStaticPlaylists = ();
		if (scalar (@{$selectedStaticPlaylists}) > 0) {
			foreach my $staticPlaylistID (@{$selectedStaticPlaylists}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Selected static playlist: '.Slim::Schema->resultset('Playlist')->single( {'id' => $staticPlaylistID })->name.' (ID: '.$staticPlaylistID.')');
				push @IDsSelectedStaticPlaylists, $staticPlaylistID;
			}
		}
		$multipleSelectionString = join (',', @IDsSelectedStaticPlaylists);
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('multipleSelectionString = '.Data::Dump::dump($multipleSelectionString));
	return $multipleSelectionString;
}


## virtual libraries ##

sub getVirtualLibraries {
	my @items;
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	main::DEBUGLOG && $log->is_debug && $log->debug('ALL virtual libraries: '.Data::Dump::dump($libraries));

	while (my ($k, $v) = each %{$libraries}) {
		my $count = Slim::Music::VirtualLibraries->getTrackCount($k);
		my $name = Slim::Music::VirtualLibraries->getNameForId($k);
		my $displayName = Slim::Utils::Unicode::utf8decode($name, 'utf8').' ('.Slim::Utils::Misc::delimitThousands($count).($count == 1 ? ' '.string("PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_TRACK") : ' '.string("PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_TRACKS")).')';
		main::DEBUGLOG && $log->is_debug && $log->debug("VL: ".$displayName);

		push @items, {
			name => $displayName,
			sortName => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
			value => qq('$k'),
			id => qq('$k'),
		};
	}
	if (scalar(@items) == 0) {
		push @items, {
			name => string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_COMPLETELIB'),
			sortName => 'complete library',
			value => qq(''),
			id => qq(''),
		};
	}

	if (scalar(@items) > 1) {
		@items = sort {lc($a->{sortName}) cmp lc($b->{sortName})} @items;
	}
	return \@items;
}

sub checkForLimitingVL {
	my ($client, $parameters, $playlist, $source) = @_;

	## get VLID for VLs to limit the displayed genres, decades or years to those in the VL
	my $limitingParamSelVLID;

	# check fixed playlist parameters first
	my $playlistVLnames = $playlist->{'playlistvirtuallibrarynames'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistVLnames = '.Data::Dump::dump($playlistVLnames));
	my $playlistVLids = $playlist->{'playlistvirtuallibraryids'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistVLids = '.Data::Dump::dump($playlistVLnames));
	if (keys %{$playlistVLnames}) {
		$limitingParamSelVLID = Slim::Music::VirtualLibraries->getIdForName($playlistVLnames->{'1'});
	}
	if (keys %{$playlistVLids}) {
		$limitingParamSelVLID = Slim::Music::VirtualLibraries->getRealId($playlistVLids->{'1'});
	}

	# check for user-input VL
	if ($source) {
		# jive & IP3k / VFD
		my $playlistParams = $playlist->{'parameters'};
		my $playlistVLParamID;
		foreach (keys %{$playlistParams}) {
		 $playlistVLParamID = $_ if $playlistParams->{$_}->{'type'} && $playlistParams->{$_}->{'type'} eq 'virtuallibrary';
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('playlistVLParamID = '.Data::Dump::dump($playlistVLParamID));

		if ($source == 1) { # jive
			$limitingParamSelVLID = $parameters->{$playlistVLParamID} if $playlistVLParamID && keys %{$parameters} > 0;
		} elsif ($source == 2) { # IP3k / VFD
			$limitingParamSelVLID = $client->modeParam('dynamicplaylist_parameter_'.$playlistVLParamID)->{'value'} if $playlistVLParamID && defined($client->modeParam('dynamicplaylist_parameter_'.$playlistVLParamID));
		}
	} else {
		# web
		foreach (@{$parameters}) {
			if ($_->{parameter}->{type} && $_->{parameter}->{type} eq 'virtuallibrary') {
				$limitingParamSelVLID = $_->{value};
			}
		}
	}
	$limitingParamSelVLID =~ s|^\`(.*)\`$|$1|s or
	$limitingParamSelVLID =~ s|^\"(.*)\"$|$1|s or
	$limitingParamSelVLID =~ s|^\'(.*)\'$|$1|s if $limitingParamSelVLID;
	main::DEBUGLOG && $log->is_debug && $log->debug('limitingParamSelVLID = '.Data::Dump::dump($limitingParamSelVLID));

	return $limitingParamSelVLID;
}


## preselection ##

sub registerPreselectionMenu {
	my ($client, $url, $obj, $remoteMeta, $tags, $filter, $objectType) = @_;
	$tags ||= {};

	unless ($objectType && ($objectType eq 'artist' || $objectType eq 'album')) {
		return undef;
	}
	return undef if $objectType eq 'album' && defined($filter->{'work_id'}); # no context menu for works

	my $objectName = $objectType eq 'artist' ? $obj->name : $obj->title;
	my $objectID = $obj->id;
	my $artistName = (Slim::Schema->find('Contributor', $obj->contributor->id))->name if $objectType eq 'album';
	my $jive = {};

	if ($tags->{menuMode}) {
		my $actions = {
			go => {
				player => 0,
				cmd => ['dynamicplaylist', 'preselect'],
				params => {
					'objectid' => $objectID,
					'objecttype' => $objectType,
					'objectname' => $objectName,
					'artistname' => $artistName,
				},
			},
		};
		$jive->{actions} = $actions;
	}

	return {
		type => 'text',
		jive => $jive,
		objecttype => $objectType,
		objectid => $objectID,
		objectname => $objectName,
		artistname => $artistName,
		action => 2,
		name => $objectType eq 'artist' ? $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTARTISTS') : $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTALBUMS'),
		favorites => 0,
		web => {
			'type' => 'htmltemplate',
			'value' => 'plugins/DynamicPlaylists4/dynamicplaylist_preselectionlink.html'
		},
	};
}

sub _preselectionMenuWeb {
	my ($client, $params) = @_;
	my $objectType = $params->{'objecttype'};
	my $objectId = $params->{'objectid'};
	my $objectName = $params->{'objectname'};
	my $artistName = $params->{'artistname'};
	my $action = $params->{'action'};

	my $listName = $objectType eq 'artist' ? 'cachedArtists' : 'cachedAlbums';
	my $preselectionList = $client->pluginData($listName) || {};

	if ($action && $action == 1) {
		delete $preselectionList->{$objectId};
		$client->pluginData($listName, $preselectionList);
	} elsif ($action && $action == 2) {
		$preselectionList->{$objectId}->{'name'} = $objectName if $objectName;
		$preselectionList->{$objectId}->{'id'} = $objectId;
		$preselectionList->{$objectId}->{'artistname'} = $artistName if $objectType eq 'album' && $artistName;
		$client->pluginData($listName, $preselectionList);
	} elsif ($action && $action == 3) {
		$client->pluginData($listName, {});
	}
	$preselectionList = $client->pluginData($listName) || {};
	main::DEBUGLOG && $log->is_debug && $log->debug("pluginData '$listName' (web) = ".Data::Dump::dump($preselectionList));
	$params->{'preselitemcount'} = keys %{$preselectionList};
	$params->{'pluginDynamicPlaylists4preselectionList'} = $preselectionList if (keys %{$preselectionList} > 0);
	$params->{'action'} = ();
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlaylists4/dynamicplaylist_preselectionmenu.html', $params);
}

sub _preselectionMenuJive {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request = '.Data::Dump::dump($request));
	my $client = $request->client();
	my $materialCaller = 1 if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->{'_source'}) && $request->{'_source'} eq 'JSONRPC');

	if (!$request->isQuery([['dynamicplaylist'], ['preselect']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting preselectionMenuJiveHandler');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting preselectionMenuJiveHandler');
		return;
	}

	my $params = $request->getParamsCopy();
	my $iPengCaller = 1 if $params->{'userInterfaceIdiom'} && $params->{'userInterfaceIdiom'} eq 'iPeng';
	my $objectType = $params->{'objecttype'};
	my $objectID = $params->{'objectid'};
	my $objectName = $params->{'objectname'};
	my $artistName = $params->{'artistname'};
	my $removeID = $params->{'removeid'};

	main::DEBUGLOG && $log->is_debug && $log->debug('objectType = '.Data::Dump::dump($objectType).'objectID = '.Data::Dump::dump($objectID).'removeID = '.Data::Dump::dump($removeID).'artistName = '.Data::Dump::dump($artistName));
	my $listName = $objectType eq 'artist' ? 'cachedArtists' : 'cachedAlbums';
	my $preselectionList = $client->pluginData($listName) || {};

	if ($removeID) {
		if ($removeID eq 'clearlist') {
			$client->pluginData($listName, {});
		} else {
			delete $preselectionList->{$removeID};
			$client->pluginData($listName, $preselectionList);
		}
	}
	if ($objectID) {
		$preselectionList->{$objectID}->{'name'} = $objectName if $objectName;
		$preselectionList->{$objectID}->{'id'} = $objectID;
		$preselectionList->{$objectID}->{'artistname'} = $artistName if $objectType eq 'album' && $artistName;
		$client->pluginData($listName, $preselectionList);
	}

	$preselectionList = $client->pluginData($listName) || {};

	main::DEBUGLOG && $log->is_debug && $log->debug("pluginData $listName (jive) = ".Data::Dump::dump($preselectionList));
	my $cnt = 0;
	if (keys %{$preselectionList} > 0) {
		$request->addResultLoop('item_loop', $cnt, 'type', 'text');
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'text', $objectType eq 'artist' ? $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_REMOVEINFO_ARTIST') : $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_REMOVEINFO_ALBUM'));
		$cnt++;

		if (keys %{$preselectionList} > 1) {
			my %itemParams = (
				'objecttype' => $objectType,
				'removeid' => 'clearlist',
			);

			my $actions = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'preselect'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};

			$request->addResultLoop('item_loop', $cnt, 'type', 'text');
			$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'parent');
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_CLEAR_LIST'));
			$cnt++;
		}

		foreach my $itemID (sort { $preselectionList->{$a}->{'name'} cmp $preselectionList->{$b}->{'name'}; } keys %{$preselectionList}) {
			my $selectedItem = $preselectionList->{$itemID};
			my $itemName = $selectedItem->{'name'};
			my $itemArtistName = $selectedItem->{'artistname'};
			my $text = $objectType eq 'artist' ? $itemName : $itemName.'  -- '.$client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_INFO_BY').'  '.$itemArtistName;
			my %itemParams = (
				'objecttype' => $objectType,
				'removeid' => $itemID,
			);

			my $actions = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'preselect'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'type', 'text');
			if ($objectID && $itemID == $objectID) {
				$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'parent');
			} else {
				$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'refresh');
			}
			$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $cnt, 'text', $text);
			$cnt++;
		}
	} else {
		$request->addResultLoop('item_loop', $cnt, 'type', 'text');
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_NONE'));
		$cnt++;
	}
	# Material always displays last selection as window title. Add correct window title as textarea
	my $windowTitle = $objectType eq 'artist' ? $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_CACHED_ARTISTS_LIST') : $client->string('PLUGIN_DYNAMICPLAYLISTS4_PRESELECTION_CACHED_ALBUMS_LIST');
	if ($materialCaller || $iPengCaller) {
		$request->addResult('window', {textarea => $windowTitle});
	} else {
		$request->addResult('window', {text => $windowTitle});
	}
	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);
	$request->setStatusDone();
}


## dpl queue ##

sub _dplQueueMenuWeb {
	my ($client, $params) = @_;
	my $objecturlmd5 = $params->{'objecturlmd5'};
	my $action = $params->{'action'};
	my $move = $params->{'move'};

	my $dplQueue = $client->pluginData('dplQueue') || [];

	if ($action && $action == 1) {
		@{$dplQueue} = grep {$_->{'urlmd5'} ne $objecturlmd5} @{$dplQueue};
		$client->pluginData('dplQueue', $dplQueue);
	} elsif ($action && $action == 2) {
		$client->pluginData('dplQueue', []);
	}

	if ($move) {
		my $index;
		for my $i (keys @{$dplQueue}) {
			if (@{$dplQueue}[$i]->{'urlmd5'} eq $objecturlmd5) {
				$index = $i;
				last;
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('current index = '.Data::Dump::dump($index));
		main::DEBUGLOG && $log->is_debug && $log->debug('indexChange = '.($move == 1 ? 'down' : 'up'));

		my $newIndex = $index + $move;
		$newIndex = 0 if $newIndex < 0;
		$newIndex = (scalar @{$dplQueue} - 1) if $newIndex > (scalar @{$dplQueue} - 1);
		main::DEBUGLOG && $log->is_debug && $log->debug('new index = '.$newIndex);
		splice(@{$dplQueue}, $newIndex, 0, splice(@{$dplQueue}, $index, 1));
		$client->pluginData('dplQueue', $dplQueue);
	}

	$dplQueue = $client->pluginData('dplQueue') || [];
	main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'dplQueue' (web) = ".Data::Dump::dump($dplQueue));
	$params->{'dplqueueitemcount'} = scalar @{$dplQueue};
	$params->{'pluginDynamicPlaylists4dplQueue'} = $dplQueue if (scalar @{$dplQueue} > 0);
	$params->{'action'} = ();
	return Slim::Web::HTTP::filltemplatefile('plugins/DynamicPlaylists4/dynamicplaylist_dplqueue.html', $params);
}

sub _queueMenuJive {
	my $request = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('request = '.Data::Dump::dump($request));
	my $client = $request->client();
	my $materialCaller = 1 if (defined($request->{'_connectionid'}) && $request->{'_connectionid'} =~ 'Slim::Web::HTTP::ClientConn' && defined($request->{'_source'}) && $request->{'_source'} eq 'JSONRPC');

	if (!$request->isQuery([['dynamicplaylist'], ['queuelist']])) {
		$log->warn('Incorrect command');
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _queueMenuJive');
		return;
	}
	if (!defined $client) {
		$log->warn('Client required');
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting _queueMenuJive');
		return;
	}

	my $params = $request->getParamsCopy();
	my $iPengCaller = 1 if $params->{'userInterfaceIdiom'} && $params->{'userInterfaceIdiom'} eq 'iPeng';
	my $removeURLmd5 = $params->{'removeurlmd5'};

	main::DEBUGLOG && $log->is_debug && $log->debug('removeURLmd5 = '.Data::Dump::dump($removeURLmd5));
	my $dplQueue = $client->pluginData('dplQueue') || [];

	if ($removeURLmd5) {
		if ($removeURLmd5 eq 'clearlist') {
			$client->pluginData('dplQueue', []);
		} else {
			@{$dplQueue} = grep {$_->{'urlmd5'} ne $removeURLmd5} @{$dplQueue};
			$client->pluginData('dplQueue', $dplQueue);
		}
	}

	$dplQueue = $client->pluginData('dplQueue') || [];

	main::DEBUGLOG && $log->is_debug && $log->debug('pluginData dplQueue (jive) = '.Data::Dump::dump($dplQueue));
	my $cnt = 0;
	if (scalar @{$dplQueue} > 0) {
		$request->addResultLoop('item_loop', $cnt, 'type', 'text');
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_DPLQUEUE_REMOVEINFO'));
		$cnt++;

		if (scalar @{$dplQueue} > 1) {
			my %itemParams = (
				'removeurlmd5' => 'clearlist',
			);

			my $actions = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'queuelist'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};

			$request->addResultLoop('item_loop', $cnt, 'type', 'text');
			$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'parent');
			$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_DPLQUEUE_CLEAR_QUEUE'));
			$cnt++;
		}

		foreach my $queuedDPL (@{$dplQueue}) {
			my $text = $queuedDPL->{'title'};
			my %itemParams = (
				'removeurlmd5' => $queuedDPL->{'urlmd5'},
			);

			my $actions = {
				'go' => {
					'cmd' => ['dynamicplaylist', 'queuelist'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};
			$request->addResultLoop('item_loop', $cnt, 'type', 'text');
			if (scalar @{$dplQueue} == 1) {
				$request->addResultLoop('item_loop', $cnt, 'nextWindow', $materialCaller ? 'home' : 'parent');
			} else {
				$request->addResultLoop('item_loop', $cnt, 'nextWindow', 'refresh');
			}
			$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
			$request->addResultLoop('item_loop', $cnt, 'text', $text);
			$cnt++;
		}
	} else {
		$request->addResultLoop('item_loop', $cnt, 'type', 'text');
		$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		$request->addResultLoop('item_loop', $cnt, 'text', $client->string('PLUGIN_DYNAMICPLAYLISTS4_DPLQUEUE_NONE'));
		$cnt++;
	}

	$request->addResult('offset', 0);
	$request->addResult('count', $cnt);
	$request->setStatusDone();
}

sub _queuePlaylist {
	my ($client, $url, $playlist) = @_;

	my $dplQueue = $client->pluginData('dplQueue') || [];
	if (scalar @{$dplQueue} >= 5) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Not adding dynamic playlist to queue. Max. number of queued dynamic playlist = 5');
	} else {
		# check if already in queue
		my $alreadyQueued = 0;
		if (scalar @{$dplQueue} > 0) {
			foreach (@{$dplQueue}) {
				if ($_->{'urlmd5'} eq md5_hex($url)) {
					$alreadyQueued = 1;
				}
			}
		}
		if ($alreadyQueued) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Not adding dynamic playlist to queue. Already in queue.');
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Adding this url to dynamic playlist queue: '.$url);
			push @{$dplQueue}, {'title' => $playlist->{'name'}, 'url' => $url, 'urlmd5' => md5_hex($url)};
			$client->pluginData('dplQueue', $dplQueue);
			main::DEBUGLOG && $log->is_debug && $log->debug('Current dplQueue = '.Data::Dump::dump($dplQueue));
		}
	}
}



### get local dynamic playlists
### built-in + custom/user-provided + saved static playlists

sub getDynamicPlaylists {
	my $client = shift;
	my $playLists = ();
	my %result = ();

	if ($prefs->get('includesavedplaylists')) {
		my @result;
		for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {
			push @result, $playlist;
		}
		$playLists = \@result;

		main::DEBUGLOG && $log->is_debug && $log->debug('Got: '.scalar(@{$playLists}).' number of saved static playlists');
		my $playlistDir = $serverPrefs->get('playlistdir');
		if ($playlistDir) {
			$playlistDir = Slim::Utils::Misc::fileURLFromPath($playlistDir);
		}
		foreach my $playlist (@{$playLists}) {
			my $playlistid = 'dplstaticpl_'.sha1_base64($playlist->url);
			my $id = $playlist->id;
			my $name = $playlist->title;
			my $playlisturl;
			$playlisturl = 'clixmlbrowser/clicmd=browselibrary+items&linktitle=SAVED_PLAYLISTS&mode=playlistTracks&playlist_id='.$playlist->id;

			my %currentResult = (
				'id' => $id,
				'name' => $name,
				'playlistsortname' => $name,
				'playlistcategory' => 'static LMS playlists',
				'usecache' => 1,
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
			my ($playlistid, $playlistsortname);
			my $url = '';
			if ($current->{'defaultplaylist'}) {
				$playlistid = 'dpldefault_'.$playlist;
				$playlistsortname = '0000001_'.$playlistid;
			}
			if ($current->{'customplaylist'}) {
				$playlistid = 'dplusercustom_'.$playlist;
				if ((!$current->{'playlistcategory'} || $current->{'playlistcategory'} eq '') && $prefs->get('unclassified_sortbyid')) {
					$playlistsortname = '0000002_dplusercustom_'.$playlistid;
				} else {
					$playlistsortname = '0000002_dplusercustom_'.$current->{'name'};
				}
			}
			if ($current->{'dplcplaylist'}) {
				$playlistid = 'dplccustom_'.$playlist;
				if ((!$current->{'playlistcategory'} || $current->{'playlistcategory'} eq '') && $prefs->get('unclassified_sortbyid')) {
					$playlistsortname = '0000003_dplccustom_'.$playlistid;
				} else {
					$playlistsortname = '0000003_dplccustom_'.$current->{'name'};
				}
				$url = "plugins/DynamicPlaylistCreator/webpagemethods_edititem.html?item=".escape($playlist)."&redirect=1"
			}
			my %currentResult = (
				'id' => $playlist,
				'name' => $current->{'name'},
				'playlistsortname' => $playlistsortname,
				'menulisttype' => $current->{'menulisttype'},
				'playlistcategory' => $current->{'playlistcategory'},
				'minlmsversion' => $current->{'minlmsversion'},
				'apcplaylist' => $current->{'apcplaylist'},
				'dplcplaylist' => $current->{'dplcplaylist'},
				'playlistapcdupe' => $current->{'playlistapcdupe'},
				'playlisttrackorder' => $current->{'playlisttrackorder'},
				'playlistlimitoption' => $current->{'playlistlimitoption'},
				'playlistvirtuallibrarynames' => $current->{'playlistvirtuallibrarynames'},
				'playlistvirtuallibraryids' => $current->{'playlistvirtuallibraryids'},
				'usecache' => $current->{'usecache'},
				'repeat' => $current->{'repeat'},
				'url' => $url
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
				$currentResult{'startactions'} = $current->{'startactions'};
			}
			if (defined($current->{'stopactions'})) {
				$currentResult{'stopactions'} = $current->{'stopactions'};
			}
			if (defined($current->{'contextmenulist'})) {
				$currentResult{'contextmenulist'} = $current->{'contextmenulist'};
			}
			if ($current->{'groups'} && scalar($current->{'groups'})>0) {
				$currentResult{'groups'} = $current->{'groups'};
			}
			$result{$playlistid} = \%currentResult;
		}
	}

	return \%result;
}

sub getNextDynamicPlaylistTracks {
	my ($client, $dynamicplaylist, $limit, $offset, $parameters) = @_;
	my @idList = ();
	my $dynamicplaylistID = $dynamicplaylist->{'dynamicplaylistid'};
	my $localDynamicPlaylistID = $dynamicplaylist->{'id'};
	my $dbh = Slim::Schema->dbh;

	if ((starts_with($dynamicplaylistID, 'dpldefault_') == 0) || (starts_with($dynamicplaylistID, 'dplusercustom_') == 0) || (starts_with($dynamicplaylistID, 'dplccustom_') == 0)) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting tracks for dynamic playlist: \''.$dynamicplaylist->{'name'}.'\' with ID: '.$dynamicplaylist->{'id'});
		main::DEBUGLOG && $log->is_debug && $log->debug("limit = $limit, offset = $offset, parameters = ".Data::Dump::dump($parameters));

		my $localDynamicPlaylistSQLstatement = $localDynamicPlaylists->{$localDynamicPlaylistID}->{'sql'};
		my $sqlstatement = replaceParametersInSQL($localDynamicPlaylistSQLstatement, $parameters);
		my $predefinedParameters = getInternalParameters($client, $dynamicplaylist, $limit, $offset);
		$sqlstatement = replaceParametersInSQL($sqlstatement, $predefinedParameters, 'Playlist');
		main::DEBUGLOG && $log->is_debug && $log->debug('sqlstatement = '.$sqlstatement);

		my @idList = ();
		my %idListCompleteInfo = ();
		my ($noPrimaryArtistsCol, $noPlayCountCol) = 0;

		my $i = 1;
		for my $sql (split(/[\n\r]/, $sqlstatement)) {
			my $sqlExecTime = time();
			eval {
				my $sth = $dbh->prepare($sql);
				$sth->execute() or do {
					$sql = undef;
				};
				if ($sql =~ /^\(*select+/oi) {
					my ($id, $primary_artist, $playCount);
					$sth->bind_col(1, \$id);
					eval {
						unless ($noPrimaryArtistsCol) {
							$sth->bind_col(2, \$primary_artist);
						}
					};
					if ($@) {
						$noPrimaryArtistsCol = 1;
					}
					eval {
						unless ($noPlayCountCol) {
							$sth->bind_col(3, \$playCount);
						}
					};
					if ($@) {
						$noPlayCountCol = 1;
					}

					my @trackIDs = ();
					while ($sth->fetch()) {
						push @trackIDs, $id;
						$idListCompleteInfo{$id}{'id'} = $id;
						$idListCompleteInfo{$id}{'primary_artist'} = $primary_artist if !$noPrimaryArtistsCol && $primary_artist;
						$idListCompleteInfo{$id}{'playCount'} = $playCount if !$noPlayCountCol && $playCount;
					}
					push @idList, @trackIDs;
				}
				$sth->finish();
			};

			#main::DEBUGLOG && $log->is_debug && $log->debug('idListCompleteInfo = '.Data::Dump::dump(\%idListCompleteInfo));
			if ($@) {
				$log->error("Database error: $DBI::errstr\n$@");
				return 'error';
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("sql statement $i: exec time = ".(time() - $sqlExecTime).' secs');
		}
		main::DEBUGLOG && $log->is_debug && $log->debug('Got '.scalar(@idList).' track IDs');
		#main::DEBUGLOG && $log->is_debug && $log->debug('idList = '.Data::Dump::dump(\@idList));

		return \@idList, \%idListCompleteInfo;

	} else {

		## static playlists ##
		main::DEBUGLOG && $log->is_debug && $log->debug('Getting track IDs for static playlist: \''.$dynamicplaylist->{'name'}.'\' with ID: '.$dynamicplaylist->{'id'}." -- limit = $limit, offset = $offset");
		my $playlist = objectForId('playlist', $dynamicplaylist->{'id'});
		my @trackIDs = ();
		my %tracksCompleteInfo;

		my $iterator = $playlist->tracks;
		my @tracks = $iterator->slice(0, $iterator->count);

		for my $track (@tracks) {
			my $trackID = $track->id;
			my $artistID;

			my $isRemoteTrack = Slim::Music::Info::isRemoteURL($track->url);
			main::DEBUGLOG && $log->is_debug && $log->debug('isRemoteURL = '.Data::Dump::dump($isRemoteTrack));
			if ($isRemoteTrack && $isRemoteTrack == 1) {
				$trackID = undef;
				my ($trackTitle, $extID);
				my $urlmd5 = $track->urlmd5 || md5_hex($track->url);
				my $dbh = Slim::Schema->dbh;
				my $sqlstatement = "select tracks.title, tracks.id, tracks.primary_artist, tracks.extid from tracks where tracks.urlmd5 = \"$urlmd5\"";
				eval {
					my $sth = $dbh->prepare($sqlstatement);
					$sth->execute() or do {$sqlstatement = undef;};
					$sth->bind_columns(undef, \$trackTitle, \$trackID, \$artistID, \$extID);
					$sth->fetchrow;
					$sth->finish();
				};
				if ($@) {
					main::DEBUGLOG && $log->is_debug && $log->debug("error: $@");
					next;
				}
				main::DEBUGLOG && $log->is_debug && $log->debug('track ID = '.Data::Dump::dump($trackID).' ##### extID = '.Data::Dump::dump($extID).' ##### track url = '.$track->url);
				next if (!$trackID || !$extID);
				main::DEBUGLOG && $log->is_debug && $log->debug("Remote track is part of LMS library: ".$trackTitle);
			} else {
				$artistID = $track->artistid;
			}

			push @trackIDs, $trackID;
			$tracksCompleteInfo{$track->id}{'id'} = $trackID;
			$tracksCompleteInfo{$track->id}{'primary_artist'} = $artistID if $artistID;
		}

		main::DEBUGLOG && $log->is_debug && $log->debug('Got '.scalar(@trackIDs).' track IDs');
		return \@trackIDs, \%tracksCompleteInfo;
	}
}

sub getInternalParameters {
	my ($client, $dynamicplaylist, $limit, $offset) = @_;
	my $dbh = Slim::Schema->dbh;

	my $playlistLimitOption = $dynamicplaylist->{'playlistlimitoption'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistLimitOption = '.Data::Dump::dump($playlistLimitOption));
	my $playlistVLnames = $dynamicplaylist->{'playlistvirtuallibrarynames'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistVLnames = '.Data::Dump::dump($playlistVLnames));
	my $playlistVLids = $dynamicplaylist->{'playlistvirtuallibraryids'};
	main::DEBUGLOG && $log->is_debug && $log->debug('playlistVLids = '.Data::Dump::dump($playlistVLnames));

	my $predefinedParameters = ();
	my %player = (
		'id' => 'Player',
		'value' => $dbh->quote($client->id),
	);
	my %offsetParameter = (
		'id' => 'Offset',
		'value' => $offset
	);
	if (!defined($limit) || ($playlistLimitOption && $playlistLimitOption eq 'unlimited')) {$limit = -1};
	my %limitParameter = (
		'id' => 'Limit',
		'value' => $limit
	);
	my %VAstring = (
		'id' => 'VariousArtistsString',
		'value' => $dbh->quote($serverPrefs->get('variousArtistsString')) || 'Various Artists',
	);
	my %VAid = (
		'id' => 'VariousArtistsID',
		'value' => Slim::Schema->variousArtistsObject->id,
	);
	my %minTrackDuration = (
		'id' => 'TrackMinDuration',
		'value' => $prefs->get('song_min_duration'),
	);
	my %topratedMinRating = (
		'id' => 'TopRatedMinRating',
		'value' => $prefs->get('toprated_min_rating'),
	);
	my %periodPlayedLongAgo = (
		'id' => 'PeriodPlayedLongAgo',
		'value' => $prefs->get('period_playedlongago'),
	);
	my %minArtistTracks = (
		'id' => 'MinArtistTracks',
		'value' => $prefs->get('minartisttracks'),
	);
	my %minAlbumTracks = (
		'id' => 'MinAlbumTracks',
		'value' => $prefs->get('minalbumtracks'),
	);
	my %excludedGenres = (
		'id' => 'ExcludedGenres',
		'value' => getExcludedGenreList(),
	);
	my %currentVirtualLibraryForClient = (
		'id' => 'CurrentVirtualLibraryForClient',
		'value' => $dbh->quote(Slim::Music::VirtualLibraries->getLibraryIdForClient($client)),
	);

	if (keys %{$playlistVLnames}) {
		foreach my $thisKey (sort keys %{$playlistVLnames}) {
			my %thisVirtualLibraryNameItem = (
				'id' => 'VirtualLibraryName'.$thisKey,
				'value' => $dbh->quote(Slim::Music::VirtualLibraries->getIdForName($playlistVLnames->{$thisKey})),
			);
			$predefinedParameters->{'PlaylistVirtualLibraryName'.$thisKey} = \%thisVirtualLibraryNameItem;
		}
	}
	if (keys %{$playlistVLids}) {
		foreach my $thisKey (sort keys %{$playlistVLids}) {
			my %thisVirtualLibraryIDItem = (
				'id' => 'VirtualLibraryID'.$thisKey,
				'value' => $dbh->quote(Slim::Music::VirtualLibraries->getRealId($playlistVLids->{$thisKey})),
			);
			$predefinedParameters->{'PlaylistVirtualLibraryID'.$thisKey} = \%thisVirtualLibraryIDItem;
		}
	}

	my $preselectionListArtists = $client->pluginData('cachedArtists') || {};
	my $preselectionListAlbums = $client->pluginData('cachedAlbums') || {};
	main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedArtists' = ".Data::Dump::dump($preselectionListArtists));
	main::DEBUGLOG && $log->is_debug && $log->debug("pluginData 'cachedAlbums' = ".Data::Dump::dump($preselectionListAlbums));
	if (keys %{$preselectionListArtists} > 0) {
		my %preselArtists= (
			'id' => 'PreselectedArtists',
			'value' => join(',', keys %{$preselectionListArtists}),
		);
		$predefinedParameters->{'PlaylistPreselectedArtists'} = \%preselArtists;
	}
	if (keys %{$preselectionListAlbums} > 0) {
		my %preselAlbums = (
			'id' => 'PreselectedAlbums',
			'value' => join(',', keys %{$preselectionListAlbums}),
		);
		$predefinedParameters->{'PlaylistPreselectedAlbums'} = \%preselAlbums;
	}

	$predefinedParameters->{'PlaylistPlayer'} = \%player;
	$predefinedParameters->{'PlaylistOffset'} = \%offsetParameter;
	$predefinedParameters->{'PlaylistLimit'} = \%limitParameter;
	$predefinedParameters->{'PlaylistVariousArtistsString'} = \%VAstring;
	$predefinedParameters->{'PlaylistVariousArtistsID'} = \%VAid;
	$predefinedParameters->{'PlaylistTrackMinDuration'} = \%minTrackDuration;
	$predefinedParameters->{'PlaylistTopRatedMinRating'} = \%topratedMinRating;
	$predefinedParameters->{'PlaylistPeriodPlayedLongAgo'} = \%periodPlayedLongAgo;
	$predefinedParameters->{'PlaylistMinArtistTracks'} = \%minArtistTracks;
	$predefinedParameters->{'PlaylistMinAlbumTracks'} = \%minAlbumTracks;
	$predefinedParameters->{'PlaylistExcludedGenres'} = \%excludedGenres;
	$predefinedParameters->{'PlaylistCurrentVirtualLibraryForClient'} = \%currentVirtualLibraryForClient;
	return \%{$predefinedParameters};
}

sub replaceParametersInSQL {
	my ($sql, $parameters, $parameterType) = @_;
	if (!defined($parameterType)) {
		$parameterType = 'PlaylistParameter';
	}

	if (defined($parameters)) {
		foreach my $key (keys %{$parameters}) {
			my $parameter = $parameters->{$key};
			my $value = $parameter->{'value'};
			if (!defined($value)) {
				$value = '';
			}
			my $parameterid = "\'$parameterType".$parameter->{'id'}."\'";
			main::DEBUGLOG && $log->is_debug && $log->debug('Replacing '.$parameterid.' with '.$value);
			$sql =~ s/$parameterid/$value/g;
		}
	}
	return $sql;
}



### read + parse built-in + custom dynamic playlist FILES ###

sub readParseLocalDynamicPlaylists {
	my $pluginPlaylistFolder = $prefs->get('pluginplaylistfolder');
	my $customPlaylistFolder = $prefs->get('customplaylistfolder');
	my $dplc_customPLfolder = (preferences('plugin.dynamicplaylistcreator')->get('customplaylistfolder') || '') if $dplc_enabled;
	my $localCustomDynamicPlaylists;

	my @localDefDirs = ($customPlaylistFolder);
	if (!$localBuiltinDynamicPlaylists) {
		push @localDefDirs, $pluginPlaylistFolder;
		main::DEBUGLOG && $log->is_debug && $log->debug('Built-in dpls not parsed yet. Including them in search.');
	}

	if ($dplc_enabled && $dplc_customPLfolder) {
		push @localDefDirs, $dplc_customPLfolder;
		main::DEBUGLOG && $log->is_debug && $log->debug("Including DynamicPlaylistCreator folder '$dplc_customPLfolder' in search.");
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Searching for dynamic playlist definitions in local directories');

	for my $localDefDir (@localDefDirs) {
		if (!defined $localDefDir || !-d $localDefDir) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Directory is undefined or does not exist - skipping scan for dpl definitions in: '.Data::Dump::dump($localDefDir));
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Checking dir: '.$localDefDir);
			my $fileExtension = "\\.sql\$";
			my @dircontents = Slim::Utils::Misc::readDirectory($localDefDir, "sql", 'dorecursive');
			main::DEBUGLOG && $log->is_debug && $log->debug("directory contents for dir '$localDefDir': ".Data::Dump::dump(\@dircontents));

			for my $item (@dircontents) {
				next unless $item =~ /$fileExtension$/;
				next if -d $item;
				my $content = eval {read_file($item)};
				my $plDirName = dirname($item);
				$item = basename($item);
				if ($content) {
					# If necessary convert the file data to utf8
					my $encoding = Slim::Utils::Unicode::encodingFromString($content);
					if ($encoding ne 'utf8') {
						$content = Slim::Utils::Unicode::latin1toUTF8($content);
						$content = Slim::Utils::Unicode::utf8on($content);
						main::DEBUGLOG && $log->is_debug && $log->debug("Loading $item and converting from latin1");
					} else {
						$content = Slim::Utils::Unicode::utf8decode($content,'utf8');
						main::DEBUGLOG && $log->is_debug && $log->debug("Loading $item without conversion with encoding ".$encoding);
					}

					my $parsedContent;
					if ($localDefDir eq $pluginPlaylistFolder) {
						if ($plDirName =~ /extplugin_APC/) {
							next unless $apc_enabled;
						}
						$parsedContent = parseContent($item, $content, undef, 'parseStrings');
						$parsedContent->{'defaultplaylist'} = 1;
						$parsedContent->{'playlistsortname'} = ''.$parsedContent->{'name'};
						if (($plDirName =~ /extplugin_APC/) && $apc_enabled) {
								$parsedContent->{'apcplaylist'} = 1;
						}
						$localBuiltinDynamicPlaylists->{$parsedContent->{'id'}} = $parsedContent;
					}
					if ($localDefDir eq $customPlaylistFolder) {
						$parsedContent = parseContent($item, $content);
						$parsedContent->{'customplaylist'} = 1;
						$localCustomDynamicPlaylists->{$parsedContent->{'id'}} = $parsedContent;
					}
					if ($dplc_customPLfolder && $localDefDir eq $dplc_customPLfolder) {
						$parsedContent = parseContent($item, $content, undef, 'parseStrings');
						$parsedContent->{'dplcplaylist'} = 1;
						$localCustomDynamicPlaylists->{$parsedContent->{'id'}} = $parsedContent;
					}
				}
			}
		}
	}
	if (scalar keys %{$localCustomDynamicPlaylists} > 0) {
		%{$localDynamicPlaylists} = (%{$localBuiltinDynamicPlaylists}, %{$localCustomDynamicPlaylists});
	} else {
		$localDynamicPlaylists = $localBuiltinDynamicPlaylists;
	}
	#main::DEBUGLOG && $log->is_debug && $log->debug('localDynamicPlaylists = '.Data::Dump::dump($localDynamicPlaylists));
}

sub parseContent {
	my ($item, $content, $items, $parseStrings) = @_;

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
		my $playlistLMSminVersion = undef;
		my $playlistCategory = '';
		my $playlistAPCdupe = '';
		my $playlistTrackOrder = '';
		my $playlistLimitOption = '';
		my $playlistVLnames = ();
		my $playlistVLids = ();
		my %startactions = ();
		my %stopactions = ();
		my $useCache;
		my $repeat;

		for my $line (@playlistDataArray) {
			if (!$name) {
				$name = $parseStrings ? parsePlaylistName($line, 'parseStrings') : parsePlaylistName($line);
				if (!$name) {
					my $file = $item;
					my $fileExtension = "\\.sql\$";
					$item =~ s/$fileExtension$//;
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
			my $parameter = $parseStrings ? parseParameter($line, 'parseStrings') : parseParameter($line);
			my $action = parseAction($line);
			my $listType = parseMenuListType($line);
			my $category = parseCategory($line);
			my $LMSminVersion = parseLMSminVersion($line);
			my $APCdupe = parseAPCdupe($line);
			my $trackOrder = parseTrackOrder($line);
			my $limitOption = parseLimitOption($line);
			my $VLnameItem = parseVirtualLibraryName($line);
			my $VLidItem = parseVirtualLibraryID($line);
			my $cached = parseUseCache($line);
			my $repeatIndef = parseRepeat($line);

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
			if ($LMSminVersion) {
				$playlistLMSminVersion = $LMSminVersion;
			}
			if ($APCdupe) {
				$playlistAPCdupe = $APCdupe;
			}
			if ($trackOrder) {
				$playlistTrackOrder = $trackOrder;
			}
			if ($limitOption) {
				$playlistLimitOption = $limitOption;
			}
			if (keys %{$VLnameItem}) {
				$$playlistVLnames{$VLnameItem->{'number'}} = $VLnameItem->{'name'};
			}
			if (keys %{$VLidItem}) {
				$$playlistVLids{$VLidItem->{'number'}} = $VLidItem->{'id'};
			}
			if ($cached) {
				$useCache = $cached;
			}
			if ($repeatIndef) {
				$repeat = $repeatIndef;
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
			my $fileExtension = "\\.sql\$";
			$item =~ s/$fileExtension$//;
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
						main::DEBUGLOG && $log->is_debug && $log->debug("Use already existing value PlaylistParameter$p = ".$playLists->{$playlistid}->{'parameters'}->{$p}->{'value'});
						$parameters{$p}->{'value'} = $playLists->{$playlistid}->{'parameters'}->{$p}->{'value'};
					}
				}
			}
			if ($menuListType) {
				$playlist{'menulisttype'} = $menuListType;
			}
			if ($playlistCategory) {
				$playlist{'playlistcategory'} = $playlistCategory;
			}
			if ($playlistLMSminVersion) {
				$playlist{'minlmsversion'} = $playlistLMSminVersion;
			}
			if ($playlistAPCdupe) {
				$playlist{'playlistapcdupe'} = $playlistAPCdupe;
			}
			if ($playlistTrackOrder) {
				$playlist{'playlisttrackorder'} = $playlistTrackOrder;
			}
			if ($playlistLimitOption) {
				$playlist{'playlistlimitoption'} = $playlistLimitOption;
			}
			if (keys %{$playlistVLnames}) {
				$playlist{'playlistvirtuallibrarynames'} = $playlistVLnames;
			}
			if (keys %{$playlistVLids}) {
				$playlist{'playlistvirtuallibraryids'} = $playlistVLids;
			}
			if ($useCache) {
				$playlist{'usecache'} = $useCache;
			}
			if ($repeat) {
				$playlist{'repeat'} = $repeat;
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
			$log->error("Unable to read playlist configuration:\n$@");
		} else {
			$errorMsg = 'Incorrect information in playlist data';
			$log->error('Unable to to read playlist configuration');
		}
	}
	return undef;
}

sub parsePlaylistName {
	my ($line, $parseStrings) = @_;
	if ($line =~ /^\s*--\s*PlaylistName\s*[:=]\s*/) {
		my $name = $line;
		$name =~ s/^\s*--\s*PlaylistName\s*[:=]\s*//io;
		$name =~ s/\s+$//;
		$name =~ s/^\s+//;

		if ($name) {
			if ($parseStrings) {
				$name = string($name) || $name;
			}
			return $name;
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("No name found in: $line");
			main::DEBUGLOG && $log->is_debug && $log->debug("Value: name = $name");
			return undef;
		}
	}
	return undef;
}

sub parseParameter {
	my ($line, $parseStrings) = @_;
	my $unknownString = string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_UNKNOWN');

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
		if ($parameterName && $parseStrings) {
			$parameterName = string($parameterName) || $parameterName;
		}

		$parameterDefinition =~ s/^\s+//;
		$parameterDefinition =~ s/\s+$//;
		$parameterDefinition =~ s/PlaylistDefinitionUnknownString/$unknownString/ig;

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
			$log->warn("Parameter values: Id = $parameterId, Type = $parameterType, Name = $parameterName, Definition = $parameterDefinition");
			return undef;
		}
	}
	return undef;
}

sub parseAction {
	my ($line, $actionType) = @_;

	if ($line =~ /^\s*--\s*Playlist(Start|Stop)Action\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*Playlist(Start|Stop)Action\s*(\d)\s*[:=]\s*([^:]+):\s*(.*)$/;
		my $executeTime = $1;
		my $actionId = $2;
		my $actionType = $3;
		my $actionDefinition = $4;

		if ($actionId && $actionType && $actionDefinition) {
			$actionType =~ s/^\s+//;
			$actionType =~ s/\s+$//;
			$actionDefinition =~ s/^\s+//;
			$actionDefinition =~ s/\s+$//;

			my %action = (
				'id' => $actionId,
				'execute' => $executeTime,
				'type' => $actionType,
				'data' => $actionDefinition
			);
			return \%action;
		} else {
			$log->warn("No action defined or error in action: $line");
			$log->warn('Action values: ID = '.Data::Dump::dump($actionId).' -- Type = '.Data::Dump::dump($actionType).' -- Definition = '.Data::Dump::dump($actionDefinition));
			return undef;
		}
	}
	return undef;
}

sub parseLMSminVersion {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistLMSminVersion\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistLMSminVersion\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $minVersion = $1;

		if ($minVersion && $minVersion =~ /(\d+)\.(\d+).*/) {
			$minVersion =~ s/\s+$//;
			$minVersion =~ s/^\s+//;
			return $minVersion;
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("No value or error in minVersion: $line");
			main::DEBUGLOG && $log->is_debug && $log->debug('Option values: minVersion = '.Data::Dump::dump($minVersion));
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

		if ($MenuListType) {
			$MenuListType =~ s/\s+$//;
			$MenuListType =~ s/^\s+//;
			return $MenuListType;
		} else {
			$log->warn("No value or error in MenuListType: $line");
			$log->warn('Option values: MenuListType = '.Data::Dump::dump($MenuListType));
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

		if ($category) {
			$category =~ s/\s+$//;
			$category =~ s/^\s+//;
			return $category;
		} else {
			$log->warn("No value or error in category: $line");
			$log->warn('Option values: category = '.Data::Dump::dump($category));
			return undef;
		}
	}
	return undef;
}

sub parseAPCdupe {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistAPCdupe\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistAPCdupe\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $APCdupe = $1;

		if ($APCdupe) {
			$APCdupe =~ s/\s+$//;
			$APCdupe =~ s/^\s+//;
			return $APCdupe;
		} else {
			$log->warn("No value or error in APCdupe: $line");
			$log->warn('Option values: APCdupe = '.Data::Dump::dump($APCdupe));
			return undef;
		}
	}
	return undef;
}

sub parseTrackOrder {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistTrackOrder\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistTrackOrder\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $trackOrder = $1;

		if ($trackOrder) {
			$trackOrder =~ s/\s+$//;
			$trackOrder =~ s/^\s+//;
			return $trackOrder;
		} else {
			$log->warn("No value or error in trackOrder: $line");
			$log->warn('Option values: trackOrder = '.Data::Dump::dump($trackOrder));
			return undef;
		}
	}
	return undef;
}

sub parseLimitOption {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistLimitOption\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistLimitOption\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $limitOption = $1;

		if ($limitOption) {
			$limitOption =~ s/\s+$//;
			$limitOption =~ s/^\s+//;
			return $limitOption;
		} else {
			$log->warn("No value or error in limitOption: $line");
			$log->warn('Option values: limitOption = '.Data::Dump::dump($limitOption));
			return undef;
		}
	}
	return undef;
}

sub parseVirtualLibraryName {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistVirtualLibraryName\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistVirtualLibraryName\s*(\d)\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $VLnumber = $1;
		my $VLname = $2;

		if ($VLnumber && $VLname) {
			$VLnumber =~ s/^\s+//;
			$VLnumber =~ s/\s+$//;
			$VLname =~ s/^\s+//;
			$VLname =~ s/\s+$//;

			my %VLnameItem = (
				'number' => $VLnumber,
				'name' => $VLname,
			);
			return \%VLnameItem;
		} else {
			$log->warn("Error in parameter: $line");
			$log->warn('Parameter values: VL number = '.Data::Dump::dump($VLnumber).' -- VL name = '.Data::Dump::dump($VLname));
			return undef;
		}
	}
	return undef;
}

sub parseVirtualLibraryID {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistVirtualLibraryID\s*\d\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistVirtualLibraryID\s*(\d)\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $VLnumber = $1;
		my $VLid = $2;

		if ($VLnumber && $VLid) {
			$VLnumber =~ s/^\s+//;
			$VLnumber =~ s/\s+$//;
			$VLid =~ s/^\s+//;
			$VLid =~ s/\s+$//;

			my %VLidItem = (
				'number' => $VLnumber,
				'id' => $VLid,
			);
			return \%VLidItem;
		} else {
			$log->warn("Error in parameter: $line");
			$log->warn('Parameter values: VL number = '.Data::Dump::dump($VLnumber).' -- VLid = '.Data::Dump::dump($VLid));
			return undef;
		}
	}
	return undef;
}

sub parseUseCache {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistUseCache\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistUseCache\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $useCache = $1;

		if ($useCache) {
			$useCache =~ s/\s+$//;
			$useCache =~ s/^\s+//;
			return $useCache;
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("No value or error in useCache: $line");
			main::DEBUGLOG && $log->is_debug && $log->debug('Option values: useCache = '.Data::Dump::dump($useCache));
			return undef;
		}
	}
	return undef;
}

sub parseRepeat {
	my $line = shift;
	if ($line =~ /^\s*--\s*PlaylistRepeat\s*[:=]\s*/) {
		$line =~ m/^\s*--\s*PlaylistRepeat\s*[:=]\s*([^:]+)\s*(.*)$/;
		my $repeat = $1;

		if ($repeat) {
			$repeat =~ s/\s+$//;
			$repeat =~ s/^\s+//;
			return $repeat;
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("No value or error in repeat: $line");
			main::DEBUGLOG && $log->is_debug && $log->debug('Option values: repeat = '.Data::Dump::dump($repeat));
			return undef;
		}
	}
	return undef;
}


### DPL history & cache ###

sub initDatabase {
	my $dbh = Slim::Schema->dbh;
	my $st = $dbh->table_info();
	my $tablexists;
	while (my ($qual, $owner, $table, $type) = $st->fetchrow_array()) {
		if ($table eq 'dynamicplaylist_history') {
			$st->finish();

			my $sth = $dbh->prepare (q{pragma table_info(dynamicplaylist_history)});
			$sth->execute() or do {
				main::DEBUGLOG && $log->is_debug && $log->debug("Error executing");
			};

			my $colName;
			my %colNames = ();
			while ($sth->fetch()) {
				$sth->bind_col(2, \$colName);
				$colNames{$colName} = 1 if $colName;
			}
			$sth->finish();

			if ($colNames{'skipped'}) {
				my $sql = qq(drop table if exists dynamicplaylist_history );
				eval {$dbh->do($sql)};
				if ($@) {
					msg("Couldn't drop DPL history database table: [$@]");
				}
			} else {
				$tablexists = 1;
			}
		last;
		}
	}
	$st->finish();

	unless ($tablexists) {
		my $sqlCreate = "create table if not exists dynamicplaylist_history (client varchar(20) not null, position integer primary key autoincrement, id int(10) not null unique, added int(10) not null default null);";
		main::DEBUGLOG && $log->is_debug && $log->debug('Creating DPL history database table');
		eval {$dbh->do($sqlCreate)};
		if ($@) {
			msg("Couldn't create DPL history database table: [$@]");
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Creating DPL history database indexes');
	my $sqlIndex = "create unique index if not exists idClientIndex on dynamicplaylist_history (id,client);";
	eval {$dbh->do($sqlIndex)};
	if ($@) {
		msg("Couldn't index DPL history database table: [$@]");
	}
	commit($dbh);
}

sub addToPlayListHistory {
	my ($client, $trackID, $addedTime) = @_;

	if (Slim::Music::Import->stillScanning && (!UNIVERSAL::can('Slim::Music::Import', 'externalScannerRunning') || Slim::Music::Import->externalScannerRunning)) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Adding track to queue: '.$trackID);
		my $item = {
			'id' => $trackID,
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

	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->prepare("insert or replace into dynamicplaylist_history (client, id, added) values (?, ".$trackID.", ".$addedTime.")");
	eval {
		$sth->bind_param(1, $client->id);
		$sth->execute();
		commit($dbh);
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr");
		eval {
			rollback($dbh); # just die if rollback is failing
		};
	}
	$sth->finish();
}

sub clearPlayListHistory {
	my $clients = shift;
	my $dbh = Slim::Schema->dbh;

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
			main::DEBUGLOG && $log->is_debug && $log->debug('Deleting playlist history for player: '.$client->name);
			if ($clientIds ne '') {
				$clientIds .= ',';
			}
			$clientIds .= $dbh->quote($client->id);
		}
		my $sql = "delete from dynamicplaylist_history where client in ($clientIds)";
		$sth = $dbh->prepare($sql);
	} else {
		$sth = $dbh->prepare("delete from dynamicplaylist_history");
	}
	eval {
		$sth->execute();
		commit($dbh);
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr");
		eval {
			rollback($dbh); #just die if rollback is failing
		};
	}
	$sth->finish();
}

sub getNoOfItemsInHistory {
	my $client = shift;
	my $result = 0;
	my $dbh = Slim::Schema->dbh;
	eval {
		my $clientid = $dbh->quote($client->id);
		my $sql = "select count(position) from dynamicplaylist_history where dynamicplaylist_history.client = $clientid";
		my $sth = $dbh->prepare($sql);
		main::DEBUGLOG && $log->is_debug && $log->debug("Executing history count SQL: $sql");
		$sth->execute() or do {
			main::DEBUGLOG && $log->is_debug && $log->debug("Error executing: $sql");
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

sub clearCache {
	my $clients = shift;

	if (defined($clients)) {
		if (ref $clients eq 'ARRAY') {
			foreach (@{$clients}) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Multiple clients: Clearing cache for client: '.$_->id);
				$cache->remove('dpl_totalTrackIDlist_'.$_->id);
				$cache->remove('dpl_totalTracksCompleteInfo_'.$_->id);
				$_->pluginData('cacheFilled' => 0);
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('Single client: clearing cache for client: '.$clients->id);
			$cache->remove('dpl_totalTrackIDlist_'.$clients->id);
			$cache->remove('dpl_totalTracksCompleteInfo_'.$clients->id);
			$clients->pluginData('cacheFilled' => 0);
		}
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Clearing cache for all clients');
		foreach (Slim::Player::Client::clients()) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Clearing cache for client: '.$_->id);
			$cache->remove('dpl_totalTrackIDlist_'.$_->id);
			$cache->remove('dpl_totalTracksCompleteInfo_'.$_->id);
			$_->pluginData('cacheFilled' => 0);
		}
	}
}


### titleformats ###

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
	my ($client, $song, $tag) = @_;

	main::DEBUGLOG && $log->is_debug && $log->debug("Entering getTitleFormatDynamicPlaylist with $client and $tag");
	my $masterClient = masterOrSelf($client);

	my $playlist = getPlayList($client, $mixInfo{$masterClient}->{'type'});

	if ($playlist) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Exiting getTitleFormatDynamicPlaylist with '.$playlist->{'name'});
		return $playlist->{'name'};
	}

	if ($tag =~ 'DYNAMICORSAVEDPLAYLIST') {
		my $playlist = Slim::Music::Info::playlistForClient($client);
		if ($playlist && $playlist->content_type && $playlist->content_type ne 'cpl') {
			main::DEBUGLOG && $log->is_debug && $log->debug('Exiting getTitleFormatDynamicPlaylist with '.$playlist->title);
			return $playlist->title;
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Exiting getTitleFormatDynamicPlaylist with undef');
	return undef;
}


### CustomSkip filters ###

sub getCustomSkipFilterTypes {
	my @result = ();

	my %recentlyaddedalbums = (
		'id' => 'dynamicplaylist_recentlyaddedalbum',
		'name' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDALBUM_NAME'),
		'filtercategory' => 'albums',
		'description' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDALBUM_DESC'),
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDALBUM_PARAM_NAME'),
				'data' => '1=1 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONG').',2=2 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',2=3 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',4=4 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',5=5 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',10=10 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',20=20 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',30=30 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',50=50 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS'),
				'value' => 10
			}
		]
	);
	push @result, \%recentlyaddedalbums;
	my %recentlyaddedartists = (
		'id' => 'dynamicplaylist_recentlyaddedartist',
		'name' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDARTIST_NAME'),
		'filtercategory' => 'artists',
		'description' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDARTIST_DESC'),
		'parameters' => [
			{
				'id' => 'nooftracks',
				'type' => 'singlelist',
				'name' => string('PLUGIN_DYNAMICPLAYLISTS4_CUSTOMSKIP_RECENTLYADDEDARTIST_PARAM_NAME'),
				'data' => '1=1 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONG').',2=2 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',2=3 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',4=4 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',5=5 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',10=10 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',20=20 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',30=30 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS').',50=50 '.string('PLUGIN_DYNAMICPLAYLISTS4_LANGSTRINGS_SONGS'),
				'value' => 10
			}
		]
	);
	push @result, \%recentlyaddedartists;
	return \@result;
}

sub checkCustomSkipFilterType {
	my ($client, $filter, $track, $lookaheadonly, $index) = @_;
	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $sql = undef;
	my $result = 0;
	my $dbh = Slim::Schema->dbh;
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
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join contributor_track on contributor_track.track = dynamicplaylist_history.id where contributor_track.contributor = $artistid and dynamicplaylist_history.client = $clientid";
					} else {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join contributor_track on contributor_track.track = dynamicplaylist_history.id where contributor_track.contributor = $artistid and dynamicplaylist_history.client = $clientid and dynamicplaylist_history.position > (select position from dynamicplaylist_history where dynamicplaylist_history.client = $clientid order by position desc limit 1 offset $nooftracks)";
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
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join tracks on tracks.id = dynamicplaylist_history.id where tracks.album = $albumid and dynamicplaylist_history.client = $clientid";
					} else {
						$sql = "select dynamicplaylist_history.position from dynamicplaylist_history join tracks on tracks.id = dynamicplaylist_history.id where tracks.album = $albumid and dynamicplaylist_history.client = $clientid and dynamicplaylist_history.position > (select position from dynamicplaylist_history where dynamicplaylist_history.client = $clientid order by position desc limit 1 offset $nooftracks)";
					}
				}
				last;
			}
		}
	}
	if (defined($sql)) {
		eval {
			my $sth = $dbh->prepare($sql);
			main::DEBUGLOG && $log->is_debug && $log->debug("Executing skip filter SQL: $sql");
			$sth->execute() or do {
				$log->error("Error executing: $sql");
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
			$log->error("Error executing filter: $@");
		}
	}
	return $result;
}



# misc / helpers

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
		main::DEBUGLOG && $log->is_debug && $log->debug('Clearing play history for all players');
		clearPlayListHistory();
		$deleteAllQueues = 0;
		$deleteQueue = {};
	} elsif (scalar(keys %{$deleteQueue}) > 0) {
		my @clients = ();
		foreach my $clientId (keys %{$deleteQueue}) {
			my $deleteClient = Slim::Player::Client::getClient($clientId);
			push @clients, $deleteClient;
			main::DEBUGLOG && $log->is_debug && $log->debug('Clearing play history for player: '.$deleteClient->name);
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
					if (defined($item->{'id'})) {
						main::DEBUGLOG && $log->is_debug && $log->debug('Added play history of track: '.$item->{'id'});
						addToPlayListHistory($addedClient, $item->{'id'}, $item->{'addedTime'});
					}
				}
			}
		}
		$historyQueue = {};
	}

	clearCache();
}

sub continuePreviousPlaylist {
	my $client = shift;
	my $masterClient = masterOrSelf($client);

	my $type = $prefs->client($masterClient)->get('playlist');
	if (defined($type)) {
		my $offset = $prefs->client($masterClient)->get('offset');
		main::DEBUGLOG && $log->is_debug && $log->debug("Continuing playing playlist: $type on ".$client->name);
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
		main::DEBUGLOG && $log->is_debug && $log->debug('No previously playing playlist');
	}
}

sub commandCallback {
	my $request = shift;
	my $client = $request->client();
	my $masterClient = masterOrSelf($client);

	if (defined($request->source()) && $request->source() eq 'PLUGIN_DYNAMICPLAYLISTS4') {
		return;
	} elsif (defined($request->source())) {
		main::DEBUGLOG && $log->is_debug && $log->debug('received command initiated by '.$request->source());
	}
	if ($request->isCommand([['playlist'], ['play']])) {
		my $url = $request->getParam('_item');
		if ($url =~ /^dynamicplaylist:\/\//) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Skipping '.$request->getRequestString()." $url");
			return;
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('received command '.($request->getRequestString()));

	# because of the filter this should never happen
	# in addition there are valid commands (e.g. rescan) that have no client
	# so the bt() is strange here
	if (!defined $masterClient || !defined $mixInfo{$masterClient}->{'type'}) {
		return;
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('while in mode: '.($mixInfo{$masterClient}->{'type'}).', from '.($client->name));

	my $songIndex = Slim::Player::Source::streamingSongIndex($client);

	if ($request->isCommand([['playlist'], ['newsong']])
		|| $request->isCommand([['playlist'], ['delete']]) && $request->getParam('_index') > $songIndex) {

		if ($request->isCommand([['playlist'], ['newsong']])) {
			if ($masterClient->id ne $client->id) {
				main::DEBUGLOG && $log->is_debug && $log->debug('Ignoring event, this is a slave player');
				return;
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("new song detected ($songIndex)");
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug('deletion detected ('.($request->getParam('_index')).')');
		}

		my $songsToKeep = $prefs->get('number_of_played_tracks_to_keep');
		if ($songIndex && $songsToKeep) {
			main::DEBUGLOG && $log->is_debug && $log->debug('Stripping off completed track(s)');

			# Delete tracks before this one on the playlist
			for (my $i = 0; $i < $songIndex - $songsToKeep; $i++) {
				my $request = $client->execute(['playlist', 'delete', 0]);
				$request->source('PLUGIN_DYNAMICPLAYLISTS4');
			}
		}

		my $songAddingCheckDelay = $prefs->get('song_adding_check_delay') || 0;
		my $songIndex = Slim::Player::Source::streamingSongIndex($client);
		my $songsRemaining = Slim::Player::Playlist::count($client) - $songIndex - 1;
		if ($songAddingCheckDelay && $songsRemaining > 0) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Will check in $songAddingCheckDelay seconds if new songs have to be added");
			Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $songAddingCheckDelay, \&playRandom, $mixInfo{$masterClient}->{'type'}, 1, 0);
		} else {
			playRandom($client, $mixInfo{$masterClient}->{'type'}, 1, 0);
		}
	} elsif ($request->isCommand([['playlist'], [keys %stopcommands]])) {

		main::DEBUGLOG && $log->is_debug && $log->debug('cyclic mode ending due to playlist: '.($request->getRequestString()).' command');
		playRandom($client, 'disable');
	}
}

sub createCustomPlaylistFolder {
	my $customPlaylistFolder_parentfolderpath = $prefs->get('customdirparentfolderpath') || Slim::Utils::OSDetect::dirsFor('prefs');
	my $customPlaylistFolder = catdir($customPlaylistFolder_parentfolderpath, 'DPL-custom-lists');
	eval {
		mkdir($customPlaylistFolder, 0755) unless (-d $customPlaylistFolder);
	} or do {
		$log->error("Could not create custom playlist folder in parent folder '$customPlaylistFolder_parentfolderpath'! Please make sure that LMS has read/write permissions (755) for the parent folder.");
		return;
	};
	$prefs->set('customplaylistfolder', $customPlaylistFolder);
}

sub refreshPluginPlaylistFolder {
	# in case you need to switch between manual and LMS repo install
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if (-d catdir($plugindir, 'DynamicPlaylists4', 'Playlists')) {
			my $pluginPlaylistFolder = catdir($plugindir, 'DynamicPlaylists4', 'Playlists');
			main::DEBUGLOG && $log->is_debug && $log->debug('pluginPlaylistFolder = '.Data::Dump::dump($pluginPlaylistFolder));
			$prefs->set('pluginplaylistfolder', $pluginPlaylistFolder);
		}
		if (-d catdir($plugindir, 'DynamicPlaylists4', 'HTML', 'EN', 'plugins', 'DynamicPlaylists4', 'html', 'audio')) {
			$prefs->set('silencetrackurl', catfile($plugindir, 'DynamicPlaylists4', 'HTML', 'EN', 'plugins', 'DynamicPlaylists4', 'html', 'audio','silence.mp3'));
			main::DEBUGLOG && $log->is_debug && $log->debug('silence track url = '.catfile($plugindir, 'DynamicPlaylists4', 'HTML', 'EN', 'plugins', 'DynamicPlaylists4', 'html', 'audio','silence.mp3'));
		}
	}
}

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
	main::DEBUGLOG && $log->is_debug && $log->debug('mixStatus = '.Data::Dump::dump($mixStatus));
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
		$excludedgenreString = join ',', map qq/'$_'/, @{$excludegenres_namelist};
	}
	return $excludedgenreString;
}

sub getMsgDisplayTime {
	my $displayString = shift;
	my $showTimePerChar = $prefs->get('showtimeperchar') / 1000;
	my $msgDisplayTime = length($displayString) * $showTimePerChar;
	$msgDisplayTime = 2 if $msgDisplayTime < 2;
	$msgDisplayTime = 25 if $msgDisplayTime > 25;
	main::DEBUGLOG && $log->is_debug && $log->debug("Display time: ".$msgDisplayTime."s for message '".$displayString."'");
	return $msgDisplayTime;
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

sub weight {
	return 78;
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

sub objectForId {
	my ($type, $id) = @_;
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

sub isInt {
	my ($val, $low, $high, $setLow, $setHigh) = @_;

	if ($val && $val !~ /^-?\d+$/) { # not an integer
		return undef;
	} elsif (defined($low) && $val < $low) { # too low, equal to $low is acceptable
		if ($setLow) {
			return $low;
		} else {
			return undef;
		}
	} elsif (defined($high) && $val > $high) { # too high, equal to $high is acceptable
		if ($setHigh) {
			return $high;
		} else {
			return undef;
		}
	}
	return $val;
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

*escape = \&URI::Escape::uri_escape_utf8;
*unescape = \&URI::Escape::uri_unescape;

1;
