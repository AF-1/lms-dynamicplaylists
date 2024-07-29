-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_ALBUMS_VLIB_RANDOM
-- PlaylistGroups:Albums
-- PlaylistCategory:albums
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:virtuallibrary:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTVLIB:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDECOMPIS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_COMPISONLY,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_NOCOMPIS
-- PlaylistParameter3:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_albums;
create temporary table dynamicplaylist_random_albums as
	select tracks.album as album, count(distinct tracks.id) as totaltrackcount from tracks
		join albums on albums.id = tracks.album
		left join library_track on library_track.track = tracks.id
		left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			tracks.audio = 1
			and dynamicplaylist_history.id is null
			and
				case
					when ('PlaylistParameter1' != '' and 'PlaylistParameter1' is not null)
					then library_track.library = 'PlaylistParameter1'
					else 1
				end
			and not exists (select * from tracks t2, genre_track, genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
		group by tracks.album
			having totaltrackcount >= 'PlaylistMinAlbumTracks'
			and
				case
					when 'PlaylistParameter2' = 1 then ifnull(albums.compilation, 0) = 1
					when 'PlaylistParameter2' = 2 then ifnull(albums.compilation, 0) = 0
					else 1
				end
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_albums on dynamicplaylist_random_albums.album = tracks.album
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter3' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter3' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
		and
			case
				when ('PlaylistParameter1' != '' and 'PlaylistParameter1' is not null)
				then library_track.library = 'PlaylistParameter1'
				else 1
			end
	group by tracks.id
	order by dynamicplaylist_random_albums.album,tracks.disc,tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_albums;
