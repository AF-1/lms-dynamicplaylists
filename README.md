Dynamic Playlists
====

This plugin lets you play continuous music mixes based on selection criteria defined in so-called <i>dynamic playlists</i>.<br>
It comes with a number of ready-to-use dynamic playlists. In addition you can now <b>use your own custom dynamic playlist</b> definitions <b>directly</b> in this plugin, you don't need other plugins for that anymore. Based on Erland's <i>DynamicPlayList</i> plugin.
<br><br>

## Installation

Add the repo URL below at the bottom of *LMS* > *Settings* > *Plugins*:<br>
[https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml](https://raw.githubusercontent.com/AF-1/lms-dynamicplaylists/main/public.xml)
<br><br>
Or download the latest (source code) zip from this repository and put the folder called *DynamicPlayList* in your local LMS plugin folder.
<br><br>
Some changes:<br>
- comes with ready-to-use dynamic playlists (stand-alone + for context menus)
- use your own custom dynamic playlist files/definitions in DPL so you can but don't have to install other plugins (like SQLPlayList or TrackStat) to get dynamic playlists
- UI changes
- separation of stand-alone from context menu dynamic playlists to minimize clutter
- added new playlist parameters like <i>virtuallibrary</i>
- allow other plugins to check if a client is playing a DPL mix, no more clashes with DSTM
- SQLite only, removed CustomBrowse/MultiLibraries code, min. LMS version = 7.9
- …
<br><br>

## Custom dynamic playlists

DPL will still pick up dynamic playlists from other plugins. So you can still use SQLPlayList to create your own dynamic playlists and use them in DPL, just like you did before.<br><br>
Since the <i>new custom dynamic playlists definitions are based on the SQLPlayList format</i> you can also export your dynamic playlists from SQLPlayList and use them <b>directly</b> in DPL (without SQLPlayList):<br>
just save them as <b>"Customized SQL"</b> files (file extension: .sql.xml) in SQLPlayList and place these files in the new <i>DynamicPlayList folder for custom files</i> (which you can change/set on the DPL plugin's settings page).
<br><br>
If you're interested in creating your own custom dynamic playlists (without SQLPlayList) check out the [wiki](https://github.com/AF-1/lms-dynamicplaylists/wiki/DPL-playlist-format) for more information.