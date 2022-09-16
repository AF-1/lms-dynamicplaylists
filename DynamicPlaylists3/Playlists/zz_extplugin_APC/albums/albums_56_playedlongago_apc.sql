-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS3_BUILTIN_PLAYLIST_ALBUMS_PLAYEDLONGAGO_APC
-- PlaylistGroups:Albums
-- PlaylistCategory:albums
-- PlaylistTrackOrder:ordered
-- PlaylistLimitOption:unlimited
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_INCLUDECOMPIS:0:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_ALBUMS_ALL,1:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_ALBUMS_COMPISONLY,2:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_ALBUMS_NOCOMPIS
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS3_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS3_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_albums;
create temporary table dynamicplaylist_random_albums as
	select distinct tracks.album as album, count(distinct tracks.id) as totaltrackcount from tracks
		join albums on
			albums.id = tracks.album
		join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		left join library_track on
			library_track.track = tracks.id
		left join dynamicplaylist_history on
			dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
		where
			tracks.audio = 1
			and dynamicplaylist_history.id is null
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient'!='' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
			and not exists (select * from tracks t2, genre_track, genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.name in ('PlaylistExcludedGenres'))
		group by tracks.album
			having totaltrackcount >= 'PlaylistMinAlbumTracks' and (strftime('%s',DATE('NOW','-'PlaylistPeriodPlayedLongAgo' YEAR')) - max(ifnull(alternativeplaycount.lastPlayed,0))) > 0
			and
				case
					when 'PlaylistParameter1'=1 then ifnull(albums.compilation, 0) = 1
					when 'PlaylistParameter1'=2 then ifnull(albums.compilation, 0) = 0
					else 1
				end
		order by random()
		limit 1;
select distinct tracks.url from tracks
	join dynamicplaylist_random_albums on
		dynamicplaylist_random_albums.album = tracks.album
	join alternativeplaycount on
		alternativeplaycount.urlmd5 = tracks.urlmd5
	left join library_track on
		library_track.track = tracks.id
	left join dynamicplaylist_history on
		dynamicplaylist_history.id=tracks.id and dynamicplaylist_history.client='PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter2'=1 then ifnull(alternativeplaycount.playCount, 0) = 0
				when 'PlaylistParameter2'=2 then ifnull(alternativeplaycount.playCount, 0) > 0
				else 1
			end
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.name in ('PlaylistExcludedGenres'))
	group by tracks.id
	order by
		case
			when 'PlaylistTrackOrder' = 1 then "dynamicplaylist_random_albums.album, tracks.disc, tracks.tracknum"
		else
			"dynamicplaylist_random_albums.album, random()"
		end
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_albums;
