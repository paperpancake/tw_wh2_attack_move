Attack Move and Counter Charge, a mod for Total War: Warhammer 2

NOTE: This is formatted for the Steam Workshop page where it's published: https://steamcommunity.com/sharedfiles/filedetails/?id=2193421281


This mod is for anyone who has wished you could give your units standing orders so that they could do the most basic tasks without constant supervision.


[h2]How do I use this?[/h2]
[olist]
[*]Select some units.

[*](optional) Give a move order.

[*]Use the hotkey or press the button. Yes, do this [u][b]after[/b][/u] your move order unless the unit is already ordered to be where you want it to be and you are just turning on counter charge.

[*]This mod saves the ordered location for each unit, locking it in.**

[*]This mod frequently checks to see if your unit should attack nearby units.
[list]
[*]When there are no appropriate targets, the mod will reorder your units to move toward the locked-in destination.
[/list]

[*]When your attack-moving unit reaches the ordered position, the attack-move order turns into a counter charge order. Your unit will attack any units that come near and then keep returning to its locked ordered location.

[*]IMPORTANT: While this attack-move lock is on, it will override any new orders you are trying to give your units. If you want to give a new move or attack order to the unit, you must unlock the attack order by selecting the unit and using the hotkey or pressing the button.
[/olist]

**This mod cannot determine if you've shift-clicked some orders. It will just lock in the final destination and all the other orders in between will be lost (unless your configuration has a sufficiently big "chasing adjustment", perhaps?).


[h2]You'll notice that is a little different than other RTS attack-moves[/h2]

It is the best I could come up with given the scripting limitations for this game. If you are curious or if want to help me think of better workarounds, I invite you to check out the [url=https://steamcommunity.com/workshop/filedetails/discussion/2193421281/2797251375486378276/]discussion about scripting limitations[/url].


[h2]What hotkey does this use?[/h2]

You can use whatever key combination you want. By default, this mod uses whatever you set in "Save Camera Bookmark 7" (which is usually not set to anything). I personally use Z, since I don't ever use Z to controlling the camera.

If you don't want this mod to piggyback on your "Save Camera Bookmark 7" hotkey, you can [url=https://steamcommunity.com/workshop/filedetails/discussion/2193421281/2797251375486419512/]configure this mod[/url].


[h2]Disabled by default during siege battles[/h2]

By default, this is disabled during siege battles since this mod doesn't know how to handle walls. You can enable it during siege battles using a config option (see below). Attack-moving units that can't climb or fly over walls will stand like confused puppies at the base of the wall if their target is on the wall.


[h2]Optional Configuration[/h2]

This mod should work without you doing anything with configuration. However, you can customize a lot of variables between battles using either [url=https://steamcommunity.com/sharedfiles/filedetails/?id=2136347705]the new MCT[/url] or [url=https://steamcommunity.com/workshop/filedetails/discussion/2193421281/2797251375486419512/]a text file[/url].


[h2]Pairs well with...[/h2]
[url=https://steamcommunity.com/sharedfiles/filedetails/?id=1961243473]Find Idle Units[/url]


[h2]Compatibility[/h2]
[b]Saved Games?[/b] Yes.

[b]Other mods that DON'T run scripts during battle?[/b] Yes, definitely.

[b]Other mods that DO run scripts during battle?[/b] Yes for most. No for some. Examples:
[list]
[*]YES: Find Idle Units, AI General II, Counting Skulls, Quick Spell Menu, ClickNFight, etc.
[*]NO: Spectator Mode II (use AI General II instead)
[/list]

Please let me know if you find another incompatible mod so I can list it here and/or work with its authors to fix the incompatibility.

[url=https://steamcommunity.com/workshop/filedetails/discussion/2193421281/2797251375486741612/]Technical compatibility details for curious modders[/url]


[h2]Multiplayer?[/h2]
This works in most multiplayer situations. As with all mods, this mod will only work in multiplayer if you and the person you are playing with have the same mods enabled, and have no extra mods in your data folder. (Otherwise, the game will say you have a version mismatch).

The only multiplayer issue I know of is that during multiplayer cooperative campaigns, this mod will only work for the player who has an army in the fight. If you spectate your ally's battle and your ally gifts you units, this mod will do nothing for the spectator. You can still play as normal, though, and the original player will still be able to use attack move and counter charge like normal.
