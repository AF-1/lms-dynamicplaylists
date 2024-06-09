-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_WORKS_MOSTPLAYEDAVG
-- PlaylistGroups:Works
-- PlaylistCategory:works
-- PlaylistLMSminVersion: 9.0.0
-- PlaylistAPCdupe:yes
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_works;
create temporary table dynamicplaylist_random_works as
	select mostavgplayed.album as album, mostavgplayed.work as work, mostavgplayed.performance as performance from
		(select tracks.album as album, tracks.work as work, tracks.performance as performance, avg(ifnull(tracks_persistent.playCount,0)) as avgcount, count(distinct tracks.id) as totaltrackcount from tracks
		left join library_track on
			library_track.track = tracks.id
		join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
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
		group by case when tracks.performance is not null then tracks.performance else tracks.work end
			having totaltrackcount >= 'PlaylistMinAlbumTracks'
		order by avgcount desc, random()
		limit 30) as mostavgplayed
	order by random()
	limit 1;
select tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_works on (tracks.album = dynamicplaylist_random_works.album and tracks.work = dynamicplaylist_random_works.work and case when dynamicplaylist_random_works.performance is not null then tracks.performance = dynamicplaylist_random_works.performance else 1 end)
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5
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
				when 'PlaylistParameter1' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter1' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
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
