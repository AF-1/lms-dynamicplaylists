-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_ARTISTS_LEASTPLAYEDAVG
-- PlaylistGroups:Artists
-- PlaylistCategory:artists
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_contributors;
create temporary table dynamicplaylist_random_contributors as
	select leastavgplayed.contributor as contributor from
		(select ct.contributor as contributor, avg(t.playcount) as avgcount, count(distinct t.id) as totaltrackcount
		from (
			select tracks.id, tracks.urlmd5,
				ifnull(tracks_persistent.playCount, 0) as playcount
			from tracks
			join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
			where tracks.audio = 1
		) as t
		join (
			select distinct track, contributor
			from contributor_track
			where role in (1,4,5,6)
		) as ct on ct.track = t.id
		left join dynamicplaylist_history on dynamicplaylist_history.id = t.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			dynamicplaylist_history.id is null
			and ct.contributor != 'PlaylistVariousArtistsID'
			and not exists (select * from tracks t2, genre_track, genres
							where
								t2.id = t.id and
								t2.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then exists (select 1 from library_track where library_track.track = t.id and library_track.library = 'PlaylistCurrentVirtualLibraryForClient')
					else 1
				end
		group by ct.contributor
		having totaltrackcount >= 'PlaylistMinArtistTracks'
		order by avgcount asc, random()
		limit 30) as leastavgplayed
	order by random()
	limit 1;
select distinct tracks.id, tracks.primary_artist from tracks
	join contributor_track on contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
	join dynamicplaylist_random_contributors on dynamicplaylist_random_contributors.contributor = contributor_track.contributor
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
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.namesearch in ('PlaylistExcludedGenres'))
	order by dynamicplaylist_random_contributors.contributor, random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_contributors;
