-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_SONGS_RANDOM_DPSV_APC
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistUseCache: 1
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMAXDPSV:100:100,90:90,80:80,70:70,60:60,50:50,40:40,30:30,20:20,10:10,0:0,-10:-10,-20:-20,-30:-30,-40:-40,-50:-50,-60:-60,-70:-70,-80:-80,-90:-90
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINDPSV:-100:-100,-90:-90,-80:-80,-70:-70,-60:-60,-50:-50,-40:-40,-30:-30,-20:-20,-10:-10,0:0,10:10,20:20,30:30,40:40,50:50,60:60,70:70,80:80,90:90
select tracks.id, tracks.primary_artist from tracks
	left join library_track on
		library_track.track = tracks.id
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
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
		and ifnull(alternativeplaycount.dynPSval, 0) <= 'PlaylistParameter1'
		and ifnull(alternativeplaycount.dynPSval, 0) >= 'PlaylistParameter2'
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.name in ('PlaylistExcludedGenres'))
	group by tracks.id
