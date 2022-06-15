-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS3_BUILTIN_PLAYLIST_CONTEXT_PLAYLIST_SONGS_PLAYEDLONGAGO
-- PlaylistGroups:Context menu lists/ playlist
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:playlists
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:playlist:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_SELECTPLAYLIST:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_PLAYED
select distinct playlist_track.track from playlist_track
	join tracks on
		tracks.url = playlist_track.track
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		playlist_track.playlist='PlaylistParameter1'
		and tracks.audio = 1
		and (strftime('%s',DATE('NOW','-'PlaylistPeriodPlayedLongAgo' YEAR')) - ifnull(tracks_persistent.lastPlayed,0)) > 0
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter2'=1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter2'=2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient'!='' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and not exists (select * from tracks t2,genre_track,genres
						where
							t2.id=tracks.id and
							tracks.id=genre_track.track and
							genre_track.genre=genres.id and
							genres.name in ('PlaylistExcludedGenres'))
	group by playlist_track.track
	order by random()
	limit 'PlaylistLimit';
