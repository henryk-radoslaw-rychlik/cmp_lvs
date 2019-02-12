#!/bin/bash

#-------
# TODO:
# - fsck
# - no LVs passed
# mount check if mounted
#-------

#-------------------------------------------------
# See bottom of the file for configurable settings
#-------------------------------------------------

function add_to_res {
	local exit_code="$?"
	local resource="${1:-}"  
	verbose "blue" "function add_to_res [resource: $resource, exit_code: $exit_code]"

	resources_to_clean="$resource ${resources_to_clean:-}"
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
			eval "echo -e -n \$${color#-}\${message[@]}\$default"
        	elif [ "$color" == "blue" -o "$color" == "default" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
			eval "echo -e \$$color\${message[@]}\$default"
        	else
        	    cecho "red" "Please set the \"color\" argument for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} properly and try again, exiting!"
        	    exit 1
        	fi
    	else
        	cecho "red" "Please set the \"message\" argument for the cecho function at line ${BASH_LINENO[$((${#BASH_LINENO[@]} - 2))]} properly and try again, exiting!"
       		exit 1
	fi
}

function check_function_arguments {
	verbose "blue" "function check_function_arguments"
	check_number_of_arguments_passed "check_function_arguments" "0" "$#"
	
	if [ -z "$vg_lv" -o -z "$vg" ]; then
		usage
	fi
}

function check_if_argument_empty {
    local args="${@:-}"
    verbose "blue" "function check_if_argument_empty [args: $args]"

    if [ -n "$args" ]; then
        local arg
        for arg in "$args"; do
            if [ -z "$arg" ]; then
                cecho "red" "[ ! -n $arg ]\nEmpty argument detected by  \"check_if_argument_empty\" function. Please set the arguments for the preceeding function correctly and try again, exiting!"
                exit_error
            fi
        done
    else
        cecho "red" "[ ! -n $args ]\nNo arguments passed to  \"check_if_argument_empty\" function. Please set the arguments for the preceeding function correctly and try again, exiting!"
        exit_error
    fi
}

function check_number_of_arguments_passed {
    local function_name="${1:-}"
    local number_of_arguments_expected="${2:-}"
    local number_of_arguments_passed="${3:-}"

    check_if_argument_empty "$function_name" "$number_of_arguments_passed" "$number_of_arguments_expected"
    verbose "blue" "function check_number_of_arguments_passed [ function_name: $function_name, number_of_arguments_passed: $number_of_arguments_passed, number_of_arguments_expected: $number_of_arguments_expected]"
    
    if [ "$number_of_arguments_passed" != "$number_of_arguments_expected" ]; then
        cecho "red" "Number of arguments given[$number_of_arguments_passed] doesn't equal number_of_arguments_expected[$number_of_arguments_expected], please set the arguments for \"$function_name\" function properly and try again, exiting!"
        exit_error
    fi
}

function check_lvs {
    local lvs="${@:-}"
    verbose "blue" "function check_lvs [lvs: $lvs]"
#     check_if_argument_empty "$lvs"

    for lv in "$lvs"; do
        if [ "$(dirname $lv)" != "." -a "$(dirname $lv)" != "/" ]; then
            check_vgs "$(dirname $lv)"
        else
            cecho "red" "Logical Volume(LV) provided [$lv]doesn't seem to follow VG/LV format, please specify an LV correctly and try again, exiting!"
            exit_error
        fi

        cecho "-light_blue" "Checking LV [$lv]..."
        if $(lvs "$lv" 1>&3 2>&4); then
            cecho "green" "OK"
        else
            cecho "red" "LV [$lv] not found, exiting!"
            exit_error
        fi
    done
}

function check_user {
    verbose "blue" "function check_user"
    check_number_of_arguments_passed "check_user" "0" "$#"

    cecho "-light_blue" "Checking for root priviliges..."
    if [ $(whoami) != "root" ]; then
        cecho "red" "FAILED"
        cecho "yellow" "This script requires root privileges, exiting!"
        exit_error
    else
        cecho "green" "OK"
    fi
}

function check_vgs {
	local vgs="${@:-}"
	verbose "blue" "function check_vgs [vgs: $vgs]"
	check_if_argument_empty "$vgs"

	for vg in "$vgs"; do
		cecho "-light_blue" "Checking VG $vg..."
		if $(vgs "$vg" 1>&3 2>&4); then
			cecho "green" "OK"
		else
			cecho "red" "VG [$vg] not found, exiting!"
			exit_error
		fi
    done
}

function configure_terminal {
	verbose "blue" "function configure_terminal"
	cecho "-light_blue" "Configuring terminal..."
	check_number_of_arguments_passed "configure_terminal" "0" "$#"

	set -euf -o pipefail
	trap exit_trap EXIT

	if [ "$verbose" == "yes" ]; then
		exec 3<&1
		exec 4<&2
	elif [ "$verbose" == "no" ]; then
		exec 3>/dev/null
		exec 4>/dev/null
    fi
    
        cecho "green" "OK"
}

function check_for_backup {
	local dst_vg="$3"
	local lv="$2"
	local vg="$1"
	verbose "blue" "function check_for_backup [lv: $lv, vg: $vg]"

	check_lv "$vg/$lv"
	check_vgs "$dst_vg"

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
	verbose "blue" "function clean_up [resources_to_clean: ${resources_to_clean:-}]"
	cecho "-light_blue" "Cleaning up..."

	for resource in ${resources_to_clean:-}; do
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

function compare_lvs {
	local lv="${1:-}"
	local vg="${2:-}"
	verbose "blue" "function compare_lvs [lv:$lv, vg:$vg]"

	mount_lvs "$lv"
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

function exit_error {
    verbose "blue" "function error_exit"
    exit 0
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

function function_argument_error {
    local argument_name="${1:-}"
    local function_name="${2:-}"
    verbose "blue" "function function_argument_error [argument_name: $argument_name, function_name: $function_name]"
    check_number_of_arguments_passed "function_argument_error" "2" "$#"
    
    cecho "red" "Please set the $argument_name argument properly for the $function_name function and try again, exiting!"
    exit 1
}
    
function get_answer {
    read answer
    while [ "$answer" != "no" -a "$answer" != "yes" ]; do
        cecho "yellow" "Please choose the correct answer[no/yes]!"
        read answer
    done
}

function lvm_activate {
    local possible_vgs_or_lvs=${@:-}
    verbose "blue" "function lvm_activate [possible_vgs_or_lvs: $possible_vgs_or_lvs]"
    check_if_argument_empty "$possible_vgs_or_lvs"
    
    for possible_vg_or_lv in ${possible_vgs_or_lvs}; do
        if grep / <<< "$possible_vg_or_lv"; then
            check_lvs "$possible_vg_or_lv"
            lvchange -ay "$possible_vg_or_lv"
        else
            check_vgs "$possible_vg_or_lv"
            vgchange -ay "$possible_vg_or_lv"
        fi
    done
}

function lvm_deactivate {
    local possible_vgs_or_lvs=${@:-}
    verbose "blue" "function lvm_deactivate [possible_vgs_or_lvs: $possible_vgs_or_lvs]"
    check_if_argument_empty "$possible_vgs_or_lvs"
    
    for possible_vg_or_lv in ${possible_vgs_or_lvs}; do
        if grep / <<< "$possible_vg_or_lv"; then
            check_lvs "$possible_vg_or_lv"
            lvchange -an "$possible_vg_or_lv"
        else
            check_vgs "$possible_vg_or_lv"
            vgchange -an "$possible_vg_or_lv"
        fi
    done
}

function create_dir {
	local dir="${1:-}"
	verbose "blue" "function create_dir [$dir]"

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
		mount_lvs "$vg/$backup"
	done
}

function mount_lvs {
	local lvs="${@:-}"
	verbose "blue" "function mount_lvs [LVs: $lvs]"

	for lv in $lvs; do
            local dir="/mnt/$(echo $lv | sed 's:/:-:')"
            cecho "-light_blue" "Mounting $lv at $dir..."
            create_dir "$dir"
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
        done
}

function rm_from_res {
	local resource=${1:-}
	verbose "blue" "function rm_from_res [resource: $resource, resources_to_clean: $resources_to_clean]"
	if [ -n "$resources_to_clean" ]; then
		if [ -n "resource" ]; then
			verbose "blue" "Removing $resource"
			resources_to_clean=${resources_to_clean#$resource }
		else
			echo "The given resource [$resource] is empty, exiting!"
			exit 1
		fi
	else
		verbose "blue" "Clean_up complete"
	fi
}

function run_command {
    if [ "$#" == "6" ]; then
        local command="${1:-}"
        local condition="${2:-}"
        local error_message="${3:-}"
        local message="${4:-}"
        local permissible="${5:-}"
        local resource="${6:-}"
    
        verbose "blue" "function run_command [command: $command, condition: $condition, error_message: $error_message, message: $message, permissible: $permissible, resource: $resource]"

        check_if_argument_empty "$command" "$permissible"

        if eval $condition 1>&3 2>&4; then
            if [ -z "$message" ]; then
                verbose "blue" "Executing command [$command]..."
            else
                verbose "blue" "$message..."
            fi
            if [ -z "$error_message" ]; then
                eval "$command"
                check_status "$command" "$resource"
            else
                eval "$command"
                check_status "$error_message" "$resource"
            fi
        else
            if [ "$permissible" == "fail_on_condition" ]; then
                cecho "red" "[ ! $condition ]\n Please set the \"condition\" argument for \"run-command\" function correctly and try again, exiting!"
                exit_error
            elif [ "$permissible" != "do_not_fail_on_condition" -a "$permissible" != "fail_on_condition" ]; then
                cecho "red" "[ $permissible != do_not_fail_on_condition -a $permissible != fail_on_condition ]\n Please set the \"condition\" argument for \"run-command\" function correctly and try again, exiting!"
                exit_error
            fi
        fi
    else
        cecho "red" "[ $# != 6 ]\nPlease set the arguments for \"run_command\" function properly and try again, exiting!"
    fi
}

function umount_lvs {
	local lvs="${@:-}"
	check_if_argument_empty "$lvs"
	verbose "blue" "function umount_lvs [LVs: $lvs]"

	for lv in $lvs; do
            local dir="/mnt/$(echo $lv | sed 's:/:-:')"
            cecho "-light_blue" "Unmounting $lv from $dir..."
            if (cryptsetup isLuks /dev/"$lv"); then
                umount /dev/mapper/"$(echo $lv | cut -f 2 -d /)"
                cryptsetup close /dev/mapper/"$(echo $lv | cut -f 2 -d /)"
            else
                if mountpoint "$dir"; then
                    umount "$dir"
                else
                    cecho "yellow" "Nothing mounted at $dir directory, skipping."
                fi
            fi
            if [ -d "$dir" ]; then
                rmdir $dir
            else
                cecho "yellow" "Directory $dir doesn't exist, skipping."
            fi
            cecho "green" "OK"
        done
}

function usage {
	verbose "blue" "function usage"
	check_number_of_arguments_passed "usage" "0" "$#"

	cecho "yellow" "Usage: \n
                        \t${0#./} [options] <action> <action_arguments> [options]\n
                        \n
                        actions: \n
                        \t activate <VG>[/LV] \n
                        \t deactivate <VG>[/LV] \n
                        \t mount <VG>/<LV> \n
                        \t oumount <VG>/<LV>\n
                        \n
                        options: \n
                        \t verbose"
    exit 0
}

# OK
function verbose {
	local color="${1:-}"
	local message="${2:-}"

	if [ -n "$color" ]; then
		if [ -n "$message" ]; then
			if [ "$verbose" == "yes" ]; then
                cecho "$color" "$message"
			elif [ "$verbose" != "no" -a "$verbose" != "yes" ]; then
				cecho "red" "Please set the global \"verbose\" variable properly [\"$verbose\" != no/yes] and try again, exiting!"
				exit 1
            fi
        else
            function_argument_error "message" "verbose"
        fi
	else
        function_argument_error "color" "verbose"
	fi
}

########################
# main
########################
verbose="no"
check_user
configure_terminal

if [ "$#" == "0" ]; then
    usage
else
    arguments=( "$@" )
fi

for ((argument_number=0;argument_number<${#arguments[@]};argument_number++)) do
    case ${arguments[$argument_number]} in
        activate)
            lvm_activate "${arguments[@]:(($argument_number + 1))}"
            break
            ;;
        compare)
            source="${arguments[(($argument_number + 1))]:-}"
            destination="${arguments[(($argument_number + 2))]:-}"
            if [ -n "$source" -a -n "$destination" ]; then
                lvm_activate "$source" "$destination"
                mount_lvs "$source" "$destination"
                rsync -a --info=name -n -O /mnt/$(echo "$source" | sed 's:/:-:g')/ /mnt/$(echo "$destination" | sed 's:/:-:g')/
                umount_lvs "$source" "$destination"
                lvm_deactivate "$source" "$destination"
            else
                usage
            fi
            break
            ;;
        sync)
            source="${arguments[(($argument_number + 1))]:-}"
            destination="${arguments[(($argument_number + 2))]:-}"
            if [ -n "$source" -a -n "$destination" ]; then
                lvm_activate "$source" "$destination"
                mount_lvs "$source" "$destination"
                rsync -a --info=name -O /mnt/$(echo "$source" | sed 's:/:-:g')/ /mnt/$(echo "$destination" | sed 's:/:-:g')/
                umount_lvs "$source" "$destination"
                lvm_deactivate "$source" "$destination"
            else
                usage
            fi
            break
            ;;
            deactivate)
            lvm_deactivate "${arguments[@]:(($argument_number + 1))}"
            break
            ;;
        mount)
            lvm_activate "${arguments[@]:(($argument_number + 1))}"
            mount_lvs "${arguments[@]:(($argument_number + 1))}"
            resources_to_clean=""
            break
            ;;
        umount)
            umount_lvs "${arguments[@]:(($argument_number + 1))}"
            lvm_deactivate "${arguments[@]:(($argument_number + 1))}"
            break
            ;;
        verbose)
            if [ "${#arguments[@]}" == "1" ]; then
                usage
            else
                verbose="yes"
            fi
            ;;
        *)
            usage
            ;;
    esac
done
exit 0

for src_lv in "$src_lvs"; do
	check_for_backup "$src_vg" "$src_lv" "$dst_vg"
	if [ -n "$backups" ]; then
		cecho "default" "Would you like to compare[no/yes]?"
		get_answer
		if [ "$answer" == "yes" ]; then
			compare_lvs "$src_vg/$src_lv" "$dst_vg"
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
