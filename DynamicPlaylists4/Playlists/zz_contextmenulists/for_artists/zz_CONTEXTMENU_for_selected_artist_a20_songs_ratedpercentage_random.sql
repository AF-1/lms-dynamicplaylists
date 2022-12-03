-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_ARTIST_SONGS_PERCENTAGERATED
-- PlaylistGroups:Context menu lists/ artist
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:artists
-- PlaylistParameter1:artist:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTARTIST:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPERCENTAGERATED:0:0%,10:10%,20:20%,30:30%,40:40%,50:50%,60:60%,70:70%,80:80%,90:90%,100:100%
-- PlaylistParameter3:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists randomweightedratingshigh;
drop table if exists randomweightedratingslow;
drop table if exists randomweightedratingscombined;
create temporary table randomweightedratingslow as select tracks.id, tracks.primary_artist from tracks
	join contributor_track on
		contributor_track.track = tracks.id and contributor_track.contributor = 'PlaylistParameter1'
	left join library_track on
		library_track.track = tracks.id
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) = 0
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
		and
			case
				when 'PlaylistParameter3' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter3' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
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
	limit (100-'PlaylistParameter2');
create temporary table randomweightedratingshigh as select tracks.id, tracks.primary_artist from tracks
	join contributor_track on
		contributor_track.track = tracks.id and contributor_track.contributor = 'PlaylistParameter1'
	left join library_track on
		library_track.track = tracks.id
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) > 0
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
		and
			case
				when 'PlaylistParameter3' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter3' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
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
	limit 'PlaylistParameter2';
create temporary table randomweightedratingscombined as select * from randomweightedratingslow union select * from randomweightedratingshigh;
	select * from randomweightedratingscombined
	order by random()
	limit 'PlaylistLimit';
drop table randomweightedratingshigh;
drop table randomweightedratingslow;
drop table randomweightedratingscombined;
