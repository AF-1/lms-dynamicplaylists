# Dynamic Playlists - Home Extras Test Branch

I've stopped working on the home extras branch. But I will leave it here in case somebody else wants to take a shot at this and maybe push a PR.

Use the Home Extras example sql file *material_he_test_rnd_albums_multigenres.sql* to test the albums home extra. Change the genres if it doesn't get enough albums.

1. Move the sql file to the folder *DPL-custom-lists**. The parent folder is probably the one with the persist.db file unless you changed that in the plugin settings.

2. Enter the *Dynamic Playlists* (DPL) menu from the LMS home menu to make DPL pick up the example sql file (or any changes made to it).

3. In the DPL plugin settings you can link it to *Dynamic Album Discovery 1*, the Material Home Extras menu item.

4. The relevant lines in Plugin.pm start at line 7403.
