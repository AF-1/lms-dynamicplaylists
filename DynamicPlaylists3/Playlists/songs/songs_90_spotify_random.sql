-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS3_BUILTIN_PLAYLIST_SONGS_SPOTIFY_RANDOM
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
select distinct tracks.url from tracks
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		tracks.content_type = 'spt'
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
	order by random()
	limit 'PlaylistLimit';
