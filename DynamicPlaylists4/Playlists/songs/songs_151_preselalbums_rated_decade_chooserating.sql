-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_SONGS_PRESEL_ALBUMS_SONGS_MINRATING_DECADE
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistUseCache: 1
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINRATING:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_UNRATED,20:*,40:**,60:***,80:****,100:*****
-- PlaylistParameter2:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
-- PlaylistParameter3:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
select tracks.id, tracks.primary_artist from tracks
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistParameter1'
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and tracks.album in ('PlaylistPreselectedAlbums')
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and ifnull(tracks.year, 0) in ('PlaylistParameter2')
		and not exists (select * from tracks t2,genre_track,genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.name in ('PlaylistExcludedGenres'))
		and
			case
				when 'PlaylistParameter3' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter3' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
	group by tracks.id
