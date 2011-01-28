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


VERSION='0.0.3'

function usage () {
	echo "Use: $0 [fix|revert]"
	echo " $0 fix - This will set the permissions of all clients' files and dirs so they can correctly work with suexec"
	echo " $0 revert - This will revert clients' files and dirs permissions as they were before the fix option"
	exit 1
}

if [ $# -ne 1 ]; then
	usage
fi

mkdir -p /usr/local/1h/bin/
target_file='/usr/local/1h/bin/set_no_suexec_perms'

if [ "$1" == 'fix' ]; then
	# Fix .htaccess files 
	for htaccess in $(grep -iH 'ForceType application/x-httpd-php' /home/*/public_html/.htaccess | grep -v \# | cut -d : -f 1); do
		sed -i '/[Ff][Oo][Rr][Cc][Ee][Tt][Yy][Pp][Ee]/aAddHandler application/x-httpd-php .php .php5 .php4 .php3' "${htaccess}"
		echo "sed -i '/AddHandler application/D' ${htaccess}" >> $target_file
	done

	for htaccess in $(grep -iH 'suPHP_ConfigPath' /home/*/public_html/.htaccess | grep -v \# | cut -d : -f 1); do
		sed -i '/[Ss][Uu][Pp][Hh][Pp]_[Cc][Oo][Nn][Ff][Ii][Gg][Pp][Aa][Tt][Hh]/s/\(^.*$\)/# \1/' "${htaccess}"
		echo "sed -i '/[Ss][Uu][Pp][Hh][Pp]_[Cc][Oo][Nn][Ff][Ii][Gg][Pp][Aa][Tt][Hh]/s/#//g' $htaccess" >> $target_file
	done

    for htaccess in $(grep -iH '^Options' /home/*/public_html/.htaccess | grep -v \# | cut -d : -f 1); do
		sed -i "/^Options/s/$/ +ExecCGI/" "${htaccess}"
		echo "sed -i '/^Options/s/+ExecCGI//' $htaccess" >> $target_file
    done

	for i in `ls -A1 /var/cpanel/users | grep ^[a-zA-Z]`; do
		if [ ! -d /home/$i/public_html ]; then
			continue
		fi

		# Fix ownerships
		#find /home/$i/public_html ! -user $i -exec sh -c 'ls -al $0 | awk "{print \"chown\",\$3\":\"\$4, \"\\\"\"\$9\"\\\"\"}"' {} \; -exec chown $i: {} \; >> $target_file 2>&1;
		#find /home/$i/public_html ! -user $i -exec ls -al {} \; | while read perms node owner group size month date hour filename; do
		find /home/$i/ ! -user $i -printf "chown %u:%g \"%p\"\n" | while read cmd owner fullpath; do
			temp_path=$(echo $fullpath | sed 's/"//g')
			chown $i: "${temp_path}"
			#echo "temp path is '$temp_path'"
			echo "${cmd} ${owner} ${fullpath}" >> $target_file
		done
		# Fix permissions

		#find /home/$i/public_html \( -perm -000777 -o -perm -000770 -o -name .htaccess \) -print | while read result; do
		find /home/$i/public_html \( -perm -000777 -o -perm -000770 -o -name .htaccess \) -printf "\"%p\"\n" | while read fullresults; do
			result=$(echo "$fullresults" | sed 's/"//g')
			if [[ "$result" =~ ".htaccess" ]]; then
				flags=$(grep -Ei 'php_flag|php_value' "$result" | grep -v \#)
				if [ -z "$flags" ]; then
					continue
				fi
				sed -i '/\([pP][Hh][Pp]_[Ff][Ll][Aa][Gg]\|[Pp][Hh][Pp]_[Vv][Aa][Ll][Uu][Ee]\)/s/\(^.*$\)/# \1/i' $result
				php_ini="$(echo \"$result\" | sed 's/.htaccess//')php.ini"
				dir_ini=$(echo "$result" | sed 's/.htaccess//')
				user=$(ls -al "$result" | awk '{print $3}')
				echo $flags | awk '{print $2, $3}' | while read option value; do
					#echo "$result | $option = $value -> $php_ini"
					echo "$option = $value" >> ${php_ini}
				done
				chown "${user}":"${user}" "${php_ini}"
				find "${dir_ini}" -maxdepth 3 -type d -exec cp -a "${php_ini}" {} \;
				echo "sed -i '/\([pP][Hh][Pp]_[Ff][Ll][Aa][Gg]\|[Pp][Hh][Pp]_[Vv][Aa][Ll][Uu][Ee]\)/s/#//g' ${result}" >> $target_file
				echo "find '${dir_ini}' -maxdepth 3 -name php.ini -exec rm -f {} \;" >> $target_file
			else
				chmod 755 "${result}"
				echo "chmod 777 \"${result}\"" >> $target_file
			fi
		done
	done
	if [ -f $target_file ]; then
		chmod 700 $target_file
	fi
elif [ "$1" == 'revert' ]; then
	if [ -x $target_file ]; then
		$target_file
	else
		echo "$target_file missing or not executable. nothing to revert then."
		#exit 1
	fi
else
	usage
fi
