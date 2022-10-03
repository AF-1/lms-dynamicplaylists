-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS3_BUILTIN_PLAYLIST_SONGS_RATED_PERCENTAGETOPRATED
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_SELECTPERCENTAGETOPRATED:0:0%,10:10%,20:20%,30:30%,40:40%,50:50%,60:60%,70:70%,80:80%,90:90%,100:100%
drop table if exists randomweightedratingshigh;
drop table if exists randomweightedratingslow;
drop table if exists randomweightedratingscombined;
create temporary table randomweightedratingslow as select distinct tracks.url as url from tracks
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) > 0 and tracks_persistent.rating < 'PlaylistTopRatedMinRating'
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
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
	group by tracks.id
	order by random()
	limit (100-'PlaylistParameter1');
create temporary table randomweightedratingshigh as select distinct tracks.url as url from tracks
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistTopRatedMinRating'
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
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
	group by tracks.id
	order by random()
	limit 'PlaylistParameter1';
create temporary table randomweightedratingscombined as select * from randomweightedratingslow union select * from randomweightedratingshigh;
	select * from randomweightedratingscombined
	order by random()
	limit 'PlaylistLimit';
drop table randomweightedratingshigh;
drop table randomweightedratingslow;
drop table randomweightedratingscombined;
