-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS3_BUILTIN_PLAYLIST_PLAYLISTS_RANDOM
-- PlaylistGroups:Playlists
-- PlaylistCategory:playlists
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_playlists;
create temporary table dynamicplaylist_random_playlists as
	select playlist_track.playlist as playlist from playlist_track
		join tracks on
			tracks.url = playlist_track.track
		left join library_track on
			library_track.track = tracks.id
		left join dynamicplaylist_history on
			dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
		where
			dynamicplaylist_history.id is null
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
		group by playlist_track.playlist
		order by random()
		limit 1;
select distinct playlist_track.track from playlist_track
	join dynamicplaylist_random_playlists on
		dynamicplaylist_random_playlists.playlist = playlist_track.playlist
	join tracks on
		tracks.url = playlist_track.track
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter1'=1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter1'=2 then ifnull(tracks_persistent.playCount, 0) > 0
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
							t2.id=tracks.id and
							tracks.id=genre_track.track and
							genre_track.genre=genres.id and
							genres.name in ('PlaylistExcludedGenres'))
	group by tracks.id
	order by random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_playlists;
