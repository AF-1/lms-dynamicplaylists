-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_DECADE_ALBUMS_RANDOM
-- PlaylistGroups:Context menu lists/ decade
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:years
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:year:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTYEAR:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_ALBUMS_RECENTLYPLAYED:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_ALL,604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_1WEEK,1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_2WEEKS,2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_4WEEKS,7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_3MONTHS,14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_6MONTHS,-604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_1WEEK_NOT,-1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_2WEEKS_NOT,-2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_4WEEKS_NOT,-7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_3MONTHS_NOT,-14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_6MONTHS_NOT
drop table if exists dynamicplaylist_random_albums;
create temporary table dynamicplaylist_random_albums as
	select tracks.album as album, count(distinct tracks.id) as totaltrackcount from tracks
		left join library_track on
			library_track.track = tracks.id
		join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		left join dynamicplaylist_history on
			dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			tracks.audio = 1
			and tracks.year >= cast((('PlaylistParameter1'/10)*10) as int) and tracks.year < (cast((('PlaylistParameter1'/10)*10) as int)+10)
			and dynamicplaylist_history.id is null
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
			and
				case
					when 'PlaylistParameter2'>0 then (ifnull(tracks_persistent.lastPlayed,0) >= (strftime('%s',DATE('NOW')) - 'PlaylistParameter2'))
					else 1
				end
			and not exists (select * from tracks t2,genre_track,genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
		group by tracks.album
			having totaltrackcount >= 'PlaylistMinAlbumTracks'
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_albums on
		dynamicplaylist_random_albums.album = tracks.album
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
		and not exists (select * from tracks t2,genre_track,genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.namesearch in ('PlaylistExcludedGenres'))
	group by tracks.id
	order by dynamicplaylist_random_albums.album,tracks.disc,tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_albums;
