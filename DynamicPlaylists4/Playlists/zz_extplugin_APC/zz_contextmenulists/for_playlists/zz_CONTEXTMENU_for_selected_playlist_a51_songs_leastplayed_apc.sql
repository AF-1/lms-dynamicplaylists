-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_PLAYLIST_SONGS_LEASTPLAYED_APC
-- PlaylistGroups:Context menu lists/ playlist
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:playlists
-- PlaylistUseCache: 1
-- PlaylistTrackOrder:orderedascrandom
-- PlaylistParameter1:playlist:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPLAYLIST:
select tracks.id, tracks.primary_artist, alternativeplaycount.playCount from tracks
	join playlist_track on
		playlist_track.track = tracks.url
	left join library_track on
		library_track.track = tracks.id
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		playlist_track.playlist = 'PlaylistParameter1'
		and tracks.audio = 1
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
	order by alternativeplaycount.playCount asc, random()
