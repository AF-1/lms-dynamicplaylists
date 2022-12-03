-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_ARTIST_SONGS_RANDOM
-- PlaylistGroups:Context menu lists/ artist
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:artists
-- PlaylistUseCache: 1
-- PlaylistParameter1:artist:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTARTIST:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
select tracks.id, tracks.primary_artist from tracks
	join contributor_track on
		contributor_track.track = tracks.id and contributor_track.contributor = 'PlaylistParameter1'
	left join library_track on
		library_track.track = tracks.id
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5
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
		and
			case
				when 'PlaylistParameter3' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter3' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
		and not exists (select * from tracks t2,genre_track,genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.name in ('PlaylistExcludedGenres'))
	group by tracks.id
