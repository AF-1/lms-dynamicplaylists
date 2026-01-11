-- PlaylistName:Material HE Test Random Albums Multigenres
-- PlaylistGroups:Home extras menus
-- PlaylistCategory:albums
-- PlaylistMenuListType:homeextrasmenu

select albums.id from albums
	join tracks on albums.id = tracks.album
	join genre_track on genre_track.track = tracks.id
	join genres on genres.id = genre_track.genre and genres.namesearch in ('HEAVY METAL','HIP HOP','HIP HOP RAP','PUNK','SAMBA')
	WHERE
		tracks.audio = 1
group by albums.id
order by random()
limit 5;
