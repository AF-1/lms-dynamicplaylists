-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_WORKS_NEVERPLAYED_APC
-- PlaylistGroups:Works
-- PlaylistCategory:works
-- PlaylistLMSminVersion: 9.0.0
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
drop table if exists dynamicplaylist_random_works;
create temporary table dynamicplaylist_random_works as
	select tracks.album as album, tracks.work as work, tracks.grouping as grouping, sum(ifnull(alternativeplaycount.playCount,0)) as sumplaycount, count(distinct tracks.id) as totaltrackcount from tracks
		left join library_track on
			library_track.track = tracks.id
		join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		left join dynamicplaylist_history on
			dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
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
		group by case when tracks.grouping is not null then tracks.grouping else tracks.work end
			having totaltrackcount >= 'PlaylistMinAlbumTracks' and sumplaycount = 0
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_works on (tracks.album = dynamicplaylist_random_works.album and tracks.work = dynamicplaylist_random_works.work and case when dynamicplaylist_random_works.grouping is not null then tracks.grouping = dynamicplaylist_random_works.grouping else 1 end)
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
	group by tracks.id
	order by dynamicplaylist_random_works.album,tracks.disc,tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_works;
