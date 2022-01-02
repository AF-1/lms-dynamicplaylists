Dynamic Playlists 3
====

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
It comes with a number of ready-to-use dynamic playlists. In addition you can now <b>use your own custom dynamic playlist</b> definitions <b>directly</b> in this plugin, you don't need other intermediary plugins for that.<br>*Dynamic Playlists 3* will keep adding small batches of tracks in random order to your current playlist (complete albums can be added in album order). Based on Erland's <i>DynamicPlayList</i> plugin.<br><br>
Some preferences are not enabled by default. Please take a look at the preferences and their description on the plugin's settings page.
<br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br>

## Installation
⚠️ **Please read the [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq) *before* installing this plugin.**<br>

You should be able to install **Dynamic Playlists 3** from the LMS main repository (LMS plugin library): **LMS > Settings > Plugins**.<br>

If you want to test a new patch that hasn't made it into a release version yet or you need to install a previous version you'll have to [install the plugin manually](https://github.com/AF-1/sobras/wiki/Manual-installation-of-LMS-plugins).

*Previously released* versions are available here for a *limited* time after the release of a new version. The official LMS plugins page is updated about twice a day so it usually takes a couple of hours before new released versions are listed.
<br><br><br>


## Some changes<br>
- Comes with ready-to-use dynamic playlists (stand-alone + for context menus).
- Use **your own custom dynamic playlist files/definitions directly in DPL** without any other intermediary plugin - you don't have to install other plugins (like SQLPlayList or TrackStat) to get dynamic playlists. See [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq).
- New playlist parameters for *virtual libraries*, *multiple genre selection* or *preselecting artists/albums for later use* (see [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)).
- UI changes and new settings.
- Separation of stand-alone from context menu dynamic playlists to minimize clutter.
- Allow other plugins to check if a client is playing a DPL mix, no more clashes with DSTM.
- …
<br><br><br>


## FAQ

- »**How do I transition from the old Dynamic Playlists 3 version (before the name change) to the new one?**«<br>
»**I have 2 Dynamic Playlists v*3* plugins installed now.**«<br>
»**The dynamic playlists I've added to LMS favorites don't work anymore.**«<br>
*Dynamic Playlists 3* has changed its (internal) name. LMS considers it a different plugin now.<br>Therefore you'll have to uninstall any previous version of DPL and then install the latest *Dynamic Playlists **3*** version from the LMS main repository (plugin library).<br>Before uninstalling it I recommend taking a screenshot of your plugin settings to make restoring them easier afterwards.<br>And since it's a "different" plugin you'll have to remove any playlists you've added to LMS favorites and add them again. Sorry for the inconvenience.<br><br>

- »**Is DPL v*3* compatible with my old plugins?**«<br>
*Dynamic Playlist 3* removes ties to other (unsupported) plugins in a way that they shouldn't break *Dynamic Playlists 3* if those plugins ever stopped working properly. And **within these limits** DPL v**3** tries to maintain as much backwards compatibility as possible.<br><br>So older plugins *might* work with DPL v**3** but **I won't guarantee that they do or will continue to do so and I won't spend time on making DPL v3 compatible with unsupported/older plugins** (this is what **"not supported"** *below* refers to). *Somebody else* would have to maintain, test, and update those plugins to make/keep them fully compatible with newer versions of DPL v**3** and provide support for them.
<br><br>
    - **CustomSkip**: DPL v**3** works with [**CustomSkip 3**](https://github.com/AF-1/lms-customskip). If you use *SQLPlayList* to create dynamic playlists that include CustomSkip filter sets check if SQLPlayList still works with DPL3. But setting secondary Custom Skip filter sets will work without the *SQLPlayList* plugin if you set the correct playlist parameter in your dynamic playlist definition (as explained in the [**wiki**](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters)). But **please read the CustomSkip v3 [FAQ](https://github.com/AF-1/lms-customskip#faq) first *before* installing CS3**.<br>

    - **SQLPlayList**: main features (creating dynamic playlists and making them available to DPL3) should work but not supported. Please remember: SQLPlayList (which predates DPL v3) doesn't know about the new playlist parameters and functions introduced with DPL v**3**. As long as it works you could use SQLPlayList to assist you in creating (a first draft of) your custom dynamic playlists. You *don't need SQLPayList anymore to make your dynamic playlists **available** to DPL* though. You can simply export your (custom) dynamic playlists from SQLPlayList and use them directly in DPL v3 (read FAQ below).<br>

    - **TrackStat** / **CustomScan**: could work, not tested, not supported.<br>

    - **MultiLibrary**: not supported, unlikely to work without problems because DPL v3 no longer contains code for MultiLibrary. I recommend migrating from the *MultiLibrary* plugin to native LMS **virtual libraries**. You can easily create new virtual libraries using saved **advanced search**es. Then you can use DPL v3 *playlist parameters* for virtual libraries (ID, name and user input selection).<br><br>

- »**This *built-in* dynamic playlist is missing a feature that I really want.**«<br>
The collection of **built-in** dynamic playlists includes only a large but limited set of frequently used playlists that won't see regular additions or updates. It can also be used as a *starting point* to create your **own custom** dynamic playlists whose very reason for existence is to help you create dynamic playlists tailored to your *specific* needs.<br><br>


- »**How do I create my own *custom* dynamic playlist?**«<br>
Dynamic playlist definitions are basically plain text files with a "**.sql.xml**" file extension that contain your sqlite code/playlist definition. The dynamic playlist format is basically the same as the SQLPlayList format.<br><br>
If you're not comfortable with creating your SQLite playlist definition *from scratch* you could use the *SQLPlayList* plugin (to assist you in creating your first draft). You can still let *SQLPayList* make your custom dynamic playlist available to DPL and that's it. But as the *SQLPlayList* plugin predates DPL v**3** it can't know/add any of the [new playlist parameters](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#playlist-parameters) and I can't guarantee that dynamic playlists created with SQLPlayList will (continue to) work with DPL v**3**. So as long as *SQLPayList* works you could try that first if you don't like meddling with SQLite. But no guarantees.<br><br>On the other hand, if you want to make sure that your custom dynamic playlists will continue to work - even if SQLPayList stops working or is no longer compatible - you should **export** your custom dynamic playlists from *SQLPlayList* **as "Customized SQL"** files (file extension: **.sql.xml**). You can edit them in any (plain text) editor and use new playlist parameters or create more complex sqlite definitions. This will give you a great deal of freedom in creating dynamic playlists tailored to your specific needs.<br><br>
In any case **please read the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)** for more information on the dynamic playlist **format**.<br><br>

- »**I have a custom sql definition (file). How do I add it to/ use it directly in DPLv3?**«<br>
    - If you already have a sql.xml **file** you can skip the next 2 steps.
    - Open a plain text editor of your choice and copy&paste (or edit) your sql code.
    - Save it as "nameofyourchoice.sql.xml". The file extension **.sql.xml** is important.
    - Now put this file in DPL's *folder for custom dynamic playlists* called **DPL-custom-lists**. Unless you've changed its location in DPL's settings you'll find this folder in your *LMS playlist folder*.
    - The new dynamic playlist should now be listed in DPL, either in the *Not classified* group or in other groups according to what the `-- PlaylistGroups` parameter in your playlist definition says.<br><br>

- »**The *Home > Dynamic Playlists* menu doesn't show dynamic playlists for *context menus*. Why?**«<br><br>
By default the **Home > Dynamic Playlists** menu will only show dynamic playlists that *don't* include the `-- PlaylistMenuListType:contextmenu` parameter. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>
And **context menus** (= *More* menu in webUI or *click/touch-hold* on jivelite players) will *only show dynamic playlists for context menus*. So there may be some overlap but this separation greatly helps reduce clutter.<br><br>

- »**I can't add my dynamic playlist to my LMS favorites (menu)**.«<br>
»**DPL shows a favorite icon with a *p* (default skin) or an orange tint (classic skin) next to my dynamic playlists. Why?**«<br>
The DPL's default setting has always been (even in v2) that you can only add dynamic playlists to LMS favorites that **don't request user input**. In other words only *one-click* dynamic playlists could be added as LMS favorites.<br>
DPL v3.4 allows you to add dynamic playlists with playlist parameter values (= values from user input) to LMS favorites - with some **limitations**:<br>
    - this feature is experimental and is and will remain **limited to the LMS web UI** (**Default** and **Classic** skin).<br><br>
    - Saving dynamic playlists with user input values basically means you're saving a url with fixed playlist parameters as a one-click dynamic playlist. The value of some of these playlist parameters (esp. artist/album/genre/track/playlist IDs) might change after a (delete/wipe) rescan. So please remember: **a (delete/wipe) rescan might invalidate some dynamic playlists favorites *with saved user input values***. You'll have to remove & readd them. Therefore I suggest you choose a good descriptive name so you'll remember what parameter values you chose (like "Alternative 80s rated").
<br>In short: you can *save* dynamic playlists that request user input to LMS favorites now using LMS's *Default* or *Classic* **web UI**. Once saved they should behave like normal favorites (one-click action). These favorites *might* stop working after a (wipe/delete) rescan (esp. if they include artist/album/genre/track/playlist IDs).
<br><br>

- »**The *Not classified* group in the DPL (home) menu has disappeared / doesn't show.**«<br>
The *Not classified* group in the DPL (home) menu and on settings pages will only be displayed if DPL found dynamic playlists that belong in this group, i.e. if it's not empty.<br><br>

- »**I don't want my dynamic playlist in the *Not classified* group. I want a custom group (name).**«<br>
The *Not classified* group is a *catch-all group* for all dynamic playlist that are **not** assigned to any playlist *group*. You can **create your own custom playlist groups** either by entering a group name in SQLPlayList or by setting the `-- PlaylistGroups:` parameter in your dynamic playlist definition (see [**wiki**](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters)).<br><br>

- »**Does DPL handle online tracks?**«<br>
*Dynamic Playlists 3* will process **online tracks** that have been **added to your LMS library as part of an album**. LMS does not import **single** online tracks or tracks of *online* **playlists** as **library** tracks and therefore they won't be processed by *Dynamic Playlists 3*.<br><br>

- »**Can I use CLI commands to control DPL?**«<br>
Explained in the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/CLI-commands).
<br><br>

- »**Some dynamic playlist are not sorted in alphabetical order.**«<br>
In general *dynamic playlists* will **always** be listed in this order: 1. built-in  2. custom/user-provided  3. provided by other plugins. Dynamic playlists in the last two groups should be listed in *alphabetical* order.<br>**Built-in** dynamic playlists are listed in a '*content-based*' order created by me. For example, I try to group dynamic playlists together that are about ratings, play count or genre/decade selection. If you don't like that don't forget that you can clone these playlists and even put them in a custom playlist group just by adding the corresponding parameter (see [**wiki**](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters)).<br>Static (saved) playlists will always be ordered alphabetically.
<br><br>

- »**Does DPL replace SQLPlayList and/or CustomSkip?**«<br>
No. SQLPlayList and CustomSkip3 are **separate** plugins and they have a different focus/job to do. DPL will never have the same features as any of these plugins. You *can* use them but you *don't have to*.<br>Custom Skip **3** works with DPL **3** and SQLPlayList is reported to work (with some limitations and without any guarantees as to how long, see other FAQ).<br>If you're comfortable writing/editing SQLite using custom dynamic playlist definitions you can probably do without them.
<br><br>

- »**How do Dynamic Playlists 3 and SQLPlayList work together?**«<br>
*Dynamic Playlists 3* serves you a continuous music mix. To determine what music it should fetch from the music library it needs search criteria defined in so-called *dynamic playlists*. It comes with a collection of frequently used (built-in) dynamic playlists to get you started.<br>At some point you'll probably want to create a dynamic playlist that's tailored to your very specific needs because the *built-in* dynamic playlists can and will never cover more than only a small selection of all possible use cases. If you don't want to or don't know how to create custom dynamic playlists from scratch (see other FAQ section for instructions) you can try to use the *SQLPlayList* plugin (as long as it works - different plugin, not supported by me). SQLPlayList assists you in *creating* those dynamic playlists without bothering with the details of SQLite code and makes them *available* to DPL.<br>*Dynamic Playlists 3*, like its predecessor, will never have any of those features.<br><br>So even though *Dynamic Playlists 3* comes with a collection of built-in dynamic playlists **its job is not to help you *create* dynamic playlists but to *play* them**.
<br><br>

- »**I want to my dynamic playlist to use one of CustomSkip3's filter sets.**«<br>
You can either use the *SQLPlayList* plugin to do that (as long as it works - different plugin, not supported by me) or add the necessary **action/CLI playlist parameters** to the SQLite code of your custom dynamic playlist as described [**here**](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#general-parameters).
<br><br>

- »***SQLPlayList* 2.6.272 shows an error at the bottom of the page. Does this mean that *SQLPlayList* is no longer compatible with *Dynamic Playlists 3*?**«<br>
I think SQLPlayList used to display the currently playing dynamic playlist at the bottom of that page. Since DPL3 uses a different plugin name the reference to the old DPL version 2 is broken. But so far I have no reports that this breaks SQLPlaylist's main features: assisting you in creating dynamic playlists and making them available to DPL3. Just ignore this error.
<br><br>

- »**There's more than DPL context menu item now. What's *preselection*? How does it work?**«<br>
For **artists** and **albums** DPL will show a **second context menu** that allows you to **preselect** this artist/album while browsing your music library. DPL will remember your (pre)selection (*until the next LMS restart*/rescan).<br>Once you're finished preselecting artists/albums go to DPL's menu and use this selection with any dynamic playlist that makes use of the `PlaylistPreselectedArtists` or `PlaylistPreselectedAlbums` playlist parameter. There are some built-in dynamic playlists to get you started (in the *Songs* group). And it's very easy to add to your custom dynamic playlists. See [**wiki**](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#user-input-parameters) for more information.


<br><br><br>

## Bug reports

If you're **reporting a bug** please **include relevant server log entries and the version number of LMS and your OS**. You'll find all of that on the *LMS > Settings > Information* page.

Please post bug reports *only* [**here**](https://forums.slimdevices.com/showthread.php?115073-Announce-Dynamic-Playlists-3-(mod)).
