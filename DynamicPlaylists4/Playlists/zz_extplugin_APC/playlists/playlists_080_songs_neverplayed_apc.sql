-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_PLAYLISTS_NEVERPLAYED_APC
-- PlaylistGroups:Playlists
-- PlaylistCategory:playlists
drop table if exists dynamicplaylist_random_playlists;
create temporary table dynamicplaylist_random_playlists as
	select playlist_track.playlist as playlist, sum(ifnull(alternativeplaycount.playCount,0)) as sumplaycount from playlist_track
		join tracks on
			tracks.url = playlist_track.track
		left join library_track on
			library_track.track = tracks.id
		join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		left join dynamicplaylist_history on
			dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			dynamicplaylist_history.id is null
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
								genres.name in ('PlaylistExcludedGenres'))
		group by playlist_track.playlist
			having sumplaycount = 0
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join playlist_track on
		playlist_track.track = tracks.url
	join dynamicplaylist_random_playlists on
		dynamicplaylist_random_playlists.playlist = playlist_track.playlist
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
							genres.name in ('PlaylistExcludedGenres'))
	group by tracks.id
	order by random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_playlists;
