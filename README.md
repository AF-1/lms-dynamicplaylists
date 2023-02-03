Dynamic Playlists
====

This plugin<sup>1</sup> lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
*Dynamic Playlists* will keep adding small batches of tracks in random order to your current playlist (complete albums can be added in album order). It comes with a collection of built-in, ready-to-use dynamic playlists to get you started. At some point you'll probably want to create a dynamic playlist that's tailored to your very specific needs because the <i>built-in</i> dynamic playlists cannot cover all possible use cases.<br><br>
Some preferences are not enabled by default. Please take a look at the preferences and their descriptions on the plugin's settings page.
<br><br>
[⬅️ **Back to the list of all plugins**](https://github.com/AF-1/)
<br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br><br>

## Installation
⚠️ **Please read the [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq) *before* installing this plugin.**<br>

You should be able to install **Dynamic Playlists** from the LMS main repository (LMS plugin library):<br>**LMS > Settings > Plugins**.<br>

If you want to test a new patch that hasn't made it into a release version yet or you need to install a previous version, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).

It usually takes a few hours for a *new* release to be listed on the LMS plugin page.
<br><br><br><br>


## Features:
* Use **your own custom dynamic playlist files/definitions directly in DPL** without intermediary plugins - you don't have to install other plugins to get dynamic playlists. See [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq).
* Comes with more than 200 ready-to-use dynamic playlists (stand-alone + for context menus).
* **Multiple** selection of *genres*, *decades*, *years* and *static playlists*
* **Pre**select multiple *artists* or *albums* from their context menu at your leisure. DPL remembers your **pre**selection so that you can easily use it later with dynamic playlists that use **preselection**.
* Use LMS **virtual libraries**.
* Save dynamic playlists with (user input) parameters to LMS **favourites** (see [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq)).
* Create a *Don't Stop the Music* seed list and auto-start your DSTM mix.
* New playlist parameters (see [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)).
* New preference options (e.g. balanced shuffle) and UI changes.
* Compatible with [**Custom Skip**](https://github.com/AF-1/lms-customskip#custom-skip), [**Alternative Play Count**](https://github.com/AF-1/lms-alternativeplaycount) and [**Dynamic Playlist Creator**](https://github.com/AF-1/lms-dynamicplaylistcreator#dynamic-playlist-creator).
* If you have installed the [**Alternative Play Count**](https://github.com/AF-1/lms-alternativeplaycount) plugin, you will see some additional dynamic playlists that use the data from this plugin.
* Use dynamic playlists to create *static* playlists
* …
<br><br><br><br>


## Context Menus
While the Dynamic Playlists menu in the LMS home menu is easy to find, its **context menus** can easily be overlooked. You'll find the **Dynamic Playlists menus** in the *context menus* for **artists**, **albums**, **genres**, **years** (for years and decades) and **static playlists**. Some of them are presented below.
<br><br>

### Players with Jivlite UI (Touch, piCorePlayer, SqueezePlay, Radio)
![Players with Jivlite UI (Touch, piCorePlayer, SqueezePlay, Radio)](screenshots/jivelite.gif)
<hr><br>

### LMS Web UI - Default Skin
![LMS Web UI - Default Skin](screenshots/defaultskin.gif)
<hr><br>

### Material Web UI
![Material Web UI](screenshots/material.gif)
<br><br><br><br>


## Reporting a bug

If you think that you've found a bug, open an [**issue here on GitHub**](https://github.com/AF-1/lms-dynamicplaylists/issues) and fill out the ***Bug report* issue template**. Please post bug reports **only** on **GitHub**.
<br><br><br><br>


## FAQ

<details><summary>»<b>What do I need to consider when <i>upgrading</i> from version 3 ➞ 4?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>Can I downgrade from version 4 ➞ 3?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What's changed in version 4?</b>«</summary><br><p>

- <b>Changes</b><br><br>For dynamic playlists that can retrieve <b>all</b> tracks matching your search parameters in <b>one initial</b> database query, DPL version <b>4</b> loads <b>all</b> tracks into the <b>cache</b>, thus eliminating the need for further database queries. Subsequent batches of new tracks for the active dynamic playlist will be retrieved <b>from the cache only</b>, and added to a client's playlist <b>much faster</b> as a result.<br>Dynamic playlists that retrieve each batch of new tracks from a different, randomly chosen artist, album, genre, year, decade or static playlist are <b>not</b> suitable for cache use because not all tracks can be retrieved in one initial database query.<br>Furthermore, you can use dynamic playlists to create <i>static</i> playlists and select LMS's <i>balanced shuffle mode</i> as the default plugin shuffle method in the settings now.<br><br>
⚠️ Unlike previous versions, DPL <b>4</b> uses track <b>id</b>s (and not track <b>url</b>s) to cache, sort or shuffle (huge result sets of) tracks.<br>Therefore, version <b>4</b> is <b>no longer compatible with old plugins like SQLPlayList that return track <i>urls</i></b> instead of track <i>ids</i> (see <b>up</b>grading section below).
<br><br>

- <b>Up</b>grading 3 ➞ <b>4</b><br><br>Please <b>don't use version 3 <i>and</i> version 4 <i>at the same time</i></b>. Uninstall version 3, then install version 4.<br>Since version <b>4</b> expects the <b>id</b> (instead of the <i>url</i>) and the primary artist (used for LMS's balanced shuffling) for each track, you need to <b>make your <i>custom</i> dynamic playlists compatible with version 4</b>. It's rather easy:<br>
	- If you used the <a href="https://github.com/AF-1/lms-dynamicplaylistcreator"><b>Dynamic Playlist Creator</b></a> plugin to create your <i>custom</i> dynamic playlist, just click on the <b>Edit</b> button next to its name and simply <b>save</b> it again. <i>Dynamic Playlist Creator</i> will save it in a version compatible with the currently installed version of DPL. That's it.

	- If you have <b>manually created</b> <i>custom</i> dynamic playlists (<b>customized SQLite statements</b>) in the <b>DPL-custom-lists</b> folder, you simply need to replace instances of<br><br>
	&nbsp;&nbsp;&nbsp;&nbsp;<i>select <b>tracks.url</b> from tracks</i><br><br>
	with<br><br>
	&nbsp;&nbsp;&nbsp;&nbsp;<i>select <b>tracks.id, tracks.primary_artist</b> from tracks</i><br><br>
	Save a backup of your manually created custom dynamic playlists <b>before</b> you change them. If you ever wish to downgrade to version 3, you can just use the old dynamic playlists from your backup.
<br><br>

- <b>Down</b>grading 4 ➞ <b>3</b><br><br>The last version <b>3</b> of <i>Dynamic Playlists</i> will remain available for download here to allow you to downgrade at any time. It will, however, no longer be available from the LMS main repository because it won't receive further updates and should be considered deprecated.<br><br>
You can either install the last version 3 manually or add the version 3 repository URL below at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply*:<br><br>
[**https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/repo.xml**](https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/repo.xml)<br><br>
<i>Custom</i> dynamic playlists compatible with version <b>3</b> need to return track <b>urls</b>. For details, refer to the <b>up</b>grade section above.
</p></details><br>

<details><summary>»<b>With which plugins does DPL work?</b>«</summary><br><p>

DPL 4 is compatible with <a href="https://github.com/AF-1/lms-dynamicplaylistcreator"><b>Dynamic Playlist Creator</b></a>, <a href="https://github.com/AF-1/lms-alternativeplaycount"><b>Alternative Play Count</b></a> and <a href="https://github.com/AF-1/lms-customskip#custom-skip"><b>Custom Skip 3</b></a>.<br>

- <b>CustomScan</b>: could work, not tested. Compatibility not guaranteed, not supported by me.<br>

- <b>SQLPlayList</b>: does <b>NOT</b> work with DPL version <b>4</b>. Compatibility with DPL version 3 not guaranteed, <b>not supported by me</b>. Alternatively, you can give the <a href="https://github.com/AF-1/lms-dynamicplaylistcreator#dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a> plugin a try if you use DPL version **4**.<br>

- <b>TrackStat</b>: <b>not</b> supported because no longer needed. LMS keeps track of ratings, play counts and date last played in its own database table.<br>

- <b>MultiLibrary</b>: <b>not</b> supported because no longer needed. Please considering using native LMS <b>virtual libraries</b>. You can easily create new virtual libraries using saved <b>advanced search</b>es. Or, if you're a little familiar with SQLite, there's the [<b>SQLite Virtual Libraries</b>](https://github.com/AF-1/lms-sqlitevirtuallibraries) plugin that lets you use SQLite statements to create virtual libraries.
</p></details><br>

<details><summary>»<b>How do I create / add my own <i>custom</i> dynamic playlist?</b>«</summary><br><p>

- If you prefer a <b>GUI</b> and want an <b>easy</b> way to create a <i>custom</i> dynamic playlist without having to deal with SQLite, take a look at the <a href="https://github.com/AF-1/lms-dynamicplaylistcreator"><b>Dynamic Playlist Creator</b></a> plugin that uses templates to create dynamic playlists and makes them available to DPL <b>4</b>. If you still use the deprecated DPL version 3, you could try the SQLPlayList plugin.

- If you are <b>familiar with database queries and SQLite</b>, you can create a fully customized dynamic playlist in a plain text editor of your choice and use it directly in DPL.<br>Dynamic playlist definitions are basically plain text files with an "<b>sql</b>" file extension that contain your playlist definition:<br>
	- a couple of <b>parameters</b> (<i>general</i> parameters like the playlist name, group or category and <i>user input</i> parameters) and
	- the <b>SQLite statement</b> itself to fetch tracks from the LMS database.<br><br>

	Whether you use a <i>built-in</i> dynamic playlist as a template or start from scratch, this will give you a great deal of freedom in creating dynamic playlists tailored to your specific needs.<br>
In any case <b>please read the <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format">wiki</b></a> for more information on the dynamic playlist <b>format</b> and the few playlist parameters that you should definitely include.<br>Put your custom dynamic playlist <b>file</b> (with the <b>sql</b> file extension) in DPL's <i>folder for custom dynamic playlists</i> called <b>DPL-custom-lists</b>.<sup>2</sup> The new dynamic playlist should now be listed in DPL, either in the <i>Not classified</i> group or in other groups according to what the <code>-- PlaylistGroups</code> parameter in your playlist definition says.<br><br>
</p></details><br>

<details><summary>»<b>Can I save the results of a dynamic playlist as a <i>static</i> playlist?</b>«</summary><br><p>
Version <b>4</b> allows you to save the result set of any dynamic playlist as a <i>static</i> playlist. There's a control icon in the Dynamic Playlists menu (LMS default skin) next to the names of dynamic playlists that looks a bit like an old floppy disk. In Material and jivelite GUI controllers, you get a new option “<i>Save as static playlist</i>“ in addition to <i>Play</i> and <i>Add</i>. You only need to set the maximum number of tracks (max. 4000) and the name of your static playlist. Dynamic playlists <b>with</b> user-input parameters will request that input first and show you the static playlist options (max. track no., playlist name, track sort order) at the end.<br>
Depending on the complexity of your dynamic playlist and the max. track limit you set for your <i>static</i> playlist, saving it might take a while.
</p></details><br>

<details><summary>»<b>What's <i>preselection</i>? How does it work?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>There's more than one DPL context menu item.</b>«</summary><br><p>
DPL has playlist parameters that allow you to select <b>multiple</b> genres, decades, years and static playlist. But even the smallest music libraries have a large number of <b>artists</b> and <b>albums</b> that would result in poorly browsable, far too long selection lists. The solution is to gather/select artists or albums <i>first</i> using the <b>preselection</b> context menu item and then start a dynamic playlist for preselected artists/albums.<br>
So for <b>artists</b> and <b>albums</b> DPL will show a <b>second <i>context</i> menu</b> that allows you to <b>preselect</b> this artist/album while browsing your music library. DPL will remember your (pre)selection <i>until the next LMS restart/rescan</i> <sup>3</sup>.<br>Once you've finished preselecting artists/albums, go to DPL's home menu and use this selection with any dynamic playlist that makes use of the <code>PlaylistPreselectedArtists</code> or <code>PlaylistPreselectedAlbums</code> playlist parameter. There are some built-in dynamic playlists to get you started (in the <i>Songs</i> group). And it's very easy to add these playlist parameters to your custom dynamic playlists. Read this <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#user-input-parameters"><b>wiki</b></a> section for more information.
</p></details><br>

<details><summary>»<b>How does DPL work with the <i>Don't Stop the Music</i> plugin?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What does the icon with the infinity symbol do?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What does “<i>Create DSTM seed list and play</i>“ mean?</b>«</summary><br><p>
The <i>Don't Stop the Music</i> (DSTM) plugin “will automatically add similar music to what you've been listening to ... once you've reached the end of your playlist“. DSTM takes a look at the existing tracks in your client's playlist (the <i>seed list</i>) to determine what kind of tracks to search for.<br><br>As long as <i>Dynamic Playlists</i> is <b>active</b>, i.e. playing a dynamic playlist, DSTM will <b>not</b> interfere and add tracks.<br><br>But now you can use <i>Dynamic Playlists</i> to create a DSTM seed list from any dynamic playlist and start a DSTM mix for you. There's a preference setting if you prefer to skip playback of all seed list tracks (but the last one).
</p></details><br>

<details><summary>»<b>How do I know whether DPL is still <i>active</i>?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What causes DPL to no longer be active?</b>«</summary><br><p>
To find out whether <i>Dynamic Playlists</i> is still <b>active</b> just enter the DPL menu from the <i>Home/My Music</i> menu. If it's still active, it will display the active dynamic playlist at the top of the DPL menu.<br>Some actions/events that stop DPL (= no longer active): clearing your client playlist, DPL no longer finds tracks for the active dynamic playlist, you told DPL to stop adding tracks...
</p></details><br>

<details><summary>»<b>I've added a dynamic playlist to my LMS favorites, but it no longer works.</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>There are some dynamic playlists that I can't add to LMS favorites.</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>DPL shows a favorite icon with a <i>p</i> (default skin) or an orange tint (classic skin) next to my dynamic playlists. Why?</b>«</summary><br><p>
Prior to <i>Dynamic Playlists <b>3</b></i>, you could <b>only</b> save <i>one-click</i> dynamic playlists as favorites that don't ask for user input when you start them.<br><br>Now you can also add dynamic playlists <b>with</b> user input parameters.<br>By <b>default</b>, <i>Dynamic Playlists</i> will <b>not</b> let you save</b> dynamic playlists as LMS favorites that ask users for <b>volatile</b> input at run-time (artist, album, genre, multiple genres, playlist or multiple playlists) because those values <b>could change after a rescan</b> and break such favorites.<br>
If you still want to add dynamic playlists with <b>volatile</b> parameter values (artist, album, genre, multiple genres, playlist or multiple playlists) to LMS favorites, you can enable this in the plugin settings. However, keep in mind that such favorites may no longer work after a rescan and you'd have to delete and <b>readd</b> them. Therefore I suggest you choose a good descriptive name so you'll remember what parameter values you chose (like "Alternative 80s rated").<br><br>
If you always select the same artists, albums, genres or playlists, it's probably better to create a <b>custom</b> dynamic playlist with the actual artist/album/genre/playlist <b>names</b>. A favorite for such a one-click dynamic playlist is not affected by rescans.<br><br>
This feature is <b>limited to the LMS web UI</b> (<i>Default</i> and <i>Classic</i> skin), <b>players with jivelite UI</b> (<i>Touch</i>, <i>Radio</i>, <i>SqueezePlay</i>, <i>piCorePlayer</i>) and <b>Material</b> skin.<br><br>
Please note: Changing the <b>file</b>name of a <i>custom</i> dynamic playlist alters its dynamic playlist <i>id</i> and thus invalidates any existing favorite for this dynamic playlist. That hasn't changed since Dynamic Playlists 2. The same applies to <i>built-in</i> dynamic playlists: If a plugin <b>update</b> changes the filename of a built-in dynamic playlist, you'll have to delete and readd favorites based on that dynamic playlist. Doesn't happen very often and always for good reasons.<br><br>
The favorite icon with the <i>p</i> (default skin) or an orange tint (classic skin) just indicates that this dynamic playlist contains <b>p</b>arameters that will ask for user input when you start it.</p></details><br>

<details><summary>»<b>The <i>Not classified</i> group in the DPL (home) menu has disappeared / doesn't show.</b>«</summary><br><p>
The <i>Not classified</i> group in the DPL (home) menu and on settings pages will only be displayed if DPL found dynamic playlists that belong in this group, i.e. if it's not empty.</p></details><br>

<details><summary>»<b>This <i>built-in</i> dynamic playlist is missing a feature that I really want.</b>«</summary><br><p>
The collection of <b>built-in</b> dynamic playlists includes only a large but limited set of frequently used playlists that won't see regular additions or updates. It can also be used as a <i>starting point</i> for creating your <b>own custom</b> dynamic playlists whose very reason for existence is to help you create dynamic playlists tailored to your <i>specific</i> needs.</p></details><br>

<details><summary>»<b>I don't want my dynamic playlist in the <i>Not classified</i> group. I want a custom group (name).</b>«</summary><br><p>
The <i>Not classified</i> group is a <i>catch-all group</i> for all dynamic playlist that are <b>not</b> assigned to any playlist <i>group</i>. You can <b>create your own custom playlist groups</b> by setting the <code>-- PlaylistGroups:</code> parameter in your dynamic playlist definition (see <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters"><b>wiki</b></a>).</p></details><br>

<details><summary>»<b>Does DPL handle online tracks?</b>«</summary><br><p>
<i>Dynamic Playlists</i> will process <b>online tracks</b> that have been <b>added to your LMS library as part of an album</b>. LMS does not import <b>single</b> online tracks or tracks of <i>online</i> <b>playlists</b> as <b>library</b> tracks and therefore they won't be processed by <i>Dynamic Playlists</i>.</p></details><br>

<details><summary>»<b>Some dynamic playlist are not sorted in alphabetical order.</b>«</summary><br><p>
In general <i>dynamic playlists</i> will <b>always</b> be listed in this order: 1. built-in, 2. custom/user-provided, 3. provided by other plugins. Dynamic playlists in the last two groups should be listed in <i>alphabetical</i> order.<br><b>Built-in</b> dynamic playlists are listed in a 'content-based' order created by me. For example, I try to group dynamic playlists together that are about ratings, play count or genre/decade selection. If you don't like how I ordered the built-in dynamic playlists, don't forget that you can clone these playlists and even put them in a custom playlist group just by adding the corresponding parameter (see <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters"><b>wiki</b></a>).<br>Static (saved) playlists will always be ordered alphabetically.
</p></details><br>

<details><summary>»<b>Can I use CLI commands to control DPL?</b>«</summary><br><p>
Explained in the <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/CLI-commands">wiki</a>.
</p></details><br>

<details><summary>»<b>The <i>Home > Dynamic Playlists</i> menu doesn't show dynamic playlists for <i>context menus</i>. Why?</b>«</summary><br><p>
By default the <b>Home > Dynamic Playlists</b> menu will only show dynamic playlists that <i>don't</i> include the <code>-- PlaylistMenuListType:contextmenu</code> parameter. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>
And <b>context menus</b> (= <i><b>M</b>ore</i> menu in the web UI or <i>click/touch-hold</i> on jivelite players) will <i>only show dynamic playlists for context menus</i>. So there may be some overlap but this separation greatly helps reduce clutter.</p></details><br>

<details><summary>»<b>I want my dynamic playlist to use one of Custom Skip's filter sets.</b>«</summary><br><p>
Just add the necessary <b>action/CLI playlist parameters</b> to the SQLite code of your custom dynamic playlist as described <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters">here</a>.<br>
If you only need <b>one</b> filter set for <b>all</b> dynamic playlists, create a Custom Skip filter set that will <i>only</i> be active if DPL plays a dynamic playlist. See Custom Skip <a href="https://github.com/AF-1/lms-customskip/wiki#i-want-customskip-to-filter-only-dynamic-playlist-tracks">Wiki</a>.
</p></details><br>

<br><br><br><hr>
<sup>1</sup> If you want localized strings in your language, read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>. Based on Erland's <i>DynamicPlayList</i> plugin.<br>
<sup>2</sup> Unless you've changed its location in the settings, you'll find DPL's <i>folder for custom dynamic playlists</i> called <b>DPL-custom-lists</b> in your <i>LMS playlist folder</i>.<br>
<sup>3</sup> You can't save your preselection permanently, it's a <b>short</b>-term thing. If you have a fixed selection of artists or albums that you want to listen to frequently, you can "hard-code" them into <b>your own custom</b> dynamic playlist.
