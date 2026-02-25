-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_CONTEXT_GENRE_ARTISTS_MOSTPLAYED
-- PlaylistGroups:Context menu lists/ genre
-- PlaylistMenuListType:contextmenu
-- PlaylistCategory:genres
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:genre:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTGENRE:
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_INCLUDESONGS:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_UNPLAYED,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SONGS_PLAYED
drop table if exists dynamicplaylist_random_contributors;
create temporary table dynamicplaylist_random_contributors as
	select mostplayed.contributor as contributor from
		(select t.contributor as contributor, sum(t.playcount) as sumcount, count(distinct t.id) as totaltrackcount
		from (
			select tracks.id, contributor_track.contributor,
				ifnull(tracks_persistent.playCount, 0) as playcount
			from tracks
			join contributor_track on contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
			join genre_track on genre_track.track = tracks.id and genre_track.genre = 'PlaylistParameter1'
			join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
			where tracks.audio = 1
				and contributor_track.contributor != 'PlaylistVariousArtistsID'
				and not exists (select * from tracks t2,genre_track,genres
					where t2.id = tracks.id and tracks.id = genre_track.track
					and genre_track.genre = genres.id and genres.namesearch in ('PlaylistExcludedGenres'))
			group by tracks.id, contributor_track.contributor
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
		group by t.contributor
		having totaltrackcount >= 'PlaylistMinArtistTracks'
		order by sumcount desc, random()
		limit 30) as mostplayed
	order by random()
	limit 1;
select distinct tracks.id, tracks.primary_artist from tracks
	join contributor_track on contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
	join dynamicplaylist_random_contributors on dynamicplaylist_random_contributors.contributor = contributor_track.contributor
	join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
	join genre_track on genre_track.track = tracks.id and genre_track.genre = 'PlaylistParameter1'
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
	where
		tracks.audio = 1
		and tracks.secs >= 'PlaylistTrackMinDuration'
		and dynamicplaylist_history.id is null
		and
			case
				when 'PlaylistParameter2' = 1 then ifnull(tracks_persistent.playCount, 0) = 0
				when 'PlaylistParameter2' = 2 then ifnull(tracks_persistent.playCount, 0) > 0
				else 1
			end
		and
			case
				when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
				then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
				else 1
			end
	order by dynamicplaylist_random_contributors.contributor, random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_contributors;
