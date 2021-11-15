#!/usr/bin/env bash
#set -o errexit
set -o nounset
#set -x

function mount_ipod
{
	##REPLACE WITH YOUR IPODS FILESYSTEM UUID
	#fs_uuid=0B2B-08C9 RIP ORIGINAL IPOD CLASSIC THAT WAS STOLEN
	#fs_uuid=104D-11B9
	fs_uuid=B29D-7CF9
	is_connected=$(udisksctl dump | grep -A3 "\/by-uuid\/$fs_uuid")
	mount_point=$(udisksctl dump | grep -A3 "\/by-uuid\/$fs_uuid" | grep MountPoints | awk '{print $2}')
	if [[ -n $is_connected ]]
	then
	printf 'Mounting iPod...'
		if [[ -z "$mount_point" ]]; then mount_point=$(udisksctl mount -b /dev/disk/by-uuid/$fs_uuid | awk '{print $4}' | cut -f 1 -d '.'); fi
	printf 'OK\n'
	else
		echo -e "Connect iPod to system first...\n"
		read -rsp $'Press any key to exit...\n' -n 1 key
		exit
	fi
}

function unmount_ipod
{
	printf '\nUnmounting iPod...'
		umount "$mount_point"
	printf 'OK\n'
}

function hex_edit_boot()
{
printf 'Applying custom hex edits to boot file...'
	ipod_boot="$mount_point/.rockbox/rockbox.ipod"
	ipod_bin="$(dirname "$ipod_boot")/$(basename "$ipod_boot" .ipod).bin"
	##################################################################
	# chop checksum and device id off from the beginning of the boot #
	##################################################################
	tail -c $(( $(stat -c %s "$ipod_boot") - 8 )) "$ipod_boot" > "$ipod_bin"
	rm "$ipod_boot" # delete the old scrambled boot file #
	#######################################################################
	# hexedit the default max_files_in_playlist to 99999 instead of 10000 #
	#######################################################################
	sed -i 's/\xFA\x00\x00\x00\x10\x27\x00\x00/\xFA\x00\x00\x00\x9F\x86\x01\x00/' "$ipod_bin"
	./scramble -add=ip6g "$ipod_bin" "$ipod_boot" # use scramble to fix the header on our hex-edited file #
	rm "$ipod_bin" # delete backups #
printf 'OK\n'
}

function tidy_music_dir()
{
printf '\nCleaning music folder...'	
	source_dir="$1"
	if [[ -d "$source_dir" ]]
	then
		dest_dir="$2"
		while IFS='' read -r -d '' directory
		do
			dest_path="$source_dir$(echo "$directory" | cut -c "$(echo "$dest_dir" | wc -c)"-)"
			if [[ ! -d "$dest_path" ]]; then rm -rf "$directory"; fi
		done < <(find "$dest_dir" -type d -print0)
	fi
printf 'OK\n'
}

function transcode_flac()
{
printf '\nSearching for new FLAC files to transcode...'
	## https://wiki.archlinux.org/index.php/Convert_Flac_to_Mp3
	## http://mywiki.wooledge.org/BashFAQ/020
	source_dir="$1"
	dest_dir="$2"
	enc_script="$c_dir/encode_script.sh"
	##################################################
	## Find FLAC Files and transcode them			##
	##################################################
	if [[ -f "$enc_script" ]]; then rm "$enc_script"; fi
	while IFS='' read -r -d '' filename
	do
		src_file_name="$(basename "$filename")"
		src_directory_name="$(dirname "$filename")"
		
		dest_mp3_name="${src_file_name[@]/%.flac/.mp3}"
		dest_path="$dest_dir/$(echo "$src_directory_name" | cut -c "$(echo "$source_dir" | wc -c)"-)"
		dest_file_path="$dest_path/$dest_mp3_name"
		
		if [[ ! -f "$dest_file_path" ]]
		then
			mkdir -p "$dest_path"
			## https://trac.ffmpeg.org/wiki/Encode/MP3
			## http://wiki.hydrogenaud.io/index.php?title=LAME
			## https://arstechnica.com/civis/viewtopic.php?t=1138392
			lame_vbr_level=0
			echo ffmpeg -hide_banner -loglevel quiet -i \""$filename\"" -qscale:a $lame_vbr_level \""$dest_file_path\"" >> "$enc_script"
		fi
	done < <(find "$source_dir" -mindepth 1 -type f -iname "*.flac" -print0)
	printf 'OK\n'
	####################################################################################################################################
	## if we wrote the encoding script then we found new flac files. transcode using parallel. kludgey but it works surpirsingly well ##
	####################################################################################################################################
	if [[ -f "$enc_script" ]]
	then
		total_tracks="$(wc -l "$enc_script" | cut -f 1 -d' ')"
		#printf "\nTranscoding %s new FLAC file(s) to LAME MP3 VBR 0..." "$total_tracks"
		#printf "\nTranscoding new FLAC file(s) to LAME MP3 VBR 0..."
		cat "$enc_script" | sed 's/\$/\\$/g' | parallel &
		sleep 1s
		while [[ $(pgrep parallel) ]]
		do
			foo1="$(ps a | grep -o 'ffmpeg.*' | grep -o '\/.*mp3' | sort | tail -n1)"
			foo2="$(basename "$foo1")"
			current_track="$(grep -n "$foo2" "$enc_script" | cut -f1 -d:)"
			
			## https://stackoverflow.com/a/24777667
			#if [[ $current_track -lt $total_tracks ]]; then echo -ne "Transcoding new FLAC file(s) to LAME MP3 VBR 0... $current_track / $total_tracks\r"; fi
			if [[ ${current_track#0} -lt ${total_tracks#0} ]]
			then
				if [[ -n $current_track && -n $total_tracks ]]
				then
					echo -ne "Transcoding new FLAC file(s) to LAME MP3 VBR $lame_vbr_level... $current_track / $total_tracks\r"
				fi
			fi
		done
		echo -ne "\r"
		printf 'OK\n'
	fi	
}

function update_rockbox()
{
	rockbox_info="$mount_point/.rockbox/rockbox-info.txt"
	build_info="$(wget -qO - https://www.rockbox.org/dl.cgi?bin=ipod6g | grep "$(date +%F)" )"
	if [[ -z "$build_info" ]] # today's build doesn't exist yet?
	then
		## We'll take yesterday's build thank you very much
		build_info="$(wget -qO - https://www.rockbox.org/dl.cgi?bin=ipod6g | grep "$(date --date yesterday +%F)" )"
	fi
	latest_svn="$(echo "$build_info" | grep -Eo '[a-z0-9]{7}' | tail -n 1)"
	current_svn="$(grep 'Version' "$rockbox_info" | cut -c 10-16)"
		echo -e "\nLatest Rockbox SVN Revision: $latest_svn"
		echo -e "Current Rockbox SVN Revision: $current_svn\n"

	if [[ -n "$current_svn" && -n "$latest_svn" ]];
	then
		if [[ "$current_svn" != "$latest_svn" ]]
		then
			printf 'Updating iPod rockbox to latest revision...'
			dl_url="http://download.rockbox.org/daily/ipod6g/rockbox-ipod6g.zip"
			zip_name="$(basename "$dl_url")"
			
			if [[ ! -f "/tmp/$zip_name" ]]; then wget -q "$dl_url" -O "/tmp/$zip_name"; fi
			unzip -qo "/tmp/$zip_name" -d "$mount_point/"
			printf 'OK\n'
			hex_edit_boot
		else
			echo -e "Rockbox is already up to date.\n"
		fi
	fi
}

function rsync_mp3s()
{
printf '\nSyncing music to iPod...'
	source_dir="$1"
	dest_dir="$2"
	excludes_file="$c_dir/excludes.txt"
	if [[ "$#" -eq "3" ]]
	then
		if [[ "$3" == "--delete" ]]
		then
			rsync -qrtm --safe-links --modify-window=2 --delete "$source_dir" "$dest_dir" --exclude-from="$excludes_file"
		fi
	else
		rsync -qrtm --safe-links --modify-window=2 "$source_dir" "$dest_dir" --exclude-from="$excludes_file"
	fi
printf 'OK\n'
}

function create_playlists()
{
printf '\nCreating updated playlists for the current sync...'
	playlist_file="$mount_point/Music/music.m3u"
		
	## Create a playlist file of the current date containing only the new tracks, makes it easy to listen to the new tunes!
	if [[ -f "$playlist_file" ]]
	then
		playlist_tmp="$mount_point/Music/music_tmp.m3u"
		playlist_of_sync="$(dirname "$playlist_file")/$(basename "$playlist_file" .m3u)_$(date '+%y_%m_%d_%H_%M').m3u"
		
		## move any previous sync playlists into the playlist archive.
		find "$mount_point/Music/" -maxdepth 1 -type f -iname "music_*.m3u" -exec sed -i "s%^%/Music/%g" "{}" \;
		find "$mount_point/Music/" -maxdepth 1 -type f -iname "music_*.m3u" -exec mv "{}" "$mount_point/Music/Playlists/" \;
		
		mv "$playlist_file" "$playlist_tmp"
		
		find "$mount_point/Music/" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.ape" -o -iname "*.wav" -o -iname "*.wma" \) -print | sed "s%$mount_point/Music/%%g" | sort -t / -k 2  > "$playlist_file"
		
		diff --unchanged-group-format='' "$playlist_file" "$playlist_tmp" > "$playlist_of_sync"
		rm "$playlist_tmp"
		
		## work through our playlist of the day and the removed entries which have been deleted (no longer exist on the ipod) this fixes the direction of the diffing crudely so everything is playable
		## "$playlist_of_sync" can be zero length so take that into account
		while read -r line; do if [[ -f "$mount_point/Music/$line" ]]; then echo "$line" >> "$playlist_of_sync.new"; fi; done < "$playlist_of_sync"; rm "$playlist_of_sync"; mv "$playlist_of_sync.new" "$playlist_of_sync"
		
		## check if we have run a previous sync today and concatenate them together
		## deleting the previous syncs playlists after they are joined
		todays_playlists="$(dirname "$playlist_file")/$(basename "$playlist_file" .m3u)_$(date '+%y_%m_%d')"
		if [[ $( find "$todays_playlists"*.m3u -maxdepth 1 -type f | wc -l ) -gt 1 ]]
		then
			sort "$todays_playlists"*.m3u -o "$todays_playlists".m3u
			rm "$todays_playlists"_*.m3u
		fi
	else
		## make a playlist if one doesn't exist
		find "$mount_point/Music/" -type f -iname "*.mp3" -print | sed "s%$mount_point/Music/%%g" | sort  >> "$playlist_file"
	fi
printf 'OK\n'	
}

function normal_run()
{
	mount_ipod
		## no longer updating to nightlies as 3.15 is in feature freeze
		#update_rockbox
		#hex_edit_boot
		
		mp3_dir="/media/Share/Music/albums [MP3]"
		flac_dir="/media/Share/Music/albums [FLAC]"

		tidy_music_dir "$flac_dir/" "$mount_point/Music/albums [FLAC_XCODE]"
		transcode_flac "$flac_dir/" "$mount_point/Music/albums [FLAC_XCODE]"
		
		rsync_mp3s "$mp3_dir/" "$mount_point/Music/albums [MP3]/" "--delete"
		tidy_music_dir "$mp3_dir/" "$mount_point/Music/albums [MP3]"
		
		create_playlists
		
	unmount_ipod
	read -rsp $'\niPod sync script complete. Press any key to exit...\n' -n 1 key
}

c_dir="$(realpath "$(dirname "$0")")"

normal_run
#testing
