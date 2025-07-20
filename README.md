Dynamic Playlists
====
![Min. LMS Version](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fraw.githubusercontent.com%2FAF-1%2Fsobras%2Fmain%2Frepos%2Flms%2Fpublic.xml&query=%2F%2F*%5Blocal-name()%3D'plugin'%20and%20%40name%3D'DynamicPlaylists4'%5D%2F%40minTarget&prefix=v&label=Min.%20LMS%20Version%20Required&color=darkgreen)<br>

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i> (smart playlists).<br>
*Dynamic Playlists* will keep adding small batches of tracks in random order to your current playlist (complete albums can be added in album order). It comes with a collection of built-in, ready-to-use dynamic playlists to get you started.<br>

Since the <i>built-in</i> dynamic playlists cannot cover all possible use cases, you'll probably want to create a dynamic playlist that's tailored to your very specific needs at some point using [**Dynamic Playlist Creator**](https://github.com/AF-1/#-dynamic-playlist-creator) or a file with SQLite statements (see [FAQ](#faq)).<br>
Some features are not enabled by default.
<br><br>
[⬅️ **Back to the list of all plugins**](https://github.com/AF-1/)
<br><br>
**Use the** &nbsp; <img src="screenshots/menuicon.png" width="30"> &nbsp;**icon** (top right) to **jump directly to a specific section.**

<br><br>

## Features

* Use **your own custom dynamic playlist files/definitions directly in DPL** without intermediary plugins - you don't have to install other plugins to get dynamic playlists. See [FAQ](#faq).

* Comes with more than 200 ready-to-use dynamic playlists (stand-alone + for context menus).

* **Multiple** selection of *genres*, *decades*, *years* and *static playlists*.

* **Pre**select multiple *artists* or *albums* from their context menu at your leisure. DPL remembers your **pre**selection (until the next rescan/server restart) so that you can easily use it later with dynamic playlists that use **preselection**.

* Use dynamic playlists to **create *static/normal* playlists**.

* Queue dynamic playlists (see [FAQ](#faq)).

* **Continue listening** to your *active* dynamic playlist **on another player** by transferring it with one click (incl. history, cache + all parameters).

* Create a *Don't Stop the Music* seed list and auto-start your DSTM mix.

* Supports LMS **virtual libraries**.

* Save dynamic playlists with (user input) parameters to LMS **favourites** (see [FAQ](#faq)).

* New playlist parameters (see [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)).

* Compatible with [**Dynamic Playlist Creator**](https://github.com/AF-1/#-dynamic-playlist-creator), [**Alternative Play Count**](https://github.com/AF-1/#-alternative-play-count) and [**Custom Skip**](https://github.com/AF-1/#-custom-skip).

* If you have installed the [**Alternative Play Count**](https://github.com/AF-1/#-alternative-play-count) plugin, you will see some additional dynamic playlists that use the data from this plugin.
<br><br><br><br>


## Screenshots - Context Menus[^1]
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

<br><br><br>


## Installation

**Dynamic Playlists** is available from the LMS plugin library: `LMS > Settings > Manage Plugins`.<br>

If you want to test a new patch that hasn't made it into a release version yet, you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).
<br><br><br><br>


## Report a new issue

To report a new issue please file a GitHub [**issue report**](https://github.com/AF-1/lms-dynamicplaylists/issues/new/choose).
<br><br><br>


## ⭐ Help others discover this project

If you find this project useful, giving it a <img src="screenshots/githubstar.png" width="20" height="20" alt="star" /> (top right of this page) is a great way to show your support and help others discover it. Thank you.
<br><br><br><br>


## FAQ

<details><summary>»<b>How do I create / add my own <i>custom</i> dynamic playlist?</b>«</summary><br><p>

- If you prefer a <b>GUI</b> and want an <b>easy</b> way to create a <i>custom</i> dynamic playlist *without* having to deal with raw SQLite, take a look at the <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a> plugin that uses templates to create dynamic playlists and makes them available to DPL.

- If you are <b>familiar with database queries and SQLite</b>, you can create a fully customized dynamic playlist in a plain text editor of your choice and use it directly in DPL.<br>Dynamic playlist definitions are basically plain text files with an "<b>sql</b>" file extension that contain your playlist definition:<br>
	- a couple of <b>parameters</b> (<i>general</i> parameters like the playlist name, group or category and <i>user input</i> parameters) and
	- the <b>SQLite statement</b> itself to fetch tracks from the LMS database.<br><br>

	Whether you use a <i>built-in</i> dynamic playlist as a template or start from scratch, this will give you a great deal of freedom in creating dynamic playlists tailored to your specific needs.<br>
In any case <b>please read the <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format">wiki</b></a> for more information on the dynamic playlist <b>format</b> and the few playlist parameters that you should definitely include.<br>Put your custom dynamic playlist <b>file</b> (with the <b>sql</b> file extension) in DPL's <i>folder for custom dynamic playlists</i> called <b>DPL-custom-lists</b> (in your <i>LMS preferences folder</i> unless you've changed its location in the settings).<br>The new dynamic playlist should now be listed in DPL, either in the <i>Not classified</i> group or in other groups according to what the <code>-- PlaylistGroups</code> parameter in your playlist definition says.<br><br>
</p></details><br>

<details><summary>»<b>Can I save the results of a dynamic playlist as a <i>static</i> playlist?</b>«</summary><br><p>
DPL allows you to save the result set of any dynamic playlist as a <i>static</i> playlist. There's a control icon in the Dynamic Playlists menu (web skins: default, dark default, classic) next to the names of dynamic playlists that looks a bit like an old floppy disk. In Material and jivelite GUI controllers, you get a new option “<i>Save as static playlist</i>“ in addition to <i>Play</i> and <i>Add</i>. You only need to set the maximum number of tracks (max. 4000) and name your static playlist. Dynamic playlists <b>with</b> user-input parameters will request that input first and show you the static playlist options (max. track no., playlist name, track sort order) at the end.<br>
Depending on the complexity of your dynamic playlist and the max. track limit you set for your <i>static</i> playlist, saving it might take a while.
</p></details><br>

<details><summary>»<b>What's <i>preselection</i>? How does it work?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>There's more than one DPL context menu item.</b>«</summary><br><p>
DPL has playlist parameters that allow you to select <b>multiple</b> genres, decades, years and static playlists. But even the smallest music libraries have a large number of <b>artists</b> and <b>albums</b> that would result in poorly browsable, far too long selection lists.<br>The solution is to gather/select artists or albums <i>first</i> using the <b>preselection</b> context menu item and then start a dynamic playlist for preselected artists/albums.<br>
So for <b>artists</b> and <b>albums</b> DPL will show a <b>second <i>context</i> menu</b> that allows you to <b>preselect</b> this artist/album while browsing your music library. DPL will remember your (pre)selection <i>until the next LMS restart/rescan</i>. You can't save your preselection permanently, it's a <b>short</b>-term thing. For anything more permanent, please create a custom dynamic playlist with <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a>.<br>Once you've finished preselecting artists/albums, go to DPL's home menu and use this selection with any dynamic playlist that makes use of the <code>PlaylistPreselectedArtists</code> or <code>PlaylistPreselectedAlbums</code> playlist parameter. There are some built-in dynamic playlists to get you started (in the <i>Songs</i> group). And it's very easy to add these playlist parameters to your custom dynamic playlists. Read this <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#user-input-parameters"><b>wiki</b></a> section for more information.
</p></details><br>

<details><summary>»<b>With which plugins does DPL work?</b>«</summary><br><p>
DPL is compatible with <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a>, <a href="https://github.com/AF-1/#-alternative-play-count"><b>Alternative Play Count</b></a> and <a href="https://github.com/AF-1/#-custom-skip"><b>Custom Skip</b></a>.<br>

If you're familiar with SQLite and know how to create <i>custom</i> dynamic playlists, you can use data from any LMS database table.
</p></details><br>

<details><summary>»<b>Do I need the <i>Dynamic Mix</i> plugin?</b>«</summary><br><p>
No. <i>Dynamic Mix</i> version 1.3 is <u><i>not</i></u> compatible with <i>Dynamic Playlists</i> version <b>4</b>. Dynamic Mix used MusicIP to create dynamic playlist mixes for DPL version <b>2</b>. I don't use MusicIP. So I don't know if Dynamic Mix interferes with DPL version <b>4</b>. But since it's not compatible, it's probably better to uninstall it.
</p></details><br>

<details><summary>»<b>How do I queue dynamic playlists?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>I've queued dynamic playlists and they disappeared.</b>«</summary><br><p>
You can queue up to 5 dynamic playlists. When all tracks matching the search criteria for the <i>active</i> dynamic playlist have been added to your client playlist and you have queued dynamic playlists, DPL will add a short silent track and (a placeholder for) the next queued dynamic playlist to your client playlist. The silent track should help with a smooth transition so the last track before the new dynamic playlist isn't cut short.<br><br><b>Please note:</b> The list with queued dynamic playlists is <b>cleared</b> when you <b>restart the server</b>.
</p></details><br>

<details><summary>»<b>How does DPL work with the <i>Don't Stop the Music</i> plugin?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What does the icon with the infinity symbol do?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What does “<i>Create DSTM seed list and play</i>“ mean?</b>«</summary><br><p>
The <i>Don't Stop the Music</i> (DSTM) plugin “will automatically add similar music to what you've been listening to ... once you've reached the end of your playlist“. DSTM takes a look at the existing tracks in your client's playlist (the <i>seed list</i>) to determine what kind of tracks to search for.<br><br>As long as <i>Dynamic Playlists</i> is <b>active</b>, i.e. playing a dynamic playlist, <b>DSTM</b> will <b>not</b> interfere or add any tracks.<br><br>But now you can use <i>Dynamic Playlists</i> to create a DSTM seed list from any dynamic playlist and start a DSTM mix for you. There's a preference setting if you prefer to skip playback of all seed list tracks (but the last one).
</p></details><br>

<details><summary>»<b>How do I know whether DPL is still <i>active</i>?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>What causes DPL to no longer be active?</b>«</summary><br><p>
To find out whether <i>Dynamic Playlists</i> is still <b>active</b> just enter the DPL menu from the <i>Home/My Music</i> menu. If it's still active, it will display the active dynamic playlist at the top of the DPL menu.<br>Some actions/events that stop DPL (= no longer active): clearing your client playlist, DPL no longer finds tracks for the active dynamic playlist, you told DPL to stop adding tracks...
</p></details><br>

<details><summary>»<b>What does the <i>PlaylistUseCache</i> option do? Which dynamic playlists can use the cache?</b>«</summary><br><p>
For dynamic playlists that can retrieve <b>all</b> tracks matching your search parameters in <b><u>one</u> initial</b> database query, DPL loads <b>all</b> tracks into the <b>cache</b>, thus eliminating the need for further database queries. Subsequent batches of new tracks for the active dynamic playlist will be retrieved <b>from the cache only</b>, and added to a client's playlist <b>much faster</b> as a result.<br>Dynamic playlists that retrieve each batch of new tracks from a different, randomly chosen artist, album, genre, year, decade or static playlist are <b>not</b> suitable for cache use because not all tracks can be retrieved in one initial database query.
</p></details><br>

<details><summary>»<b>I've added a dynamic playlist to my LMS favorites, but it no longer works.</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>There are some dynamic playlists that I can't add to LMS favorites.</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>DPL shows a favorite icon with a <i>p</i> (default skin) or an orange tint (classic skin) next to my dynamic playlists. Why?</b>«</summary><br><p>
Prior to <i>Dynamic Playlists <b>3</b></i>, you could <b>only</b> save <i>one-click</i> dynamic playlists as favorites that don't ask for user input when you start them.<br><br>Now you can also add dynamic playlists <b>with</b> user input parameters.<br>By <b>default</b>, <i>Dynamic Playlists</i> will <b>not</b> let you save</b> dynamic playlists as LMS favorites that ask users for <b>volatile</b> input at run-time (artist, album, genre(s) or playlist(s)) because those values <b>could change after a rescan</b> and break such favorites.<br>
If you still want to add dynamic playlists with <b>volatile</b> parameter values (artist, album, genre(s) or playlist(s)) to LMS favorites, you can enable this in the plugin settings. However, keep in mind that such favorites may no longer work after a rescan and you'd have to delete and <b>readd</b> them. Therefore I suggest you choose a descriptive name so you'll remember what parameter values you chose (like "Alternative 80s rated").<br><br>
If you always select the same artists, albums, genres or playlists, it's probably better to create a <b>custom</b> dynamic playlist with the actual artist/album/genre/playlist <b>names</b>. A favorite for such a one-click dynamic playlist is not affected by rescans.<br><br>
This feature is <b>limited to the LMS web UI</b> (<i>(Dark) Default</i> and <i>Classic</i> skin), <b>players with jivelite UI</b> (<i>Touch</i>, <i>Radio</i>, <i>SqueezePlay</i>, <i>piCorePlayer</i>) and <b>Material</b> skin.<br><br>
Please note: Changing the <b>file</b>name of a <i>custom</i> dynamic playlist alters its dynamic playlist <i>id</i> and thus invalidates any existing favorite for this dynamic playlist. The same applies to <i>built-in</i> dynamic playlists: If a plugin <b>update</b> changes the filename of a built-in dynamic playlist, you'll have to delete and readd favorites based on that dynamic playlist. Doesn't happen very often and always for good reasons.<br><br>
The favorite icon with the <i>p</i> (default skin) or an orange tint (classic skin) just indicates that this dynamic playlist contains <b>p</b>arameters that will ask for user input when you start it.</p></details><br>

<details><summary>»<b>The <i>Not classified</i> group in the DPL (home) menu has disappeared / doesn't show.</b>«</summary><br><p>
The <i>Not classified</i> group in the DPL (home) menu and on settings pages will only be displayed if DPL found dynamic playlists <i>without</i> a playlist <b>group</b> name, i.e. if it's not empty.</p></details><br>

<details><summary>»<b>This <i>built-in</i> dynamic playlist is missing a feature that I really want.</b>«</summary><br><p>
The collection of <b>built-in</b> dynamic playlists includes only a large but limited set of frequently used playlists that won't see regular additions or updates.<br>If you want to create custom dynamic playlists without bothering with SQLite statements, please try the <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a> plugin.<br>If you're familiar with SQLite, you can use the <i>built-in</i> dynamic playlists as a <i>starting point</i> for creating your <b>own custom</b> dynamic playlists.</p></details><br>

<details><summary>»<b>I don't want my dynamic playlist in the <i>Not classified</i> group. I want a custom group (name).</b>«</summary><br><p>
The <i>Not classified</i> group is a <i>catch-all group</i> for all dynamic playlist that are <b>not</b> assigned to any playlist <i>group</i>. You can <b>create your own custom playlist groups</b> by entering a playlist group name in <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a> or by setting the <code>-- PlaylistGroups:</code> parameter in the file with your customized SQLite statement (see <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters"><b>wiki</b></a>).</p></details><br>

<details><summary>»<b>Does DPL handle online tracks?</b>«</summary><br><p>
<i>Dynamic Playlists</i> will process <b>online tracks</b> that have been <b>added to your LMS library as part of an album</b>. LMS does not import <b>single</b> online tracks or tracks of <i>online</i> <b>playlists</b> as <b>library</b> tracks and therefore they won't be processed by <i>Dynamic Playlists</i>.</p></details><br>

<details><summary>»<b>Some dynamic playlists in the <i>DPL menu</i> are not listed in alphabetical order.</b>«</summary><br><p>
In general, <i>dynamic playlists</i> in the <i>DPL menu</i> will <b>always</b> be listed in this order: 1. built-in, 2. custom/user-provided, 3. provided by other plugins. Dynamic playlists in the last two groups should be listed in <i>alphabetical</i> order.<br><b>Built-in</b> dynamic playlists are listed in a 'content-based' order created by me. For example, I try to group dynamic playlists together that are about ratings, play count or genre/decade selection. If you don't like how I ordered the built-in dynamic playlists, don't forget that you can clone these playlists and even put them in a custom playlist group just by adding the corresponding parameter (see <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters"><b>wiki</b></a>).<br>Static (saved) playlists will always be ordered alphabetically.
</p></details><br>

<details><summary>»<b>How do I transfer my active dynamic playlist to another player?</b>«<br>&nbsp;&nbsp;&nbsp;&nbsp;»<b>The player to which I want to transfer my active dynamic playlist is not listed (as a target player).</b>«</summary><br><p>
If you have an <i>active</i> dynamic playlist and <i>more than one</i> player, you can transfer the active dynamic playlist using the Dynamic Playlists (top level) menu.<br>By default, you can only transfer it to <b>un</b>synchronized players, which might be missing from the target player list. You can change that in the plugin settings.
</p></details><br>

<details><summary>»<b>Can I use CLI commands to control DPL?</b>«</summary><br><p>
Explained in the <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/CLI-commands">wiki</a>.
</p></details><br>

<details><summary>»<b>The <i>Home > Dynamic Playlists</i> menu doesn't show dynamic playlists for <i>context menus</i>. Why?</b>«</summary><br><p>
By default the <b>Home > Dynamic Playlists</b> menu will only show dynamic playlists that <i>don't</i> include the <code>-- PlaylistMenuListType:contextmenu</code> parameter. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>
And <b>context menus</b> (= <i><b>M</b>ore</i> menu in the web UI or <i>click/touch-hold</i> on jivelite players) will <i>only show dynamic playlists for context menus</i>. So there may be some overlap but this separation greatly helps reduce clutter.</p></details><br>

<details><summary>»<b>I want my dynamic playlist to use one of Custom Skip's filter sets.</b>«</summary><br><p>
Use <a href="https://github.com/AF-1/#-dynamic-playlist-creator"><b>Dynamic Playlist Creator</b></a> to create a custom dynamic playlist with a specific Custom Skip filter set that's enabled/disabled when your dynamic playlists starts/stops.<br>If you have created a custom dynamic playlist from scratch (raw SQLite), just add the necessary <b>action/CLI playlist parameters</b> to your file as described <a href="https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters">here</a>.<br>
If you only need <b>one</b> filter set for <b>all</b> dynamic playlists, create a Custom Skip filter set that will <i>only</i> be active if DPL plays a dynamic playlist. See Custom Skip <a href="https://github.com/AF-1/lms-customskip/wiki#i-want-customskip-to-filter-only-dynamic-playlist-tracks">Wiki</a>.
</p></details><br>

<details><summary>»<b>Can this plugin be <i>displayed in my language</i>?</b>«</summary><br><p>If you want localized strings in your language, please read <a href="https://github.com/AF-1/sobras/wiki/Adding-localization-to-LMS-plugins"><b>this</b></a>.</p></details>

<br><br><br>

[^1]: The screenshots might not correspond to the UI of the latest release in every detail.
