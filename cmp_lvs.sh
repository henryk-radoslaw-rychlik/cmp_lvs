#!/bin/bash
vg_lv="${1:-}"
vg="${2:-}"

function add_to_res {
	local exit_code="$?"
	local resource="${1:-}"
	verbose "function add_to_res [dir: $dir, exit_code: $exit_code]"
	resources="$resource ${resources:-}"
}

function chk_args {
	verbose "function chk_args"
	if [ -z "$vg_lv" -o -z "$vg" ]; then
		usage
	fi
}

function chk_lv {
	local lv="${1:-}"
	verbose "function chk_lv [$lv]"
	if $(lvs "$lv" 1>&3 2>&4); then
		verbose "$lv exists"
	else
		echo "VG/LV [$lv] not found, exiting!"
		exit 1
	fi
}

function chk_vg {
	local vg="${1:-}"
	verbose "function chk_vg [$vg]"
	if $(vgs "$vg" 1>&3 2>&4); then
		verbose "$vg exists"
	else
		echo "VG [$vg] not found, exiting!"
		exit 1
	fi
}

function cfg_term {
	if [ "$verbose" == "yes" ]; then
		exec 3<&1
		exec 4<&2
	elif [ "$verbose" == "no" ]; then
		exec 3>/dev/null
		exec 4>/dev/null
	else
		echo "verbose variable not set correctly[$verbose]. Please set to [no|yes] in set_variables function and try again, exiting!"
		exit 1
	fi

	trap exit_trap EXIT
	set -euf -o pipefail
}

function cfg_vars {
	verbose="no"
}

function chk_for_backup {
	local lv="$(echo ${1:-} | cut -d / -f 2)"
	local vg="${2:-}"
	verbose "function chk_for_backup [lv: $lv, vg: $vg]"
	if [ -n "$vg" -a -n "$lv" ]; then
		backups="$(lvs --noheadings -doname $vg | grep $lv)"
	else
		echo "lv [$lv] or vg [$vg] is empty, exiting!"
		exit 1
	fi
}

function clean_up {
	verbose "function clean_up [resources: $resources]"
	for resource in $resources; do
		if (mountpoint $resource 1>&3 2>&4); then
			umount "$resource"
			rm_from_res "$resource"
			continue
		fi
		if [ -b "$resource" ]; then
			lvchange -an "$resource"
			rm_from_res "$resource"
			continue
		fi
		if [ -d "$resource" ]; then
			rmdir "$resource"
			rm_from_res "$resource"
			continue
		fi
	done
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
		diff -r /mnt/$(echo $lv | cut -d "/" -f 2) /mnt/$backup
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
	verbose "function exit_trap"

	if [ "$exit_code" == "0" ]; then
		verbose "Exiting gracefully"
	else
		echo "command !! has exited with [$exit_code]"
	fi
	clean_up
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
		add_to_res "/dev/$lv"
	fi
	mount /dev/"$lv" "$dir"
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
	echo "Please provide VG/LV to check the backup for and backup VG"
	exit 1
}

function verbose {
	local message="${1:-}"

	if [ -z "$message" ]; then
		echo "An empty message has been provided, exiting!"
		exit 1
	fi

	if [ "$verbose" == "yes" ]; then
		echo "$message"
	elif [ "$verbose" != "no" ] && [ "$verbose" != "yes" ]; then
		echo "verbose2 variable not set correctly[$verbose]. Please set it in configure_variables function and try again, exiting!"
		exit 1
	fi
}

cfg_vars
cfg_term
cmp_lvs "$vg_lv" "$vg"
clean_up
