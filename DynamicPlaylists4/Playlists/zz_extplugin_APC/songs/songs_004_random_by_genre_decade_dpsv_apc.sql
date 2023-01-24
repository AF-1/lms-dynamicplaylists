-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_SONGS_RANDOM_GENRE_DECADE_DPSV_APC
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistUseCache: 1
-- PlaylistParameter1:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES:
-- PlaylistParameter2:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
-- PlaylistParameter3:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMAXDPSV:100:100,90:90,80:80,70:70,60:60,50:50,40:40,30:30,20:20,10:10,0:0,-10:-10,-20:-20,-30:-30,-40:-40,-50:-50,-60:-60,-70:-70,-80:-80,-90:-90
-- PlaylistParameter4:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINDPSV:-100:-100,-90:-90,-80:-80,-70:-70,-60:-60,,-50:-50,-40:-40,-30:-30,-20:-20,-10:-10,0:0,10:10,20:20,30:30,40:40,50:50,60:60,70:70,80:80,90:90
select tracks.id, tracks.primary_artist from tracks
	join genre_track on
		genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter1')
	left join library_track on
		library_track.track = tracks.id
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
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
		and ifnull(tracks.year, 0) in ('PlaylistParameter2')
		and ifnull(alternativeplaycount.dynPSval, 0) <= 'PlaylistParameter3'
		and ifnull(alternativeplaycount.dynPSval, 0) >= 'PlaylistParameter4'
	group by tracks.id
