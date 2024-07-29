-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_WORKS_PARTLYPLAYED_GENRE_DECADE_APC
-- PlaylistGroups:Works
-- PlaylistCategory:works
-- PlaylistLMSminVersion: 9.0.0
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES:
-- PlaylistParameter2:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
drop table if exists dynamicplaylist_random_works;
create temporary table dynamicplaylist_random_works as
	select tracks.album as album, tracks.work as work, tracks.performance as performance, count(distinct tracks.id) as totaltrackcount from tracks
		join albums on albums.id = tracks.album
		join genre_track on genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter1')
		join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
		left join library_track on library_track.track = tracks.id
		left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			tracks.audio = 1
			and dynamicplaylist_history.id is null
			and tracks.work is not null
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
		group by case when tracks.performance is not null then tracks.performance else tracks.work end
			having totaltrackcount >= 'PlaylistMinAlbumTracks'
			and min(ifnull(alternativeplaycount.playCount,0)) = 0 and avg(ifnull(alternativeplaycount.playCount,0)) > 0
			and ifnull(albums.year, 0) in ('PlaylistParameter2')
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_works on (tracks.album = dynamicplaylist_random_works.album and tracks.work = dynamicplaylist_random_works.work and case when dynamicplaylist_random_works.performance is not null then tracks.performance = dynamicplaylist_random_works.performance else 1 end)
	join genre_track on genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter1')
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
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
	group by tracks.id
	order by dynamicplaylist_random_works.album,tracks.disc,tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_works;
