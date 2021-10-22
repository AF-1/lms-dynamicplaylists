Dynamic Playlists
====

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
It comes with a number of ready-to-use dynamic playlists. In addition you can now <b>use your own custom dynamic playlist</b> definitions <b>directly</b> in this plugin, you don't need other plugins for that anymore.<br>*Dynamic Playlists* will keep adding small batches of tracks in random order to your current playlist (complete albums will be added in album order). Based on Erland's <i>DynamicPlayList</i> plugin.<br>
Some preferences are not enabled by default. Please take a look at the preferences and their description on the plugin's settings page.
<br><br>

## Requirements

- LMS version >= 7.**9**
- LMS database = **SQLite**
<br><br>

## Please read *before* switching from v2 to v3
One of my objectives was to maintain as much backwards compatibility as possible while removing ties to other (deprecated) plugins or at least making them optional and non-essential in a way that they wouldn't break DPL if they stopped working properly at some point in the future. I cannot guarantee that deprecated plugins will continue to work completely or indefinitely with new versions of DPL v**3**. Since DPLv3 introduces new playlist parameters and functions *somebody else* would have to maintain, test, and update those deprecated plugins to make them fully compatible with newer versions of DPL.<br>
In short:
- **MultiLibrary**: MultiLibrary doesn't work with v3. I recommend migrating from the deprecated *MultiLibrary* plugin to native LMS **virtual libraries**. You can easily create new virtual libraries using saved **advanced search**es. DPL v3 supports playlist parameters (ID, name) and user input selection for virtual libraries.<br>

- **CustomSkip**: I recommend doing as much filtering as possible in your <i>custom dynamic</i> playlist (sql) definition. If you have to use CustomSkip please note that the last version of CustomSkip (2.5.8**3**) doesn't seem to properly skip tracks in DPLv3 dynamic playlists. If you don't want to revert to DynamicPlayList v2 you can try this:<br>
    - enable **global skipping** in *CustomSkip* settings: set <i>Enable filtering on all playlists</i> to <b>yes</b>
    - download & install the [**revised version of CustomSkip**](https://github.com/AF-1/lms-customskip) without the code that prevents it from properly working with *DynamicPlayList* v**3**
<br><br>

## Installation

### Using repo URL

- Go to *LMS* > *Settings* > *Plugins* and uninstall the currently installed version of *Dynamic PlayLists*.
- Add the repo URL below at the bottom of *LMS* > *Settings* > *Plugins*:<br>
[https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml](https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml)
- Install the new version
<br><br>

### Manual Install

- Go to *LMS* > *Settings* > *Plugins* and uninstall the currently installed version of *Dynamic PlayLists*.
- Then go to *LMS* > *Settings* > *Information*. Near the bottom of the page you'll find several plugin folder paths. The *path* you're looking for does **not** include the word *Cache* and it's not the server plugin folder that contains built-in LMS plugins. Examples of correct paths:
    - *piCorePlayer*: /usr/local/slimserver/Plugins
    - *Mac*: /Users/yourusername/Library/Application Support/Squeezebox/Plugins
- now download the *latest* version of Dynamic PlayLists by clicking the green *Code* button and downloading the zip archive. Move the folder called *DynamicPlayList* from that archive into the plugin folder mentioned above.
- restart LMS
<br><br>

## Uninstall

### Using repo URL

- Go to *LMS* > *Settings* > *Plugins* and uninstall the currently installed version of *Dynamic PlayLists*.
- Delete the repo URL you added at the bottom of *LMS* > *Settings* > *Plugins* and click *Apply* (you may have to delete your browser cache too)
- restart LMS
<br><br>

### Manual Uninstall

- delete the folder **DynamicPlayList** from your local plugin folder
- restart LMS
<br><br>


## Some changes<br>
- comes with ready-to-use dynamic playlists (stand-alone + for context menus)
- use your own custom dynamic playlist files/definitions in DPL so you can but don't have to install other plugins (like SQLPlayList or TrackStat) to get dynamic playlists
- UI changes
- lots of new settings
- separation of stand-alone from context menu dynamic playlists to minimize clutter
- added new playlist parameters like <i>virtuallibrary</i> (see [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format))
- allow other plugins to check if a client is playing a DPL mix, no more clashes with DSTM
- removed some deprecated code (MultiLibrary, CustomBrowse...)
- …
<br><br>

## Dynamic playlists: stand-alone and context menu
By default all dynamic playlists that *don't* include the *context menulisttype* parameter will show up in the **Home > Dynamic Playlists** menu. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>

**Context menus** (= *More* menu in webUI or *click/touch-hold* on jivelite players) will only show dynamic playlists for context menus. So there may be some overlap but this separation greatly helps reduce clutter.
<br><br>

## Custom dynamic playlists

One important new feature is the ability to use your own custom dynamic playlists definitions directly in DPLv3 - without any other intermediary plugin.<br>
Dynamic playlists definitions are basically plain text files with a "**.sql.xml**" file extension that contain your sqlite code/playlist definition. This will give you a great deal of freedom in creating dynamic playlists tailored to your specific needs.<br>
If you're not comfortable with SQLite code, it's good to know that the <i>new custom dynamic playlists definitions are based on the SQLPlayList format</i>. You could export your dynamic playlists from SQLPlayList as <b>"Customized SQL"</b> files (see next section on how to import them). Just make sure your sqlite code doesn't reference any unsupported deprecated plugins like MultiLibrary.
<br><br>
If you're **interested in creating your own custom dynamic playlists**<br>
**please read the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format)**.
<br><br>

## tl;dr: I have a custom sql definition. How do I add it to/ use it directly in DPLv3?

- Open a plain text editor of your choice and copy&paste your sql code
- Save it as "nameofyourchoice.sql.xml". The file extension **.sql.xml** is important.
- Now put this file in DPL's *folder for custom dynamic playlists* called **DPL-custom-lists**. Unless you've changed its location in DPL's settings you'll find this folder in your *LMS playlist folder*.
- The new dynamic playlist should now be listed in DPL, either in the *Not classified* group or in other groups according to what the *-- PlaylistGroups* parameter in your playlist definition says.
<br><br>

## Misc.
Misc. notes:
- You can only **add dynamic playlists to LMS favorites** that *don't request user input*. In other words only *one-click* dynamic playlists can be added as LMS favorites (same as in v2).
- The *Not classified* group in the DPL (home) menu will only show if DPL found dynamic playlists that belong in this group, i.e. if it's not empty.
<br><br>


## Bug reports

If you're **reporting a bug** please **include relevant server log entries and the version number of LMS and your OS**. You'll find all of that on the *settings > information* page.

Please post bug reports only [**here**](https://forums.slimdevices.com/showthread.php?115073-Announce-Dynamic-Playlists-3-(mod)).
