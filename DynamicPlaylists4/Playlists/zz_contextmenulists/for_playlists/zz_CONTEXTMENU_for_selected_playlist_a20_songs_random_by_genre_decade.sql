-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_PLAYLIST_SONGS_GENRE_DECADE
-- PlaylistGroups:Context menu lists/ playlist
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:playlists
-- PlaylistUseCache: 1
-- PlaylistParameter1:playlist:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPLAYLIST:
-- PlaylistParameter2:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES:
-- PlaylistParameter3:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
-- PlaylistParameter4:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
select tracks.id, tracks.primary_artist from tracks
	join playlist_track on playlist_track.track = tracks.url
	left join library_track on library_track.track = tracks.id
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
	join genre_track on genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter2')
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		playlist_track.playlist = 'PlaylistParameter1'
		and tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and tracks.year in ('PlaylistParameter3')
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and
			case
				when 'PlaylistParameter4' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter4' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
	group by tracks.id
