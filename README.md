# Mac System Data check

A free, read-only Terminal script that shows what is inside **System Data** on a Mac: the gray bar in System Settings > General > Storage that macOS never explains.

It prints APFS and Time Machine snapshots, swap and sleepimage, the largest folders in `~/Library`, hidden tool caches in your home folder, system folders stored on the Data volume, Spotlight status, and developer tools such as Xcode, simulators, Docker and Ollama. Each section links to a guide that explains what you found and what is safe to remove.

## Run it

Read it first, then run it:

```bash
curl -fsSLO https://raw.githubusercontent.com/AIiteo/mac-system-data-check/main/system-data-check.sh
less system-data-check.sh
bash system-data-check.sh
```

The same file is also served at https://hoardless.app/tools/system-data-check.sh.

It takes a minute or two on a full disk. Folders macOS protects are skipped and counted; give Terminal Full Disk Access (System Settings > Privacy & Security) to include them.

## What it will never do

- Delete, move, rename or write any file, not even a temp file
- Ask for an admin password or use `sudo`
- Change a setting or send anything over the network

Every command it runs is a read: `df`, `du`, `sysctl`, `sw_vers`, `getconf`, `xcode-select -p`, `tmutil listlocalsnapshots`, `diskutil apfs listSnapshots`, `mdutil -s`, `docker context inspect` and `docker system df` (local Docker only), `simctl list`, `simctl runtime list` and `ollama list`.

## What it prints

| Section | What you learn |
|---|---|
| 1. Data volume | Used, free and total space on the volume where System Data lives |
| 2. APFS snapshots | Time Machine local snapshots and every APFS snapshot, with the macOS update snapshot to leave alone |
| 3. Swap and sleepimage | Virtual memory swap and the hibernation file |
| 4. Largest folders in ~/Library | The top 15, with a total |
| 5. Places that often hide tens of GB | Caches, iOS backups, Mail, Messages, Trash |
| 6. Hidden folders in your home | npm, pip, Hugging Face, Ollama and other tool caches |
| 7. System folders on the Data volume | Paths under /System and /Library stored on the Data volume |
| 8. Spotlight indexing | Whether a reindex may be inflating System Data |
| 9. Developer tools | Xcode, simulators, Docker and Ollama, only the ones installed |

Sizes are decimal, like Finder and Storage settings (1 GB = 1,000,000,000 bytes). `du` counts APFS clones and sparse files by the blocks they hold, so a sum of folders can differ from the volume's used figure.

## Guides

- [What is System Data on a Mac](https://hoardless.app/guides/system-data-mac)
- [See what is inside System Data](https://hoardless.app/guides/see-inside-system-data-mac)
- [System Data is 100 GB or more](https://hoardless.app/guides/system-data-100gb-mac)
- [System Data keeps growing](https://hoardless.app/guides/system-data-keeps-growing-mac)
- [Storage settings stuck on Calculating](https://hoardless.app/guides/mac-storage-stuck-calculating)
- [Purgeable space on a Mac](https://hoardless.app/guides/purgeable-space-mac)

## Requirements

macOS with the `/bin/bash` 3.2 it ships with. Works when piped into bash. Apple silicon and Intel.

## Want the full picture?

The script lists folders; it cannot tell you which bytes are safe to remove. [Hoardless](https://hoardless.app/) scans the whole disk into a local index, shows every byte by folder, app and date added, and previews every removal before anything moves to the Trash. One-time purchase, 14-day free trial.

## License

MIT. See [LICENSE](LICENSE).
