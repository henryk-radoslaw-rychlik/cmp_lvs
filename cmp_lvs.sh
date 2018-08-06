#!/bin/bash

#-------------------------------------------------
# See bottom of the file for configurable settings
#-------------------------------------------------

function add_to_res {
	local exit_code="$?"
	local resource="${1:-}"
	verbose "blue" "function add_to_res [resource: $resource, exit_code: $exit_code]"

	resources="$resource ${resources:-}"
}

function backup_lv {
	local lv="${1:-}"
	local vg="${2:-}"
	local pv_name=$(vgs --noheadings -opv_name $vg | tr -d " ")
	verbose "blue" "function backup_lv [LV: $lv, VG: $vg]"

	cecho "-light-blue" "Merging $(echo $lv | cut -d / -f 1) and $vg..."
	vgmerge "$(echo $lv | cut -d / -f 1)" "$vg"
	if [ "$?" == "0" ]; then
		cecho "green" "OK"
		cecho "-light_blue" "Converting $lv to a mirrored volume..."
		lvconvert -m1 $lv $pv_name
		if [ "$?" == "0" ]; then
			cecho "green" "OK"
			cecho "-light_blue" "Activating $lv"
			lvchange -ay $lv
			if [ "$?" == "0" ]; then
				cecho "green" "OK"
				until [ "$(lvs -oraid_sync_action --noheadings $lv | tr -d ' ')" == "idle" ]; do
					lvs --noheadings -osync_percent $lv
					sleep 5
				done
				cecho "-light_blue" "Splitting of one image from the mirrored volume $lv"
				lvconvert --splitmirrors 1 -n$(echo $lv | cut -d / -f 2)_backup_$(date +%d.%m.%y) "$lv" "$pv_name"
				if [ "$?" == "0" ]; then
					cecho "green" "OK"
					cecho "-light_blue" "De-activating $lv"
					lvchange -an "$lv" "${lv}_backup_$(date +%d.%m.%y)"
					if [ "$?" == "0" ]; then
						cecho "green" "OK"
						cecho "-light_blue" "Splitting off $vg from $(echo $lv | cut -d / -f 1)"
 						vgsplit "$(echo $lv | cut -d / -f 1)" "$vg" "$pv_name"
						if [ "$?" == "0" ]; then
							cecho "green" "OK"
						else
							cecho "red" "Failed to split off $vg from $(echo $lv | cut -d / -f 1), exiting!"
							exit 1
						fi
					else
						cecho "red" "Could not deactivate $lv, exiting"
						exit 1
					fi
				else
					cecho "red" "Could not split off a mirror, exiting!"
					exit 1
				fi
			else
				cecho "red" "Failed to activate $lv, exiting!"
				exit 1
			fi
		else
			cecho "red" "Failed to convert $lv, exiting!"
			exit 1
		fi
	else
		cecho "red" "Failed to merge $vg into $(echo $lv | cut -d / -f 1), exiting!"

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
			eval "echo -e -n \$${color#-}\$message\$default"
        	elif [ "$color" == "blue" -o "$color" == "default" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
			eval "echo -e \$$color\$message\$default"
        	else
        	    cecho "red" "Please set the \"color\" argument for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} properly and try again, exiting!"
        	    exit 1
        	fi
    	else
        	cecho "red" "Please set the \"message\" argument for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} properly and try again, exiting!"
       		exit 1
	fi
}

function chk_args {
	verbose "blue" "function chk_args"
	if [ -z "$vg_lv" -o -z "$vg" ]; then
		usage
	fi
}

function chk_lv {
	local lv="${1:-}"
	verbose "blue" "function chk_lv [$lv]"

	if [ "$(dirname $lv)" != "." -a "$(dirname $lv)" != "/" ]; then
		chk_vg "$(dirname $lv)"
	else
		cecho "red" "Logical Volume(LV) provided [$lv]doesn't seem to follow VG/LV format, please specify an LV correctly and try again, exiting!"
		exit 1
	fi

	cecho "-light_blue" "Checking LV [$lv]..."
	if $(lvs "$lv" 1>&3 2>&4); then
		cecho "green" "OK"
	else
		cecho "red" "LV [$lv] not found, exiting!"
		exit 1
	fi
}

function chk_vg {
	local vg="${1:-}"
	verbose "blue" "function chk_vg [vg: $vg]"

	if [ -n "$vg" ]; then
		cecho "-light_blue" "Checking VG $vg..."
		if $(vgs "$vg" 1>&3 2>&4); then
			cecho "green" "OK"
		else
			cecho "red" "VG [$vg] not found, exiting!"
			exit 1
		fi
	else
		cecho "red" "Please set the \"vg\" argument for the chk_vg function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} and try again, exiting!"
		exit 1
	fi
}

function configure_terminal {
	verbose "blue" "function configure_terminal"
	cecho "-light_blue" "Configuring terminal..."

	set -euf -o pipefail
	trap exit_trap EXIT

	if [ "$verbose" == "yes" ]; then
		exec 3<&1
		exec 4<&2
	elif [ "$verbose" == "no" ]; then
		exec 3>/dev/null
		exec 4>/dev/null
	else
		cecho "red" "\"verbose\" variable is not set correctly [$verbose != \"no/yes\"], please set at the bottom of the $0 file and try again, exiting!"
		exit 1
	fi

	cecho "green" "OK"
}

function configure_variables {
	local arguments="$@"
	verbose "blue" "function configure_variables [arguments: $arguments]"

	if [ "$#" -lt "1" -o "$#" -gt "3" ]; then
		cecho "red" "Number of arguments used is not supported [1<$#<4]. Please use correct arguments and try again, exiting!"
		usage
	elif [ "$#" == "3" -a "${3:-}" != "verbose" ]; then
		cecho "red" "Number of arguments used [$#] requires last one to be \"verbose\". Please use correct arguments and try again, exiting!"
		usage
	else
		cecho "-light_blue" "Setting variables..."
			local lv="$1"
		if [ "$#" == "1" ]; then
			cecho "green" "OK"
		elif [ "$#" == "2" -o "$#" == "3" ]; then
			local vg="$2"
			cecho "green" "OK"
		fi
	fi

#	dst_vg="$2"
#	src_vg="$(echo $1 | cut -d / -f 1)"
#	if [ -z "$(echo $1 | cut -d / -f 2)" ]; then
#		src_lvs="$(lvs --noheadings -oname $src_vg)"
#	else
#		src_lvs="$(echo $1 | cut -d / -f 2)"
#	fi

#	cecho "red" "\n$src_vg : $src_lv : $src_lvs : $dst_vg"
}

function chk_for_backup {
	local dst_vg="$3"
	local lv="$2"
	local vg="$1"
	verbose "blue" "function chk_for_backup [lv: $lv, vg: $vg]"

	chk_lv "$vg/$lv"
	chk_vg "$dst_vg"

	cecho "-light_blue" "Searching for existing backup..."
	echo 1
	echo $dst_vg
	backups=$(lvs --noheadings -doname $dst_vg | grep "\<$lv"; true)
	echo 2
	if [ -n "$backups" ]; then
		cecho "-light_blue" "Found $backups..."
	fi
	cecho "green" "OK"
}

function clean_up {
	verbose "blue" "function clean_up [resources: ${resources:-}]"
	cecho "-light_blue" "Cleaning up..."

	for resource in ${resources:-}; do
		if (mountpoint "$resource" > /dev/null); then
			verbose "blue" "Unmountng $resource"
			umount "$resource"
			rm_from_res "$resource"
			continue
		fi
		if [ -b "$resource" ]; then
			if (cryptsetup status "$resource"); then
				verbose "blue" "Closing encrypted $resource"
				cryptsetup close "$resource"
				rm_from_res "$resource"
				continue
			else
				verbose "blue" "De-activating $resource"
				lvchange -an "$resource"
				rm_from_res "$resource"
				continue
			fi
		fi
		if [ -d "$resource" ]; then
			verbose "blue" "Deleting $resource"
			rmdir "$resource"
			rm_from_res "$resource"
			continue
		fi
	done

	cecho "green" "OK"
}

function cmp_lvs {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "blue" "function cmp_lvs [lv:$lv, vg:$vg]"

	mnt_lv "$lv"
	mnt_backups "$lv" "$vg"

	for backup in $backups; do
		cecho "-light_blue" "checking $backup..."
		diff -ry --no-dereference --suppress-common-lines /mnt/$(echo $lv | cut -d "/" -f 2) /mnt/$backup > $(echo $lv | cut -d "/" -f 2)-$vg-$backup
		if [ "$?" == "0" ]; then
			cecho "green" "OK"
		else
			cecho "yellow" "backup $backup differs"
			exit 1
		fi
	done
}

function exit_trap {
	local exit_code="$?"
	verbose "blue" "function exit_trap [exit_code: $?]"

	if [ "$exit_code" == "0" ]; then
		verbose "blue" "Exiting gracefully"
	else
		cecho "red" "command  has exited with code [$exit_code]"
	fi

	clean_up
}

function get_answer {
    read answer
    while [ "$answer" != "no" -a "$answer" != "yes" ]; do
        cecho "yellow" "Please choose the correct answer[no/yes]!"
        read answer
    done
}

function main {
	arguments="$@"
	verbose "blue" "function main [arguments: $arguments]"

	configure_terminal
	configure_variables $arguments

	exit 0

	for src_lv in "$src_lvs"; do
		chk_for_backup "$src_vg" "$src_lv" "$dst_vg"
		if [ -n "$backups" ]; then
			cecho "default" "Would you like to compare[no/yes]?"
			get_answer
			if [ "$answer" == "yes" ]; then
				cmp_lvs "$src_vg/$src_lv" "$dst_vg"
			else
				cecho "blue" "OK buddy, exiting"
				exit 0
			fi
		else
			cecho "blue" "No backups found, would you like to create[no/yes]?"
			get_answer
			if [ "$answer" == "yes" ]; then
				backup_lv "$src_vg/$src_lv" "$dst_vg"
			else
				cecho "blue" "OK buddy, exiting"
				exit 0
			fi
		fi
	done
}

function mk_dir {
	local dir="${1:-}"
	verbose "blue" "function mk_dir [$dir]"

	if [ -d "$dir" ]; then
		cecho "red" "Directory [$dir] already exists. exiting!"
		exit 1
	else
		mkdir "$dir"
		add_to_res "$dir"
	fi
}

function mnt_backups {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "blue" "function mount_backups [lv:$lv, vg:$vg]"

	for backup in $backups; do
		mnt_lv "$vg/$backup"
	done
}

function mnt_lv {
	local lv="${1:-}"
	local dir="/mnt/$(echo $lv | cut -d / -f 2)"
	verbose "blue" "function mnt_lv [LV: $lv, DIR: $dir]"
	cecho "-light_blue" "Mounting $lv at $dir..."

	mk_dir "$dir"
	if [ ! -b /dev/"$lv" ]; then
		cecho "blue" "/dev/$lv does not exist, trying to activate..."
		lvchange -ay "$lv"
		if [ "$?" == "0" ]; then
			cecho "green" "OK"
		else
			cecho "red" "Failed to activate LV $lv, exiting!"
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
	verbose "blue" "function rm_from_res [resource: $resource, resources: $resources]"
	if [ -n "$resources" ]; then
		if [ -n "resource" ]; then
			verbose "blue" "Removing $resource"
			resources=${resources#$resource }
		else
			echo "The given resource [$resource] is empty, exiting!"
			exit 1
		fi
	else
		verbose "blue" "Clean_up complete"
	fi
}

function usage {
	verbose "blue" "function usage"

	cecho "yellow" "Usage:\n\n\
			$0 VG/LV VG [verbose]\n\
			VG/LV - Logical Volume(LV) in Volume Group(VG) to compare or back up\n\
			VG - Volume Group with backup or destination\n\n\
			$0 VG/LV [verbose]\n\
			VG/LV - Logical Volume(LV) in Volume Group(VG) to activate/deactivate and mount/unmount"
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
verbose="no"
#===========

# Checking for the verbose option early on to cover all the functions
#=====================================
if [ "$BASH_ARGV" == "verbose" ]; then
	verbose="yes"
fi
#=====================================

# Main function
#========
main "$@"
#========
