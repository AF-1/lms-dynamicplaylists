-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_ARTISTS_NEVERPLAYED_APC
-- PlaylistGroups:Artists
-- PlaylistCategory:artists
drop table if exists dynamicplaylist_random_contributors;
create temporary table dynamicplaylist_random_contributors as
	select contributor_track.contributor as contributor, count(distinct tracks.id) as totaltrackcount from tracks
		join contributor_track on contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
		join alternativeplaycount on alternativeplaycount.urlmd5 = tracks.urlmd5
		left join library_track on library_track.track = tracks.id
		left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			tracks.audio = 1
			and dynamicplaylist_history.id is null
			and contributor_track.contributor != 'PlaylistVariousArtistsID'
			and not exists (select * from tracks t2, genre_track, genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
		group by contributor_track.contributor
		having totaltrackcount >= 'PlaylistMinArtistTracks'
			and not exists (
				select 1 from tracks t3
				join contributor_track ct2 on ct2.track = t3.id and ct2.role in (1,4,5,6)
				join alternativeplaycount apc2 on apc2.urlmd5 = t3.urlmd5
				where ct2.contributor = contributor_track.contributor
				and ifnull(apc2.playCount, 0) > 0
			)
		order by random()
		limit 1;
select distinct tracks.id, tracks.primary_artist from tracks
	join contributor_track on contributor_track.track = tracks.id and contributor_track.role in (1,4,5,6)
	join dynamicplaylist_random_contributors on dynamicplaylist_random_contributors.contributor = contributor_track.contributor
	left join library_track on library_track.track = tracks.id
	left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
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
		and not exists (select * from tracks t2, genre_track, genres
						where
							t2.id = tracks.id and
							tracks.id = genre_track.track and
							genre_track.genre = genres.id and
							genres.namesearch in ('PlaylistExcludedGenres'))
	order by dynamicplaylist_random_contributors.contributor, random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_contributors;
