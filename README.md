# rockbox-music-sync
Monolithic Bash script for syncing music libraries to Rockbox powered iPod 6g.

I used this script for a long time on my mSATA iPod 6g as part of my daily commute before finally switching to Plex (and Covid removing the commute!) on my phone to stream my music library.

It works by using `rsync` to transfer a directory of mp3s and to use `ffmpeg` with `parallel` to transcode FLAC files to LAME mp3 'proxies' to maximise available disk space.

You will need to provide the binary of [scramble](https://github.com/Rockbox/rockbox/blob/master/tools/scramble.c) if you have more than 10000 tracks and wish to easily increase the maximum playlist size. (Take note of functions `update_rockbox` and `hex_edit_boot`.)

You will also need to provide the filesystem uuid in variable `$fs_uuid` from the output of `udisksctl dump`.
Pay attention to `$mp3_dir` and `$flac_dir` as well as the destination paths in function `normal_run`

I recommend thoroughly reading the script before attempting to adapt it to your use case as this repo is more of a dump than a maintained project.
