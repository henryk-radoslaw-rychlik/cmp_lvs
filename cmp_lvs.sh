#!/bin/bash

function add_to_res {
	local exit_code="$?"
	local resource="${1:-}"
	verbose "function add_to_res [resource: $resource, exit_code: $exit_code]"
	resources="$resource ${resources:-}"
}

function backup_lv {
	local lv="${1:-}"
	local vg="${2:-}"
	local pv_name=$(vgs --noheadings -opv_name $vg | tr -d " ")
	verbose "function backup_lv [LV: $lv, VG: $vg]"
	chk_lv "$lv"
	chk_vg "$vg"
	echo "Merging $(echo $lv | cut -d / -f 1) and $vg"
	vgmerge "$(echo $lv | cut -d / -f 1)" "$vg"
	if [ "$?" == "0" ]; then
		echo "OK"
		echo "Converting $lv to a mirrored volume"
		lvconvert -m1 $lv $pv_name
		if [ "$?" == "0" ]; then
			echo "OK"
			echo "Activating $lv"
			lvchange -ay $lv
			if [ "$?" == "0" ]; then
				echo "OK"
				until [ "$(lvs -oraid_sync_action --noheadings $lv | tr -d ' ')" == "idle" ]; do
					echo "waiting for sync to finish"
					sleep 5
				done
				echo "Splitting of one image from the mirrored volume $lv"
				lvconvert --splitmirrors 1 -n$(echo $lv | cut -d / -f 2)_backup_$(date +%d.%m.%y) "$lv" "$pv_name"
				if [ "$?" == "0" ]; then
					echo "OK"
					echo "De-activating $lv"
					lvchange -an "$lv" "${lv}_backup_$(date +%d.%m.%y)"
					if [ "$?" == "0" ]; then
						echo "OK"
						echo "Splitting off $vg from $(echo $lv | cut -d / -f 1)"
						vgsplit "$(echo $lv | cut -d / -f 1)" "$vg" "$pv_name"
						if [ "$?" == "0" ]; then
							echo "OK"
						else
							echo "Failed to split off $vg from $(echo $lv | cut -d / -f 1), exiting!"
							exit 1
						fi
					else
						echo "Could not deactivate $lv, exiting"
						exit 1
					fi
				else
					echo "Could not split off a mirror, exiting!"
					exit 1
				fi
			else
				echo "Failed to activate $lv, exiting!"
				exit 1
			fi
		else
			echo "Failed to convert $lv, exiting!"
			exit 1
		fi
	else
		echo "Failed to merge $vg into $(echo $lv | cut -d / -f 1), exiting!"
		exit 1
	fi
}

function cecho {
    local color="${2:-}"
    local message="${1:-}"

    local blue="\e[034m"
    local default="\e[0m"
    local green="\e[032m"
    local light_blue="\e[094m"
    local red="\e[031m"
    local yellow="\e[033m"

    if [ -n "$message" ]; then
        if [ "$color" == "-blue" -o "$color" == "-green" -o "$color" == "-light_blue" -o "$color" == "-red" -o "$color" == "-yellow" ]; then
            eval "echo -e -n \$${color#-}\$message\$default"
        elif [ "$color" == "blue" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
            eval "echo -e \$$color\$message\$default"
        elif [ "$color" == "default" ]; then
            eval "echo -e \$message"
        else
            cecho "Please specify a color for function cecho, exiting!" "red"
            exit 1
        fi
    else
        cecho "Please specify a message for function cecho, exiting!" "red"
        exit 1
    fi
}

function chk_args {
	verbose "function chk_args"
	if [ -z "$vg_lv" -o -z "$vg" ]; then
		usage
	fi
}

function chk_lv {
	local lv="${1:-}"
	verbose "function chk_lv [$lv]" "blue"

	if [ -n "$lv" ]; then
		if $(lvs "$lv" 1>&3 2>&4); then
			verbose "$lv exists" "blue"
		else
			cecho "VG/LV [$lv] not found, exiting!" "red"
			usage
		fi
	else
		cecho "lv [$lv] empty, exiting!" "red"
		exit 1
	fi
}

function chk_vg {
	local vg="${1:-}"

	verbose "function chk_vg vg $vg" "blue"
	cecho "Checking VG $vg..." "-light_blue"

	if [ -n "$vg" ]; then
		if $(vgs "$vg" 1>&3 2>&4); then
			verbose "VG $vg exists" "blue"
		else
			cecho "[vg: $vg] not found, exiting!" "red"
			exit 1
		fi
	else
		cecho "[vg: $vg] empty, exiting!" "red"
		exit 1
	fi
}

function cfg_term {
	verbose "function cfg_term" "blue"
	cecho "Configuring terminal..." "-light_blue"

	set -euf -o pipefail
	trap exit_trap EXIT

	if [ "$verbose" == "yes" ]; then
		exec 3<&1
		exec 4<&2
	elif [ "$verbose" == "no" ]; then
		exec 3>/dev/null
		exec 4>/dev/null
	else
		echo "verbose variable not set correctly[nerbose=$verbose]. Please set to [no|yes] in set_variables function and try again, exiting!"
		exit 1
	fi

	cecho "OK" "green"
}

function cfg_vars {
	verbose="yes"

	verbose "function cfg_vars" "blue"

	cecho "Setting variables..." "-light_blue"

	dst_vg="$2"
	src_lv=$(echo $1 | cut -d / -f 2)
	src_vg=$(echo $1 | cut -d / -f 1)

	cecho "OK" "green"
}

function chk_for_backup {
	local lv="$(echo ${1:-} | cut -d / -f 2)"
	local vg="${2:-}"
	verbose "function chk_for_backup [lv: $lv, vg: $vg]"
	if [ -n "$vg" -a -n "$lv" ]; then
		backups=$(lvs --noheadings -doname $vg | grep "\<$lv")
	else
		echo "lv [$lv] or vg [$vg] is empty, exiting!"
		exit 1
	fi
}

function clean_up {
	verbose "function clean_up [resources: ${resources:-}]" "blue"
	cecho "Cleaning up..." "-light_blue"

	for resource in ${resources:-}; do
		if (mountpoint "$resource" > /dev/null); then
			verbose "Unmountng $resource" "blue"
			umount "$resource"
			rm_from_res "$resource"
			continue
		fi
		if [ -b "$resource" ]; then
			verbose "De-activating $resource"
			lvchange -an "$resource"
			rm_from_res "$resource"
			continue
		fi
		if [ -d "$resource" ]; then
			verbose "Deleting $resource"
			rmdir "$resource"
			rm_from_res "$resource"
			continue
		fi
	done

	cecho "OK" "green"
}

function cmp_lvs {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "function cmp_lvs [lv:$lv, vg:$vg]"
	mnt_lv "$lv"
	mnt_backups "$lv" "$vg"
	verbose "found backups: $backups"
	for backup in $backups; do
		verbose "checking $backup"
		echo "Press enter to start"
		read
		diff -ry --no-dereference --suppress-common-lines /mnt/$(echo $lv | cut -d "/" -f 2) /mnt/$backup > $(echo $lv | cut -d "/" -f 2)
		if [ "$?" == "0" ]; then
			echo "backup $backup OK"
		else
			echo "backup $backup differs"
			exit 1
		fi
	done
}

function exit_trap {
	local exit_code="$?"
	verbose "function exit_trap [exit_code: $?]" "blue"

	if [ "$exit_code" == "0" ]; then
		verbose "Exiting gracefully" "blue"
	else
		cecho "command  has exited with code [$exit_code]" "red"
	fi

	clean_up
}

function main {
	cfg_vars "$@"
	echo $@
	verbose "function main arguments" "blue"

	cfg_term
	chk_vg "$dst_vg"
	chk_vg "$src_vg"
	chk_lv "$src_vg/$src_lv"
}

function mk_dir {
	local dir="${1:-}"
	verbose "function mk_dir [$dir]"
	if [ -d "$dir" ]; then
		echo "Directory [$dir] already exists. exiting!"
		exit 1
	else
		mkdir "$dir"
		add_to_res "$dir"
	fi
}

function mnt_backups {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "function mount_backups [lv:$lv, vg:$vg]"
	chk_for_backup "$vg_lv" "$vg"
	for backup in $backups; do
		mnt_lv "$vg/$backup"
	done
}

function mnt_lv {
	local lv="${1:-}"
	local dir="/mnt/$(echo $lv | cut -d / -f 2)"
	verbose "function mnt_lv [$lv]"
	chk_lv "$lv"
	mk_dir "$dir"
	if [ ! -b /dev/"$lv" ]; then
		verbose "Trying to activate $lv"
		lvchange -ay "$lv"
	fi
	mount /dev/"$lv" "$dir"
	add_to_res "/dev/$lv"
	add_to_res "$dir"
}

function rm_from_res {
	local resource=${1:-}
	verbose "function rm_from_res [resource: $resource, resources: $resources]"
	if [ -n "$resources" ]; then
		if [ -n "resource" ]; then
			verbose "Removing $resource"
			resources=${resources#$resource }
		else
			echo "The given resource [$resource] is empty, exiting!"
			exit 1
		fi
	else
		verbose "Clean_up complete"
	fi
}

function usage {
	verbose "function usage"
	cecho "Please provide VG/LV to check the backup for and backup VG" "yellow"
	echo "$0 <VG/LV> <VG>"
	exit 1
}

function verbose {
	local color="${2:-}"
	local message="${1:-}"
	if [ "$verbose" == "yes" ]; then
		if [ "$color" == "-blue" -o "$color" == "-green" -o "$color" == "-light_blue" -o "$color" == "-red" -o "$color" == "-yellow" -o "$color" == "blue" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" -o "$color" == "default" ]; then
			if [ -n "$message" ]; then
            			cecho "$message" "$color"
        		else
				cecho "please specify message for function verbose, exiting!" "red"
   				exit 1
			fi
		else
            		cecho "Please specify a color for function verbose, exiting!" "red"
			exit 1
		fi
	elif [ "$verbose" != "no" -a "$verbose" != "yes" ]; then
		cecho "please set global variable [verbose: $verbose] to [no/yes], exiting!" "red"
		exit 1
        fi
}

main $@
