#!/bin/bash
# 1H - Convert non-suexec sites to suexec           Copyright(c) 2010 1H Ltd
#                                                        All rights Reserved
# copyright@1h.com                                             http://1h.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


VERSION='1.0.1'

function usage () {
	echo "Use: $0 [fix|revert] [username|all]"
	echo " $0 fix - This will set the permissions of all clients' files and dirs so they can correctly work with suexec"
	echo " $0 revert - This will revert clients' files and dirs permissions as they were before the fix option"
	echo " $0 username - Apply the fix|revert actions only to a specific username's home directory"
	echo " $0 all - Apply the fix|revert actions to all home directories on this server"
	exit 1
}

if [ $# -ne 2 ]; then
	usage
fi
if [ "$1" != "fix" ] && [ "$1" != "revert" ]; then
	usage
fi

if [ "$2" != "all" ]; then
	if [ ! -d /home/$2 ]; then
		print "Home dir for username $2 (/home/$2) does not exists."
		exit 1
	fi
fi

action="$1"
user="$2"
changes_storage='converted.by.1h'

function revert_changes {
	if [ ! -x /home/$1/$changes_storage ]; then
		return 0
	fi
	# Execute /home/$1/changes_storage
	/home/$1/$changes_storage
	return 1
}

function do_changes {
	do_user="$1"
	target_file="/home/$do_user/$changes_storage"

	# Find all .htaccess files in this client's directory and start working on them
	for htaccess in $(find /home/$do_user/ -name .htaccess); do
		# Find all lines with ForceType application.* and append addhandler beneath them
		if ( grep -v \# ${htaccess} | grep -i 'ForceType application/x-httpd-php' >> /dev/null 2>&1 ); then
			sed -i '/[Ff][Oo][Rr][Cc][Ee][Tt][Yy][Pp][Ee]/aAddHandler application/x-httpd-php .php .php5 .php4 .php3' "${htaccess}"
			echo "sed -i '/AddHandler application/D' ${htaccess}" >> $target_file
		fi
		# Comment out all lines with suPHP_ConfigPath
		if ( grep -v \# ${htaccess} | grep -i 'suPHP_ConfigPath' >> /dev/null 2>&1 ); then
			sed -i '/[Ss][Uu][Pp][Hh][Pp]_[Cc][Oo][Nn][Ff][Ii][Gg][Pp][Aa][Tt][Hh]/s/\(^.*$\)/# \1/' "${htaccess}"
			echo "sed -i '/[Ss][Uu][Pp][Hh][Pp]_[Cc][Oo][Nn][Ff][Ii][Gg][Pp][Aa][Tt][Hh]/s/#//g' $htaccess" >> $target_file
		fi
		# Append '+ExecCGI' to all lines which contains Options 
		if ( grep -i 'Options' ${htaccess} >> /dev/null 2>&1 ) && ( ! grep ExecCGI ${htaccess} >> /dev/null 2>&1 ); then
			sed -i "/Options/s/$/ +ExecCGI/" "${htaccess}"
			echo "sed -i '/Options/s/ +ExecCGI//' $htaccess" >> $target_file
		fi
		
		if ( grep -v \# ${htaccess} | grep -Ei 'php_flag|php_value' >> /dev/null 2>&1 ); then
			php_ini_values=$(grep -Ei 'php_flag|php_value' ${htaccess} | awk '{print $2, "=" ,$3}')
			# Comment out all php_flags and php_values in this .htaccess
			sed -i '/\([pP][Hh][Pp]_[Ff][Ll][Aa][Gg]\|[Pp][Hh][Pp]_[Vv][Aa][Ll][Uu][Ee]\)/s/\(^.*$\)/# \1/i' ${htaccess}
			# Generate full path to a php.ini file from the .htaccess
			php_ini=$(echo $htaccess | sed 's/.htaccess/php.ini/')
			# Strip the .htaccess from the the find results so we can generate the dir where it is located
			dir_ini=$(echo $htaccess | sed 's/.htaccess//')
			echo "$php_ini_values" >> ${php_ini}
			chown "${do_user}":"${do_user}" "${php_ini}"
			# In the directory were we found the .htaccess with the php_flags find all dirs in maxdepth 3 
			# and copy the newly created php.ini files in them
			find "${dir_ini}" -maxdepth 3 -type d -exec cp -a "${php_ini}" {} \; >> /dev/null 2>&1
			# Finally write down the revert process to the $target_file
			echo "sed -i '/\([pP][Hh][Pp]_[Ff][Ll][Aa][Gg]\|[Pp][Hh][Pp]_[Vv][Aa][Ll][Uu][Ee]\)/s/#//g' ${result}" >> $target_file
			echo "find '${dir_ini}' -maxdepth 3 -name php.ini -exec rm -f {} \;" >> $target_file
		fi
	done

	if [ ! -d /home/$do_user/public_html ]; then
		# this client does not have a public_html dir so we will just go ahead and return from the function
		return 0
	fi

	# Change the ownership of all files and dirs which are not owned by $do_user to $do_user
	find /home/$do_user/public_html ! -user $do_user -printf "chown %u:%g \"%p\"\n" | while read cmd owner fullpath; do
		temp_path=$(echo $fullpath | sed 's/"//g')
		chown $i: "${temp_path}"
		echo "${cmd} ${owner} ${fullpath}" >> $target_file
	done

	# Find all files/dirs writable by group and others
	find /home/$do_user/public_html \( -perm -000777 -o -perm -000770 \) -printf "%p\n" | while read path; do
		# Remove this writable bit for group/others from the file/dir
		chmod go-w "${path}"
		# Write down the revert process
		echo "chmod 777 \"${path}\"" >> $target_file
	done
}

case "$action" in
	"fix")
		if [ "$user" == 'all' ]; then
			for user in $(ls -A1 /home); do
				if [ ! -d /home/$user ] || ( ! grep "$user:x:" /etc/passwd >> /dev/null 2>&1 ); then
					continue
				fi
				do_changes $user
			done
		else
			do_changes $user
		fi
	;;
	"revert")
		if [ "$user" == 'all' ]; then
			for user in $(ls -A1 /home); do
				if [ ! -d /home/$user ] || ( ! grep "$user:x:" /etc/passwd >> /dev/null 2>&1 ); then
					continue
				fi
				revert_changes $user
			done
		else
			revert_changes $user
		fi
	;;
	*)
		usage
esac
