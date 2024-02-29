-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_ALBUM_SONGS_MOSTPLAYED
-- PlaylistGroups:Context menu lists/ album
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:albums
-- PlaylistUseCache: 1
-- PlaylistTrackOrder:ordereddescrandom
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:album:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTALBUM:
select tracks.id, tracks.primary_artist, tracks_persistent.playCount from tracks
	left join library_track on
		library_track.track = tracks.id
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.album = 'PlaylistParameter1'
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
	order by tracks_persistent.playCount desc, random()
