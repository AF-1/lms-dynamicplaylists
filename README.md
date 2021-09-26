Dynamic Playlists
====

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
It comes with a number of ready-to-use dynamic playlists. In addition you can now <b>use your own custom dynamic playlist</b> definitions <b>directly</b> in this plugin, you don't need other plugins for that anymore. Based on Erland's <i>DynamicPlayList</i> plugin.
<br><br>

## Installation

You should be able to install *Dynamic PlayLists* from *LMS* > *Settings* > *Plugins*<br>(It usually takes a couple of hours before released versions show up on the official LMS plugins page.)<br>

Or you could download the latest (source code) zip from this repository and drop the folder called *DynamicPlayList* into your local LMS plugin folder.

If you want to test a **new** patch that hasn't made it into a release version yet or if you need to install a **previous** version:

* go to *settings > plugins* and uninstall the currently installed version of Dynamic PlayLists.
* then go to *settings > information*. Near the bottom of the page you'll find several plugin folder paths. The *path* you're looking for does **not** include the word *Cache* and it's not the server plugin folder that contains built-in LMS plugins. Examples of correct paths:
    * *piCorePlayer*: /usr/local/slimserver/Plugins
    * *Mac*: /Users/yourusername/Library/Application Support/Squeezebox/Plugins
* now download the version you need:
    * the *latest* version of Dynamic PlayLists (incl. patches not yet released) is on github. Click the green Code button and download the zip archive. Move the folder called *DynamicPlayList* from that archive into the plugin folder mentioned above.
	* *previously released* versions are available here for a *limited* time after the release of a new version. Download the source code zip archive and move the folder called *DynamicPlayList* from that archive into the plugin folder mentioned above.
* restart LMS
<br><br>

If you updated to DPL version 3+ but for some reason prefer to continue using the older deprecated version 2 then download the package with the [DPL v2 plugin](https://github.com/erland/lms-dynamicplaylist), unzip the archive, rename the folder *src* to *DynamicPlayList* and put it into the plugin folder mentioned in the description above, restart LMS. LMS should ignore DPL v3 if you install DPL 2.x this way.
<br><br>

## Some changes<br>
- comes with ready-to-use dynamic playlists (stand-alone + for context menus)
- use your own custom dynamic playlist files/definitions in DPL so you can but don't have to install other plugins (like SQLPlayList or TrackStat) to get dynamic playlists
- UI changes
- separation of stand-alone from context menu dynamic playlists to minimize clutter
- added new playlist parameters like <i>virtuallibrary</i>
- allow other plugins to check if a client is playing a DPL mix, no more clashes with DSTM
- SQLite only, removed some deprecated code, min. LMS version = 7.9
- …
<br><br>

## Dynamic playlists: stand-alone and context menu
By default all dynamic playlists that *don't* include the *context menulisttype* parameter will show up in the **Home > Dynamic Playlists** menu. Here you won't find any dynamic playlists that can be called from an item's context menu.<br>

**Context menus** (= *More* menu in webUI) will only show dynamic playlists for context menus. So there may be some overlap but this separation greatly helps reduce clutter.
<br><br>

## Custom dynamic playlists

DPL will still pick up dynamic playlists from other plugins. So you can still use SQLPlayList to create your own dynamic playlists and use them in DPL, just like you did before.<br><br>
Since the <i>new custom dynamic playlists definitions are based on the SQLPlayList format</i> you can also export your dynamic playlists from SQLPlayList and use them <b>directly</b> in DPL (without SQLPlayList):<br>
just save them as <b>"Customized SQL"</b> files (file extension: .sql.xml) in SQLPlayList and place these files in the new <i>DynamicPlayList folder for custom files</i> (which you can change/set on the DPL plugin's settings page).
<br><br>
If you're interested in creating your own custom dynamic playlists (without SQLPlayList) check out the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format) for more information.

## Bug reports

If you're **reporting a bug** please **include relevant server log entries and the version number of LMS and your OS**. You'll find all of that on the *settings > information* page.

Please post bug reports only [**here**](https://forums.slimdevices.com/showthread.php?115073-Announce-Dynamic-Playlists-3-(mod)).
