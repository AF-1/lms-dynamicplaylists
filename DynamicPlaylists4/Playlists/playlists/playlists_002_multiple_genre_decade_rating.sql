-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_PLAYLISTS_MULTIPLE_GENRE_DECADE_MINRATING
-- PlaylistGroups:Playlists
-- PlaylistCategory:playlists
-- PlaylistUseCache: 1
-- PlaylistParameter1:multiplestaticplaylists:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPLAYLISTS:
-- PlaylistParameter2:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES:
-- PlaylistParameter3:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
-- PlaylistParameter4:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINRATING:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_UNRATED,20:*,40:**,60:***,80:****,100:*****
-- PlaylistParameter5:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED

select tracks.id, tracks.primary_artist from tracks
	join playlist_track on
		playlist_track.track = tracks.url
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistParameter4'
	left join library_track on
		library_track.track = tracks.id
	join genre_track on
		genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter2')
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and playlist_track.playlist in ('PlaylistParameter1')
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and ifnull(tracks.year, 0) in ('PlaylistParameter3')
		and
			case
				when 'PlaylistParameter5' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter5' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
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
