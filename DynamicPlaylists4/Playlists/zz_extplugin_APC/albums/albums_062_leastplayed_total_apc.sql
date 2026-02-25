-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_ALBUMS_LEASTPLAYED_APC
-- PlaylistGroups:Albums
-- PlaylistCategory:albums
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDECOMPIS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_COMPISONLY,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_ALBUMS_NOCOMPIS
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_albums;
create temporary table dynamicplaylist_random_albums as
	select leastplayed.album as album from
		(select t.album as album, sum(t.playcount) as sumcount, count(distinct t.id) as totaltrackcount
		from (
			select tracks.id, tracks.urlmd5, tracks.album,
				ifnull(alternativeplaycount.playCount, 0) as playcount
			from tracks
			join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
			where tracks.audio = 1
			group by tracks.id
		) as t
		join albums on albums.id = t.album
		left join library_track on library_track.track = t.id
		left join dynamicplaylist_history on dynamicplaylist_history.id = t.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			dynamicplaylist_history.id is null
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
			and not exists (select * from tracks t2, genre_track, genres
							where
								t2.id = t.id and
								t2.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
		group by t.album
		having totaltrackcount >= 'PlaylistMinAlbumTracks'
			and
				case
					when 'PlaylistParameter1' = 1 then ifnull(albums.compilation, 0) = 1
					when 'PlaylistParameter1' = 2 then ifnull(albums.compilation, 0) = 0
					else 1
				end
		order by sumcount asc, random()
		limit 30) as leastplayed
	order by random()
	limit 1;
select distinct tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_albums on dynamicplaylist_random_albums.album = tracks.album
	join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter2' = 1 then ifnull(alternativeplaycount.playCount, 0) = 0
				when 'PlaylistParameter2' = 2 then ifnull(alternativeplaycount.playCount, 0) > 0
				else 1
			end
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.namesearch in ('PlaylistExcludedGenres'))
	order by dynamicplaylist_random_albums.album,tracks.disc,tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_albums;
