-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_ARTISTS_RECENTLYPLAYEDORLASTADDEDSONGS
-- PlaylistGroups:Artists
-- PlaylistCategory:artists
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_ARTISTS_RECENTLYPLAYED:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_ALL,604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_1WEEK,1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_2WEEKS,2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_4WEEKS,7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_3MONTHS,14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_6MONTHS,-604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_1WEEK_NOT,-1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_2WEEKS_NOT,-2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_4WEEKS_NOT,-7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_3MONTHS_NOT,-14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_6MONTHS_NOT
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTLASTADDEDPERIOD_ARTISTS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_ALL,604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_1WEEK,1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_2WEEKS,2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_4WEEKS,7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_3MONTHS,14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_6MONTHS,29030399:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_12MONTHS
drop table if exists dynamicplaylist_random_contributors;
create temporary table dynamicplaylist_random_contributors as
	select contributor_track.contributor as contributor, count(distinct tracks.id) as totaltrackcount from tracks
		join contributor_track on
			contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
		left join library_track on
			library_track.track = tracks.id
		join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		left join dynamicplaylist_history on
			dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			tracks.audio = 1
			and dynamicplaylist_history.id is null
			and contributor_track.contributor != 'PlaylistVariousArtistsID'
			and not exists (select * from tracks t2,genre_track,genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
			and
				case
					when 'PlaylistParameter1'>0 then (ifnull(tracks_persistent.lastPlayed,0) >= (strftime('%s',DATE('NOW')) - ('PlaylistParameter1')))
					else 1
				end
			and
				case
					when 'PlaylistParameter2'>0 then (tracks_persistent.added >= (select max(ifnull(tracks_persistent.added,0)) from tracks_persistent) - 'PlaylistParameter2')
					else 1
				end
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
		group by contributor_track.contributor
			having
				totaltrackcount >= 'PlaylistMinArtistTracks'
			and
				case
					when 'PlaylistParameter1'<0 then (ifnull(tracks_persistent.lastPlayed,0) < (strftime('%s',DATE('NOW')) + ('PlaylistParameter1')))
					else 1
				end
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join contributor_track on
		contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
	join dynamicplaylist_random_contributors on
		dynamicplaylist_random_contributors.contributor = contributor_track.contributor
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.namesearch in ('PlaylistExcludedGenres'))
	group by tracks.id
	order by dynamicplaylist_random_contributors.contributor, random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_contributors;
