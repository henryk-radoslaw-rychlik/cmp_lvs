#!/bin/bash

#-------------------------------------------------
# See bottom of the file for configurable settings
#-------------------------------------------------

function add_to_res {
	local exit_code="$?"
	local resource="${1:-}"
	verbose "function add_to_res [resource: $resource, exit_code: $exit_code]" "blue"

	resources="$resource ${resources:-}"
}

function backup_lv {
	local lv="${1:-}"
	local vg="${2:-}"
	local pv_name=$(vgs --noheadings -opv_name $vg | tr -d " ")
	verbose "function backup_lv [LV: $lv, VG: $vg]" "blue"

	cecho "-light-blue" "Merging $(echo $lv | cut -d / -f 1) and $vg..."
	vgmerge "$(echo $lv | cut -d / -f 1)" "$vg"
	if [ "$?" == "0" ]; then
		cecho "green" "OK"
		cecho "-light_blue" "Converting $lv to a mirrored volume..."
		lvconvert -m1 $lv $pv_name
		if [ "$?" == "0" ]; then
			cecho "OK" "green"
			cecho "Activating $lv" "-light_blue"
			lvchange -ay $lv
			if [ "$?" == "0" ]; then
				cecho "OK" "green"
				until [ "$(lvs -oraid_sync_action --noheadings $lv | tr -d ' ')" == "idle" ]; do
					lvs --noheadings -osync_percent $lv
					sleep 5
				done
				cecho "Splitting of one image from the mirrored volume $lv" "-light_blue"
				lvconvert --splitmirrors 1 -n$(echo $lv | cut -d / -f 2)_backup_$(date +%d.%m.%y) "$lv" "$pv_name"
				if [ "$?" == "0" ]; then
					cecho "OK" "green"
					cecho "De-activating $lv" "-light_blue"
					lvchange -an "$lv" "${lv}_backup_$(date +%d.%m.%y)"
					if [ "$?" == "0" ]; then
						cecho "OK" "green"
						cecho "Splitting off $vg from $(echo $lv | cut -d / -f 1)" "-light_blue"
 						vgsplit "$(echo $lv | cut -d / -f 1)" "$vg" "$pv_name"
						if [ "$?" == "0" ]; then
							cecho "OK" "green"
						else
							cecho "Failed to split off $vg from $(echo $lv | cut -d / -f 1), exiting!" "red"
							exit 1
						fi
					else
						cecho "Could not deactivate $lv, exiting" "red"
						exit 1
					fi
				else
					cecho "Could not split off a mirror, exiting!" "red"
					exit 1
				fi
			else
				cecho "Failed to activate $lv, exiting!" "red"
				exit 1
			fi
		else
			cecho "Failed to convert $lv, exiting!" "red"
			exit 1
		fi
	else
		cecho "Failed to merge $vg into $(echo $lv | cut -d / -f 1), exiting!" "red"
		exit 1
	fi
}

function cecho {
	local color="${1:-}"
    	local message="${2:-}"

	local blue="\e[034m"
    	local default="\e[0m"
    	local green="\e[032m"
    	local light_blue="\e[094m"
    	local red="\e[031m"
    	local yellow="\e[033m"

	if [ -n "$message" ]; then
        	if [ "$color" == "-blue" -o "$color" == "default" -o "$color" == "-green" -o "$color" == "-light_blue" -o "$color" == "-red" -o "$color" == "-yellow" ]; then
        	    echo aaab
			eval "echo -e -n \$${color#-}\$message\$default"
        	elif [ "$color" == "blue" -o "$color" == "default" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
			eval "echo -e \$$color\$message\$default"
        	else
        	    cecho "red" "Please set the \"color\" argument properly for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} and try again, exiting!"
        	    exit 1
        	fi
    	else
        	cecho "red" "Please set the \"message\" argument properly for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} and try again, exiting!"
       		exit 1
	fi
}

function chk_args {
	verbose "function chk_args" "blue"
	if [ -z "$vg_lv" -o -z "$vg" ]; then
		usage
	fi
}

function chk_lv {
	local lv="${1:-}"
	verbose "function chk_lv [$lv]" "blue"
	cecho "Checking LV [$lv]..." "-light_blue"

	if [ -n "$lv" ]; then
		if $(lvs "$lv" 1>&3 2>&4); then
			cecho "OK" "green"
		else
			cecho "LV [$lv] not found, exiting!" "red"
			exit 1
		fi
	else
		cecho "LV empty, exiting!" "red"
		exit 1
	fi
}

function chk_vg {
	local vg="${1:-}"

	verbose "function chk_vg arguments:[vg: $vg]" "blue"
	cecho "Checking VG $vg..." "-light_blue"

	if [ -n "$vg" ]; then
		if $(vgs "$vg" 1>&3 2>&4); then
			cecho "OK" "green"
		else
			cecho "VG [$vg] not found, exiting!" "red"
			exit 1
		fi
	else
		cecho "VG empty, exiting!" "red"
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
		cecho "verbose variable not set correctly [verbose=$verbose]. Please set to [no|yes] in set_variables function and try again, exiting!" "red"
		exit 1
	fi

	cecho "OK" "green"
}

function cfg_vars {
	if [ "$3" == "verbose" ]; then
		verbose="yes"
	elif [ "$3" != "verbose" -a "$3" != "" ]; then
		usage
	fi

	verbose "function cfg_vars arguments: [$(echo $@)]" "blue"

	if [ "$#" -lt "2" ]; then
		usage
	fi

	cecho "Setting variables..." "-light_blue"

	dst_vg="$2"
	src_vg="$(echo $1 | cut -d / -f 1)"
	if [ -z "$(echo $1 | cut -d / -f 2)" ]; then
		src_lvs="$(lvs --noheadings -oname $src_vg)"
	else
		src_lvs="$(echo $1 | cut -d / -f 2)"
	fi

	cecho "\n$src_vg : $src_lv : $src_lvs : $dst_vg" "red"

	cecho "OK" "green"
}

function chk_for_backup {
	local dst_vg="$3"
	local lv="$2"
	local vg="$1"
	verbose "function chk_for_backup [lv: $lv, vg: $vg]" "blue"

	chk_lv "$vg/$lv"
	chk_vg "$dst_vg"

	cecho "Searching for existing backup..." "-light_blue"
	echo 1
	echo $dst_vg
	backups=$(lvs --noheadings -doname $dst_vg | grep "\<$lv"; true)
	echo 2
	if [ -n "$backups" ]; then
		cecho "Found $backups..." "-light_blue"
	fi
	cecho "OK" "green"
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
			if (cryptsetup status "$resource"); then
				verbose "Closing encrypted $resource" "blue"
				cryptsetup close "$resource"
				rm_from_res "$resource"
				continue
			else
				verbose "De-activating $resource" "blue"
				lvchange -an "$resource"
				rm_from_res "$resource"
				continue
			fi
		fi
		if [ -d "$resource" ]; then
			verbose "Deleting $resource" "blue"
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
	verbose "function cmp_lvs [lv:$lv, vg:$vg]" "blue"

	mnt_lv "$lv"
	mnt_backups "$lv" "$vg"

	for backup in $backups; do
		cecho "checking $backup..." "-light_blue"
		diff -ry --no-dereference --suppress-common-lines /mnt/$(echo $lv | cut -d "/" -f 2) /mnt/$backup > $(echo $lv | cut -d "/" -f 2)-$vg-$backup
		if [ "$?" == "0" ]; then
			cecho "OK" "green"
		else
			cecho "backup $backup differs" "yellow"
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

function get_answer {
    read answer
    while [ "$answer" != "no" -a "$answer" != "yes" ]; do
        cecho "Please choose the correct answer[no/yes]!" "yellow"
        read answer
    done
}

function main {
	arguments=${@:-}
	verbose "blue" "function main [arguments: $arguments]"
	exit 0
	cfg_vars "$@"
	cfg_term

	for src_lv in "$src_lvs"; do
		chk_for_backup "$src_vg" "$src_lv" "$dst_vg"
		if [ -n "$backups" ]; then
			cecho "Would you like to compare[no/yes]?" "default"
			get_answer
			if [ "$answer" == "yes" ]; then
				cmp_lvs "$src_vg/$src_lv" "$dst_vg"
			else
				cecho "OK buddy, exiting" "blue"
				exit 0
			fi
		else
			cecho "No backups found, would you like to create[no/yes]?" "blue"
			get_answer
			if [ "$answer" == "yes" ]; then
				backup_lv "$src_vg/$src_lv" "$dst_vg"
			else
				cecho "OK buddy, exiting" "blue"
				exit 0
			fi
		fi
	done
}

function mk_dir {
	local dir="${1:-}"
	verbose "function mk_dir [$dir]" "blue"

	if [ -d "$dir" ]; then
		cecho "Directory [$dir] already exists. exiting!" "red"
		exit 1
	else
		mkdir "$dir"
		add_to_res "$dir"
	fi
}

function mnt_backups {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "function mount_backups [lv:$lv, vg:$vg]" "blue"

	for backup in $backups; do
		mnt_lv "$vg/$backup"
	done
}

function mnt_lv {
	local lv="${1:-}"
	local dir="/mnt/$(echo $lv | cut -d / -f 2)"
	verbose "function mnt_lv [LV: $lv, DIR: $dir]" "blue"
	cecho "Mounting $lv at $dir..." "-light_blue"

	mk_dir "$dir"
	if [ ! -b /dev/"$lv" ]; then
		cecho "/dev/$lv does not exist, trying to activate..." "blue"
		lvchange -ay "$lv"
		if [ "$?" == "0" ]; then
			cecho "OK" "green"
		else
			cecho "Failed to activate LV $lv, exiting!" "red"
			exit 1
		fi
	fi
	add_to_res "/dev/$lv"
	if (cryptsetup isLuks /dev/"$lv"); then
		cryptsetup luksOpen /dev/"$lv" "$(echo $lv | cut -f 2 -d /)"
		mount /dev/mapper/"$(echo $lv | cut -f 2 -d /)" "$dir"
		add_to_res /dev/mapper/"$(echo $lv | cut -f 2 -d /)"
	else
		mount /dev/"$lv" "$dir"
	fi
	add_to_res "$dir"
}

function rm_from_res {
	local resource=${1:-}
	verbose "function rm_from_res [resource: $resource, resources: $resources]" "blue"
	if [ -n "$resources" ]; then
		if [ -n "resource" ]; then
			verbose "Removing $resource" "blue"
			resources=${resources#$resource }
		else
			echo "The given resource [$resource] is empty, exiting!"
			exit 1
		fi
	else
		verbose "Clean_up complete" "blue"
	fi
}

function usage {
	verbose "function usage" "blue"
	cecho "usage:" "yellow"
	cecho "$0 VG/LV VG" "yellow"
	cecho "VG/LV - Logical Volume in Volume Group to compare or back up" "yellow"
	cecho "VG - Volume Group with backup or destination" "yellow"
	exit 1
}

function verbose {
	local color="${1:-}"
	local message="${2:-}"

	if [ -n "$color" ]; then
		if [ -n "$message" ]; then
			if [ "$verbose" == "yes" ]; then
            			cecho "$color" "$message"
			elif [ "$verbose" != "no" -a "$verbose" != "yes" ]; then
				cecho "red" "Please set the global \"verbose\" variable properly [\"$verbose\" != no/yes] at the bottom of the $0 file and try again, exiting!"
				exit 1
        		fi
        	else
			cecho "red" "Please set the \"message\" argument properly for the verbose function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} and try again, exiting!"
   			exit 1
		fi
	else
		cecho "red" "Please set the \"color\" argument properly for the verbose function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} and try again, exiting!"
		exit 1
	fi
}

# Configurable settings
#===========
verbose="yes"
#===========

# Main function
#========
main "$@"
#========
