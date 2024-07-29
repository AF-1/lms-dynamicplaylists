-- PlaylistName:PLUGIN_DYNAMICPLAYLISTS4_BUILTIN_PLAYLIST_GENRES_RECENTLYPLAYEDORLASTADDEDSONGS
-- PlaylistGroups:Genres
-- PlaylistCategory:genres
-- PlaylistAPCdupe:yes
-- PlaylistParameter1:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_GENRES_RECENTLYPLAYED:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_GENRES_ALL,1:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_GENRES_RECENTLYPLAYEDSONGS,2:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_GENRES_NORECENTLYPLAYEDSONGS
-- PlaylistParameter2:list:PLUGIN_DYNAMICPLAYLISTS4_PARAMNAME_SELECTLASTADDEDPERIOD_GENRES:0:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_ALL,604800:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_1WEEK,1209600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_2WEEKS,2419200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_4WEEKS,7257600:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_3MONTHS,14515200:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_6MONTHS,29030399:PLUGIN_DYNAMICPLAYLISTS4_PARAMVALUENAME_SELECTLASTADDEDPERIOD_12MONTHS
drop table if exists dynamicplaylist_random_genres;
create temporary table dynamicplaylist_random_genres as
	select genre_track.genre as genre from genre_track
		join tracks on genre_track.track = tracks.id
		left join library_track on library_track.track = tracks.id
		join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5
		left join dynamicplaylist_history on dynamicplaylist_history.id = tracks.id and dynamicplaylist_history.client = 'PlaylistPlayer'
		where
			genre_track.genre is not null
			and dynamicplaylist_history.id is null
			and not exists (select * from tracks t2,genre_track,genres
							where
								t2.id = tracks.id and
								tracks.id = genre_track.track and
								genre_track.genre = genres.id and
								genres.namesearch in ('PlaylistExcludedGenres'))
			and
				case
					when 'PlaylistParameter1' = 1 then ((strftime('%s',DATE('NOW','-'PlaylistPeriodRecentlyPlayed' DAY'))-ifnull(tracks_persistent.lastPlayed,0)) < 0)
					else 1
				end
			and
				case
					when 'PlaylistParameter2'>0 then (tracks_persistent.added >= (select max(ifnull(tracks_persistent.added,0)) from tracks_persistent) - 'PlaylistParameter2')
					else 1
				end
			and
				case
					when ('PlaylistCurrentVirtualLibraryForClient' != '' and 'PlaylistCurrentVirtualLibraryForClient' is not null)
					then library_track.library = 'PlaylistCurrentVirtualLibraryForClient'
					else 1
				end
		group by genre_track.genre
			having
					case
						when 'PlaylistParameter1' = 2 then ((strftime('%s',DATE('NOW','-'PlaylistPeriodRecentlyPlayed' DAY'))-max(ifnull(tracks_persistent.lastPlayed,0))) > 0)
						else 1
					end
		order by random()
		limit 1;
select tracks.id, tracks.primary_artist from tracks
	join genre_track on genre_track.track = tracks.id
	join dynamicplaylist_random_genres on dynamicplaylist_random_genres.genre = genre_track.genre
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
	group by tracks.id
	order by random()
	limit 'PlaylistLimit';
drop table dynamicplaylist_random_genres;
