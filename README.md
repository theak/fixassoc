# fixassoc

A small macOS command-line tool for fixing default apps. It lists every file extension in a folder, most common first, with the app each one opens in. You can then pick a new default from the apps that support that type, or from every installed app.

```
File types in /Users/you/Downloads
  #   ext         count   default app                 type
   1  .json       219     Sublime Text                public.json
   2  .jpg        125     Preview                     public.jpeg
   3  .wav        101     Music                       com.microsoft.waveform-audio
   4  .pdf        99      Preview                     com.adobe.pdf
   ...
```

## Install

Requires macOS 12 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
swiftc -O fixassoc.swift -o fixassoc
mv fixassoc ~/.local/bin/   # or anywhere on your PATH
```

## Usage

```sh
fixassoc            # scan the current folder
fixassoc -r         # include subfolders
fixassoc ~/Desktop  # scan another folder
```

- Type a row number or an extension like `.mp4` to change its default app.
- In the app list, type text to filter it, `a` to switch to all installed apps, or a number to choose.
- `r` rescans the folder and `q` quits.

Don't run it with `sudo`. Default apps are a per-user setting, so sudo would change root's defaults instead of yours.

## Notes

- **Shared types:** extensions that map to the same type, like `.jpg` and `.jpeg` (`public.jpeg`), change together.
- **Unregistered types:** when no installed app declares an extension, macOS gives it a temporary type ID, and a default you set for it may not stick.
- **Files only:** this doesn't change defaults for URL schemes like `http` or `mailto`.
