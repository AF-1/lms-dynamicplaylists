-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_WORKS_LEASTPLAYED
-- PlaylistGroups:Works
-- PlaylistCategory:works
-- PlaylistLMSminVersion: 9.0.0
-- PlaylistAPCdupe:yes
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_works;
create temporary table dynamicplaylist_random_works as
	select leastplayed.album as album, leastplayed.work as work, leastplayed.performance as performance from
		(select t.album as album, t.work as work, t.performance as performance, sum(t.playcount) as sumcount, count(distinct t.id) as totaltrackcount
		from (
			select tracks.id, tracks.urlmd5, tracks.album, tracks.work, tracks.performance,
				ifnull(tracks_persistent.playCount, 0) as playcount
			from tracks
			join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
			where tracks.audio = 1
				and tracks.work is not null
			group by tracks.id
		) as t
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
		group by case when t.performance is not null then t.performance else t.work end
		having totaltrackcount >= 'PlaylistMinAlbumTracks'
		order by sumcount asc, random()
		limit 30) as leastplayed
	order by random()
	limit 1;
select distinct tracks.id, tracks.primary_artist from tracks
	join dynamicplaylist_random_works on (tracks.album = dynamicplaylist_random_works.album and tracks.work = dynamicplaylist_random_works.work and case when dynamicplaylist_random_works.performance is not null then tracks.performance = dynamicplaylist_random_works.performance else 1 end)
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
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
	order by dynamicplaylist_random_works.album, tracks.disc, tracks.tracknum
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_works;
