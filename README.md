# About this script

This PowerShell script is designed to intelligently backup and restore the NVIDIA GL shader cache for Cemu on a PER-GAME basis.

The script has been wrapped as an exe using PS2EXE-GUI.

# Requirements

- Cemu
- Cemu hook (recommended)
- NVIDIA GPU
- Only tested on Windows 10

# What it fixes

It might reduce micro-stutters caused by the NVIDIA GL cache for Cemu getting invalidated / deleted.

When does that happen?
- Driver update
- Playing different games with Cemu?
- Other??

My primary concern is the multiple game scenario. This script helps maintain distinct GL shader caches per-Cemu game which, from my experience, reduces stutter caused by the cache (or portions of it) being somehow invalidated by switching games.

>NOTE: If you only play a single game with Cemu, this script probbably isn't going to help you much as your GLSahder cache will rarely get invalidated.

One commonly suggested fix to stuttering is to set the `Precombiled shader cache` option in Cemu (hook) to `Disabled/ignore`. This script more or less emulates that behaviour without having to deal with the long load times each time you play a game.

# What it doesn't fix

It won't magically fix stuttering or improve FPS, in fact it might not improve anything at all for you.

If you only play one game with Cemu, you won't really benefit much as your GLCache will rarely get invalidated.

>REMINDER: If you are playing more than one game with Cemu, this script maintains distinct versions of the NVIDIA GLCache for each game. This might help prevent the cache (or portions of it) from being invalidated when switching games, which could lead to stuttering at various points in the game.

# How it works

Before launching a specific game in Cemu, this script tries to restore a backup of the NVIDIA GL shader cache for that particular game.

When Cemu exits, the script checks to see if the GL shader cache increased significantly in size and backs it up if it did.

### What happens the first time a game is run?

When running a game for the first time (or if a previous backup was deleted), this script will use the Cemu hook .ini file to force a re-compile of the shader cache. This is necessary to get a good clean GL cache to make a backup from.

When you exit Cemu after the first run of the game, the setting will be reverted to enable the precompiled shader cache again.

>WARNING: If you make any changes to Cemu hook config on the first run and this script has forced the re-compile, the settings you changed will be reverted when you exit Cemu.

# Setup

1) Place this script/exe *and* 'Cemu_withGLCacheBackup.xml' in the same directory as Cemu.exe.

2) Edit 'Cemu_withGLCacheBackup.xml' and set the NVIDIA GL cache path and ID appropriately.

3) For each Cemu game you play, create a Windows and/or Steam shortcut

# Cemu_withGLCacheBackup.xml

You **MUST** configure the appropriate settings in this file before using the script. This only needs to be done once. This XML file must be placed in the same directory as this script/exe.

1. Open the NVIDIA GLCache folder in Windows Explorer. It will be something like:
`C:\Users\<UserName>\AppData\Local\NVIDIA\GLCache`

2. Keep opening the folders in the `GLCache` folder until you come to a folder containing at least one `.bin` file and one `.toc` file.

3. Copy this folder path and paste it in the `<glCacheDir>` element in the XML file.

4. Delete all of the `.bin` and `.toc` files in this directory so you're starting fresh.

5. Launch Cemu normally (without this script) and run any game. Let the game start, then check the folder again and you should now see a `.bin` and a `.toc` file. Copy the file name from the `.bin` file (without the extension) and paste it in the `<glCacheCemuId>` element in the XML file.

The configured XML file should look something like this:
```
<?xml version="1.0" encoding="UTF-8" ?>
<config>
	<glCacheDir>C:\Users\UserName\AppData\Local\NVIDIA\GLCache\718a971d5bda0402be4a6aa910329361\9e5cb618e0a477b0</glCacheDir>
	<glCacheCemuId>3ad8f6e21bb8bb8e</glCacheCemuId>
</config>
```

# Creating a shortcut to run a game

>Remember: If there is no existing backup (i.e. running a game using this script for the first time, or you manually deleted a backup) then this script will force a re-compile of the shader cache, so it will take longer to load as Cemu re-compiles the cache.

## Creating a Windows shortcut:

```
Target:
C:\<PathToCemu>\Cemu_withGLCacheBackup.exe -gamePath "<FullPathToGame>" -gameId "<NameOfGame>"

Start In:
C:\<PathToCemu>
```

- Note: The `gameId` parameter is simply a unique name to use as the backup cache name. It can be whatever you want, just stick to letters and numbers for simplicity.

## Creating a shortcut for Steam in-home streaming:

To prevent the console from showing an causing the Cemu window to lose focus, use the `_noConsole` variant of the script. Then add the Cemu args to enable full screen and upside-down rendering.

```
Target:
C:\<PathToCemu>\Cemu_withGLCacheBackup_noConsole.exe -gamePath "<FullPathToGame>" -gameId "<NameOfGame>" -cemuArgs "+f +ud"

Start In:
C:\<PathToCemu>
```

# Required options

```
-gamePath "<PathToCemuGame>"

The full path to the Cemu game to run.
```

```
-gameId "<NameOfGame>"

A unique identifier for the game being run. This can be whatever you want and will be used to name the backup file. Must only contain characters valid in a Windows file name.
```

# Additional options

```
-backupDir "<BackupDirectory>"

This defaults to a subdirectory named GLCacheBackup in the current directory the script is running in. You can specify the absolute path to a different directory with this option.
```

```
-cemuDir "<CemuInstallDirectory>"

This defaults to the current directory the script is running in. Normally you should not need to change this.
```

```
-cemuExe "<NameOfCemuExe>"

This defaults to Cemu.exe. Normally you should not need to change this.
```

```
-cemuArgs "<args>"

You can use this parameter to pass additional arguments to the Cemu process.

** You MUST use '+' instead of '-' in front of the arguments
   For example:
      -cemuArgs "+ud"
   This will pass the render upside-down argument to Cemu.
```

```
-showPrompts

If you use this option, you'll get prompted before restoring and saving backups. Helpful for testing.
```

```
-testMode

This flag will make the script not actually restore or backup the cache files. Useful if you just want to test your config and see the size of the shader caches.
```

# Troubleshooting

- Check the `GLCacheBackup` directory in your Cemu install dir to verify that backups are being created.

- Check the `Cemu_withGLCacheBackup.log.txt` file to look for errors or warnings.

# Logging

This script will write a log file to `Cemu_withGLCacheBackup.log.txt` whenever it is run. It can be helpful for debugging paths and settings.