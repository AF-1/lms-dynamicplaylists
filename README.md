Dynamic Playlists
====

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
It comes with a number of ready-to-use dynamic playlists. In addition you can now <b>use your own custom dynamic playlist</b> definitions <b>directly</b> in this plugin, you don't need other intermediary plugins for that anymore.<br>*Dynamic Playlists* will keep adding small batches of tracks in random order to your current playlist (complete albums can be added in album order). Based on Erland's <i>DynamicPlayList</i> plugin.<br><br>
Some preferences are not enabled by default. Please take a look at the preferences and their description on the plugin's settings page.
<br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br>

## Installation
**Please read the [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq) before installing.**<br>

### Using the repository URL

- Add the repository URL below at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply*:<br>
[https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml](https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml)
- Install the new version
<br><br>

### Manual Install

- Go to *LMS* > *Settings* > *Plugins* and uninstall the currently installed version of *Dynamic Playlists*.
- Then go to *LMS* > *Settings* > *Information*. Near the bottom of the page you'll find several plugin folder paths. The *path* you're looking for does **not** include the word *Cache* and it's not the server plugin folder that contains built-in LMS plugins. Examples of correct paths:
    - *piCorePlayer*: /usr/local/slimserver/Plugins
    - *Mac*: /Users/yourusername/Library/Application Support/Squeezebox/Plugins
- now download the *latest* version of *Dynamic Playlists* by clicking the green *Code* button and downloading the zip archive. Move the folder called *DynamicPlayList* from that archive into the plugin folder mentioned above.
- restart LMS
<br><br>

## Uninstall

### Using the repository URL

- Go to *LMS* > *Settings* > *Plugins* and uninstall the currently installed version of *Dynamic Playlists*.
- Delete the repository URL you added at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply* (you may have to delete your browser cache too)
- restart LMS
<br><br>

### Manual Uninstall

- delete the folder **DynamicPlayList** from your local plugin folder
- restart LMS
<br><br>


## Some changes<br>
- comes with ready-to-use dynamic playlists (stand-alone + for context menus)
- use your own custom dynamic playlist files/definitions directly in DPL - you don't have to install other plugins (like SQLPlayList or TrackStat) to get dynamic playlists
- new playlist parameters like <i>virtuallibrary</i> (see [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format))
- UI changes and new settings
- separation of stand-alone from context menu dynamic playlists to minimize clutter
- allow other plugins to check if a client is playing a DPL mix, no more clashes with DSTM
- removed some deprecated code (MultiLibrary, CustomBrowse...)
- …
<br><br>

## Dynamic playlists: stand-alone and context menu
By default all dynamic playlists that *don't* include the *context menulisttype* parameter will show up in the **Home > Dynamic Playlists** menu. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>

**Context menus** (= *More* menu in webUI or *click/touch-hold* on jivelite players) will only show dynamic playlists for context menus. So there may be some overlap but this separation greatly helps reduce clutter.
<br><br>

## Custom dynamic playlists

One important new feature is the ability to use your own custom dynamic playlists definitions directly in DPLv3 - without any other intermediary plugin. This will give you a great deal of freedom in creating dynamic playlists tailored to your specific needs.<br> For more information on how to create your own custom dynamic playlists and use them directly in DPL please read the [FAQ](https://github.com/AF-1/lms-dynamicplaylists#faq).
<br><br><br>


## FAQ

- »**Is DPL v*3* compatible with my old plugins?**«<br>
One of my objectives was to maintain as much backwards compatibility as possible while removing ties to other (deprecated) plugins or at least making them optional and non-essential in a way that they wouldn't break DPL if those plugins ever stopped working properly. I cannot guarantee that deprecated plugins will continue to work completely or indefinitely with new versions of DPL v**3**. Since DPLv3 introduces [new playlist parameters](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#playlist-parameters) and functions *somebody else* would have to maintain, test, and update those deprecated plugins to make them fully compatible with newer versions of DPL.
<br><br>
    - **MultiLibrary**: MultiLibrary doesn't work properly with v3. I recommend migrating from the deprecated *MultiLibrary* plugin to native LMS **virtual libraries**. You can easily create new virtual libraries using saved **advanced search**es. Then you can use DPL v3 *playlist parameters* for virtual libraries (ID, name and user input selection).<br>

    - **CustomSkip**: I recommend doing as much filtering as possible in your <i>custom dynamic</i> playlist (sql) definition. If you want to use CustomSkip please note that the last version v2 of CustomSkip (2.5.8**3**) doesn't seem to properly skip tracks in DPLv3 dynamic playlists. If you don't want to revert to DynamicPlayList v2 try this:<br>
        - Download & install version 3 of [**CustomSkip**](https://github.com/AF-1/lms-customskip).
        - Please read the CustomSkip [**FAQ**](https://github.com/AF-1/lms-customskip#faq)<br>

    - **SQLPlayList**: SQLPlayList (which predates DPL v3) can't know / use the new playlist parameters and functions introduced with DPL v**3**. Even if you use this plugin to assist you in creating (a first draft of) your custom dynamic playlists you *don't need SQLPayList anymore to make your dynamic playlists **available** to DPL*. You can simply export your (custom) dynamic playlists from SQLPlayList and use them directly in DPL v3 (read FAQ below). Just make sure your sqlite code doesn't reference unsupported plugins like *MultiLibrary*.<br><br>

- »**How do I create my own *custom* dynamic playlist?**«<br>
Dynamic playlists definitions are basically plain text files with a "**.sql.xml**" file extension that contain your sqlite code/playlist definition. The dynamic playlist format is basically the same as the SQLPlayList format.<br><br>
If you're not comfortable with creating your SQLite playlist definition *from scratch* you can use the *SQLPlayList* plugin (to assist you in creating your first draft). You can still let *SQLPayList* make your custom dynamic playlist available to DPL and that's it. But as the *SQLPlayList* plugin predates DPL v**3** it can't know/add any of the [new playlist parameters](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format#playlist-parameters) and I can't guarantee that all dynamic playlists created with SQLPlayList will (continue to) work in DPL v3.<br><br>On the other hand, if you want to make sure that your custom dynamic playlists will still work - even if SQLPayList stops working or is no longer compatible - you should **export** your custom dynamic playlists **as "Customized SQL"** files (file extension: **.sql.xml**) from *SQLPlayList*. You can edit them in any (plain text) editor using new playlist parameters or creating more complex sqlite definitions.<br><br>
In any case **please read the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)** for more information on the dynamic playlist **format**.<br><br>

- »**I have a custom sql definition (file). How do I add it to/ use it directly in DPLv3?**«<br>
    - If you already have a sql.xml **file** you can skip the next 2 steps.
    - Open a plain text editor of your choice and copy&paste (or edit) your sql code.
    - Save it as "nameofyourchoice.sql.xml". The file extension **.sql.xml** is important.
    - Now put this file in DPL's *folder for custom dynamic playlists* called **DPL-custom-lists**. Unless you've changed its location in DPL's settings you'll find this folder in your *LMS playlist folder*.
    - The new dynamic playlist should now be listed in DPL, either in the *Not classified* group or in other groups according to what the *-- PlaylistGroups* parameter in your playlist definition says.<br><br>

- »**I can't add my dynamic playlist to my LMS favorites (menu)**.«<br>
You can only add dynamic playlists to LMS favorites that **don't request user input**. In other words only *one-click* dynamic playlists can be added as LMS favorites (same as in v2).<br><br>

- »**The *Not classified* group in the DPL (home) menu has disappeared / doesn't show.**«<br>
The *Not classified* group in the DPL (home) menu and on settings pages will only be displayed if DPL found dynamic playlists that belong in this group, i.e. if it's not empty.<br><br>

- »**Does DPL handle online tracks?**«<br>
*Dynamic Playlists* will process **online tracks** that have been **added to your LMS library as part of an album**. LMS does not import **single** online tracks or tracks of *online* **playlists** as **library** tracks and therefore they won't be processed by *Dynamic Playlists*.<br><br>

- »**Can I use CLI commands to control DPL?**«<br>
Explained in the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/CLI-commands).
<br><br>


## Bug reports

If you're **reporting a bug** please **include relevant server log entries and the version number of LMS and your OS**. You'll find all of that on the *settings > information* page.

Please post bug reports only [**here**](https://forums.slimdevices.com/showthread.php?115073-Announce-Dynamic-Playlists-3-(mod)).
