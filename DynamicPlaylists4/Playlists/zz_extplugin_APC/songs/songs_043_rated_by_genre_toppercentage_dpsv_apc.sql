-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_SONGS_RATED_GENRE_MINDPSV_PERCENTAGETOPRATED_APC
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistParameter1:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPERCENTAGETOPRATED:0:0%,10:10%,20:20%,30:30%,40:40%,50:50%,60:60%,70:70%,80:80%,90:90%,100:100%
-- PlaylistParameter3:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINDPSV:-100:-100,-90:-90,-80:-80,-70:-70,-60:-60,-50:-50,-40:-40,-30:-30,-20:-20,-10:-10,0:0,10:10,20:20,30:30,40:40,50:50,60:60,70:70,80:80,90:90
drop table if exists randomweightedratingshigh;
drop table if exists randomweightedratingslow;
drop table if exists randomweightedratingscombined;
create temporary table randomweightedratingslow as select tracks.id, tracks.primary_artist from tracks
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) > 0 and tracks_persistent.rating < 'PlaylistTopRatedMinRating'
	join genre_track on genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter1')
	join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and ifnull(alternativeplaycount.dynPSval, 0) >= 'PlaylistParameter3'
	group by tracks.id
	order by random()
	limit (100-'PlaylistParameter2');
create temporary table randomweightedratingshigh as select tracks.id, tracks.primary_artist from tracks
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistTopRatedMinRating'
	join genre_track on genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter1')
	join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and ifnull(alternativeplaycount.dynPSval, 0) >= 'PlaylistParameter3'
	group by tracks.id
	order by random()
	limit 'PlaylistParameter2';
create temporary table randomweightedratingscombined as select * from randomweightedratingslow union select * from randomweightedratingshigh;
	select * from randomweightedratingscombined
	order by random()
	limit 'PlaylistLimit';
drop table randomweightedratingshigh;
drop table randomweightedratingslow;
drop table randomweightedratingscombined;
