-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_SONGS_PERCENTAGEPLAYLIST_GENRE_DECADE_MINRATING_NOTRECENTLYPLAYED_APC
-- PlaylistGroups:Songs
-- PlaylistCategory:songs
-- PlaylistParameter1:multiplestaticplaylists:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPLAYLISTS:
-- PlaylistParameter2:multiplegenres:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRES_LOCAL:
-- PlaylistParameter3:multipledecades:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTDECADES:
-- PlaylistParameter4:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTPERCENTAGEPLAYLIST:0:0%,10:10%,20:20%,30:30%,40:40%,50:50%,60:60%,70:70%,80:80%,90:90%,100:100%
-- PlaylistParameter5:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SONGS_IGNORERECENTLYPLAYED:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_ALL,604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_1WEEK,1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_2WEEKS,2592000:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_4WEEKS,7948800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_3MONTHS,15811200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_6MONTHS,31536000:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTRECENTLYPLAYEDPERIOD_12MONTHS
-- PlaylistParameter6:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTMINRATING:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_UNRATED,20:*,40:**,60:***,80:****,100:*****
drop table if exists randomweightedplaylisttracks;
drop table if exists randomweightedlibrarylocal;
drop table if exists randomweightedlibrarycombined;
create temporary table randomweightedlibrarylocal as select tracks.id, tracks.primary_artist from tracks
	join genre_track on
		genre_track.track = tracks.id and genre_track.genre in ('PlaylistParameter2')
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistParameter6'
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and ifnull(tracks.year, 0) in ('PlaylistParameter3')
		and
			case
				when 'PlaylistParameter5' > 0 then (ifnull(alternativeplaycount.lastPlayed, 0) < (strftime('%s',DATE('NOW')) - ('PlaylistParameter5')))
				else 1
			end
	group by tracks.id
	order by random()
	limit (100 - 'PlaylistParameter4');
create temporary table randomweightedplaylisttracks as select tracks.id, tracks.primary_artist from tracks
	join playlist_track on
		playlist_track.track = tracks.url and playlist_track.playlist in ('PlaylistParameter1')
	join tracks_persistent on
		tracks_persistent.urlmd5 = tracks.urlmd5 and ifnull(tracks_persistent.rating, 0) >= 'PlaylistParameter6'
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
	left join dynamicplaylist_history on
		dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and dynamicplaylist_history.id is null
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and ifnull(tracks.year, 0) in ('PlaylistParameter3')
		and
			case
				when 'PlaylistParameter5' > 0 then (ifnull(alternativeplaycount.lastPlayed, 0) < (strftime('%s',DATE('NOW')) - ('PlaylistParameter5')))
				else 1
			end
	group by tracks.id
	order by random()
	limit 'PlaylistParameter4';
create temporary table randomweightedlibrarycombined as select * from randomweightedlibrarylocal union select * from randomweightedplaylisttracks;
	select * from randomweightedlibrarycombined
	order by random()
	limit 'PlaylistLimit';
drop table randomweightedplaylisttracks;
drop table randomweightedlibrarylocal;
drop table randomweightedlibrarycombined;
