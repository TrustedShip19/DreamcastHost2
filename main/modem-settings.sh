#!/bin/bash
# Detect connected modem and establish settings to allow
# for a client to dial in and receive internet from host
# computer.
#
# Usage:
# modem-settings.sh $Override $Modem $DCuser
#
# Where:
# $Override	= The override file
# $Modem	= Modem device to use
# $DCuser	= User account to connect to
#
# Author: Gregory Hoople
#
# Date Created: 2014-8-6
# Date Modified: 2015-6-12
#
# References:
# www.dreamcast-scene.com/guides/pc-dc-server-guide-win7
# www.ryochan7.com/blog/2009/06/23/pc-dc-server-guide-part-0-introduction
#
# na2's comments on:
# www.dreamcast-talk.com/forum/viewtopic.php?f=3&t=1160&start=40
#
# Corona688's comments on:
# www.unix.com/linux/153781-how-do-i-capture-responses-chat-command.html
#
# IP Check Information/Examples:
# www.unix.com/shell-programing-and-scripting/36005-regular-expression-mac-address-validation.html


####################
# Helper Functions #
####################

# Fuction to check that an IP address is valid.
checkIP() {
    local ip="$1"
    local IFS=.
    local a b c d

    read -r a b c d <<< "$ip"

    [[ -n "$d" ]] || return 1

    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done

    return 0
}

# Use nslookup to check the IP address of the entered domain
lookupDomain() {
	toCheck=$*

	# Look up the IP address of the domain
	# Send '2' to /dev/null to prevent an arrow being
	# printed out every time this function is called
	searchIP=$(nslookup $toCheck 2>/dev/null)

	# Strip the information to just the IP address
	echo "$searchIP" | grep -A 1 "$toCheck" | grep -m 1 "Address" |
		awk '{print $2}'
}

#########################
# Set default variables #
#########################

# Override File
Override="Override.txt"

# Modem device to connect to
MODEM="/dev/ttyACM0"

# User to log in as
DCuser="dream"

# Debug:
# echo "Modem Settings - Recieved: $1 | $2 | $3"

##########################################
# Check if arguments have been passed in #
##########################################

# Check for first argument (Override)
if [[ ! -z $1 ]]; then
	Override=$1
fi

# Check for second argument (Modem)
if [[ ! -z $2 ]]; then
	MODEM=$2
fi

# Check for third argument (User Name)
if [[ ! -z $3 ]]; then
	DCuser=$3
fi

# Directory for PPP settings files
pppDirectory="/etc/ppp"

# Dreamcast User's Password
DCpass="dreamcast"

# Check for an 'Override' of 'Login' for Password
overPass=$(grep "Login" "$Override" | grep -v \# | awk '{print $3}')

if [[ ! -z $overPass ]]; then
	DCpass=$overPass
fi

# Current Date and Time
DATE=$(date +"%Y-%m-%d  %I:%M %p %Z")

# Set Communication Speed
SPEED=115200

# Check if the user has stated they don't want to
# get the apache web server.
overWeb=$(grep "Webserver Off" $Override | grep -v \#)

###############################################
# Set up the configuration file for the modem #
###############################################

# Get local IP Address
myLANip=$(ip route get 1 |
          awk '{print $7; exit}')

if [[ -z $myLANip ]]; then
	echo "Error: No Internet Detected."
	exit 1
else
	echo "Local IP:         $myLANip"
fi

# Grab everything from the IP address up to the last period.
# If the IP address is "192.168.1.13",
# the ipGroup becomes  "192.168.1"
ipGroup=${myLANip%.*}
echo "Find open IP:     $ipGroup.*"
ipCheck="127.0.0.1"
ipDreamcast=""

# Here we handle figuring out the IP address that
# the Dreamcast will use. Either one is specified
# in the Override file, or the script scans for
# an open address in the same group as the
# host computer.

# Check Overrride file for "Dreamcast IP"
overDCIP=$(grep "Dreamcast IP" $Override | grep -v \# |
	awk '{print $3}')

# No Override Specified for Dreamcast IP Address
if [[ -z $overDCIP ]]; then

	# IP addresses to scan through
	# Scan ten higher than my current IP.
	HOST_LOW=$(echo $myLANip | cut -d "." -f 4)
	HOST_LOW=$(($HOST_LOW + 5))
	HOST_HIGH=250

	# Scan for an unused IP address.
	for ((i=$HOST_LOW;i<$HOST_HIGH;i++)); do
		ipCheck=$ipGroup.$i
		if [[ $ipCheck == $myLANip ]]; then
			continue
		fi
		echo -n "Checking:         $ipCheck... "
		checkAddress=$(ping -c 1 $ipCheck)
		if [[ $checkAddress == *"0 received"* ]]; then
			echo "open!"
			ipDreamcast=$ipCheck
			break
		elif [[ -z $checkAddress ]]; then
			echo "Error: No Network Detected."
			break
		else
			echo "in use."
		fi
	done

else
	echo "Override for Dreamcast IP Found: $overDCIP"
	ipDreamcast=$overDCIP
fi

if [[ -z $ipDreamcast ]]; then
	echo "Error: Could not find an open IP Address for the Dreamcast."
	exit 1
else
	echo "Dreamcast IP:     $ipDreamcast"
fi

cidr=$(ip -4 addr show "$(/usr/sbin/ip route get 1 | awk '{print $5;exit}')" |
	awk '/inet / {print $2}' | cut -d/ -f 2)
	
	case "$cidr" in
	    8)  netmask="255.0.0" ;;
	    16) netmask="255.255.0.0" ;;
	    24) netmask="255.255.255.0" ;;
	    *)  echo "Unsupported CIDR /$cidr"; exit 1 ;;
	esac

if [[ -z $netmask ]]; then
	echo "Error: Could not find internet netmask."
	exit 1
else
	echo "Netmask:          $netmask"
fi

########################
# Determine DNS server for PPP  #
########################

# Check Override file for specified DNS server
overDNS=$(grep "^Set DNS" "$Override" | grep -v '^#' | awk '{print $3}')

dnsServer=""

if [[ -n "$overDNS" ]]; then

    # If the override isn't already an IP, try resolving it.
    if ! checkIP "$overDNS"; then
        overDNS=$(lookupDomain "$overDNS")
    fi

    if checkIP "$overDNS"; then
        dnsServer="$overDNS"
        echo "DNS Override:     $dnsServer"
    else
        echo "Invalid DNS override."
        exit 1
    fi

elif [[ -z "$overWeb" ]]; then

    # dnsmasq is running locally
    dnsServer="$myLANip"
    echo "DNS Server:       Local dnsmasq ($dnsServer)"

else

    # Try systemd-resolved first
    if command -v resolvectl >/dev/null 2>&1; then
        dnsServer=$(resolvectl dns | awk '/DNS Servers:/ {print $3; exit}')
    fi

    # Fall back to resolv.conf
    if [[ -z "$dnsServer" ]]; then
        dnsServer=$(awk '/^nameserver/ && $2 != "127.0.0.53" {print $2; exit}' /etc/resolv.conf)
    fi

    if [[ -z "$dnsServer" ]]; then
        echo "Could not determine system DNS."
        exit 1
    fi

    echo "DNS Server:       $dnsServer"

fi


# Check Overrride file for "Raspberry Pi"
overPi=$(grep "Raspberry Pi" $Override | grep -v \#)

# In the case that the system is running on a Raspberry Pi
# using wifi, a setting needs to change so that starting up
# ppp will not turn off the wifi connection. Without this,
# the dreamcast will be able to connect to local addresses
# but will not be able to load external websites or games.
#
# This suggestion was found at:
# http://www.raspberrypi.org/forums/viewtopic.php?f=29&t=39409
# Further information
# http://www.raspberrypi.org/forums/viewtopic.php?f=91&t=19430
if [[ -z $overPi ]]; then

	wiDir="/etc/ifplugd/action.d/"
	wiFile="action_wpa"

	# If the file exists and hasn't been changed yet
	if [ -f "$wiDir$wiFile" ]; then
		echo "Making sure Raspberry Pi handles wifi"

		# Add a single period before the filename
		# so that the script to kill the wifi will
		# not get run.
		mv $wiDir$wiFile $wiDir.$wiFile
	fi
fi

echo "===== Saving Settings Files ====="

##############################
# /etc/ppp/options.ModemName #
# Save Modem Options File    #
##############################
modemFile="$pppDirectory/options.$MODEM"
echo "Writing:  $modemFile"
echo "$myLANip:$ipDreamcast" > $modemFile
echo "netmask $netmask" >> $modemFile

#############################
# /etc/ppp/options          #
# Save General Options File #
#############################
optFile="$pppDirectory/options"
echo "Writing:  $optFile"
echo "#" > $optFile
echo -e "# $optFile" >> $optFile
echo "#" >> $optFile
echo "# Author(s): Gregory Hoople" >> $optFile
echo "#" >> $optFile
echo "# Created:   2014-6-20" >> $optFile
echo "# Modified:  2014-8-5" >> $optFile
echo -e "# Generated: $DATE" >> $optFile
echo "#" >> $optFile
echo "# This is the automatically generated" >> $optFile
echo "# settings file for PPP." >> $optFile
echo "#" >> $optFile
echo "# These settings are based on the following guides:" >> $optFile
echo "# www.dreamcast-scene.com/guides/pc-dc-server-guide-win7" >> $optFile
echo "# www.ryochan7.com/blog/2009/06/23/pc-dc-server-guide-part-0-introduction" >> $optFile
echo -e >> $optFile
echo "lock" >> $optFile
echo "noauth" >> $optFile
echo "refuse-pap" >> $optFile
echo "refuse-eap" >> $optFile
echo "refuse-chap" >> $optFile
echo "refuse-mschap" >> $optFile
echo "nobsdcomp" >> $optFile
echo "nodeflate" >> $optFile
echo "proxyarp" >> $optFile
echo -e >> $optFile
echo "# DNS Server Address" >> $optFile
echo "# If we have dnsmasq, this is the local IP address" >> $optFile
echo "ms-dns $dnsServer" >> $optFile

########################
# /etc/ppp/pap-secrets #
# pap-secrets setup    #
########################
papFile="$pppDirectory/pap-secrets"
echo -n "Checking: $papFile for dialup login... "
papSecrets=$( grep $DCuser $papFile | grep -v \# )
papLogin="$DCuser	*	$DCpass	*"


if [[ -z $papSecrets ]]; then
	echo "$papLogin" >> "$papFile"
	echo "Added"
else
	grep -v "^${DCuser}[[:space:]]" "$papFile" > "${papFile}.tmp"
	echo "$papLogin" >> "${papFile}.tmp"
	mv "${papFile}.tmp" "$papFile"
	echo "Updated"
fi

############################################
# /etc/ppp/peers/$DCuser                   #
# user settings                            #
############################################
# The "name" field needs to be the account
# trying to be connected to. But the
# filename can be any name. Just needs to
# be called with "pon FILENAME". For
# simplicity the filename is the username.
peerFile="$pppDirectory/peers/$DCuser"
echo "Writing:  $peerFile"
echo "$MODEM" > $peerFile
echo "$SPEED" >> $peerFile
echo "name \"$DCuser\"" >> $peerFile
echo "lock" >> $peerFile
echo "usepeerdns" >> $peerFile
echo "noauth" >> $peerFile

echo "novj" >> $peerFile
echo "noccp" >> $peerFile
echo "noipv6" >> $peerFile

# Set up the computer to have an account
# for the dreamcast to log into
echo -n "Checking: System account '$DCuser'... "
if getent passwd $DCuser > /dev/null 2>&1; then
	# User exists
	echo "OK"
	# Make sure password is correct
	echo "$DCuser:$DCpass" | chpasswd
else
	# User does not exist
	echo "NONE"
	echo "Creating: System account for '$DCuser'"
	useradd -G dialout,dip,users -c "Dreamcast user" -d /home/$DCuser -g users -s /usr/sbin/pppd $DCuser
	# Set up account's password
	echo "$DCuser:$DCpass" | chpasswd
fi


# If we're running the web server
# set up host information
if [[ -z $overWeb ]]; then

	echo "===== Configure Web Server ======"

	# Make sure the apache2 config file exists.
	# If not we make a default one to avoid
	# a couple harmless warnings.
	apacheDefault="/etc/httpd/conf/httpd.conf"
	hasServerName=$( grep "ServerName" $apacheDefault | grep -v \# )
	if [[ -z $hasServerName ]]; then
		echo "Writing:  $apacheDefault"
		echo -e >> $apacheDefault
		echo -e >> $apacheDefault
		echo "# Define ServerName to eliminate" >> $apacheDefault
		echo "# a couple apache2 warnings." >> $apacheDefault
		echo "ServerName localhost" >> $apacheDefault
fi

echo "Checking: For Updated Websites"

# Run the script to check if any website files exist in
# the specific directory and update the apache directories
exec sudo ./load-websites.sh &

# Wait for the website update to finish executing
wait $!

#############################
# Build WVDial config #
#############################
	wvdialFile="/etc/wvdial.conf"

	echo "Writing: $wvdialFile"

	cat >"$wvdialFile" <<EOF
	[Dialer Defaults]
Init1 = ATZ
Init2 = ATQ0 V1 E1 S0=0 &C1 &D2 +FCLASS=0
Modem Type = USB Modem
; Phone = <Target Phone Number>
ISDN = 0
; Password = <Your Password>
; Username = <Your Login Name>
Modem = $MODEM
Baud = 460800
EOF


# Set up dnsmasq file for Apache Server
#############################
# Build dnsmasq config #
#############################
	dnsmasqFile="/etc/dnsmasq.d/dreamcasthost.conf"

	echo "Writing: $dnsmasqFile"

	cat >"$dnsmasqFile" <<EOF
#DreamcastHost
#Automatically Generated.
EOF
#######################################
# Determine default Domain Destination #
#######################################

directTo="$myLANip"

overHost=$(grep "^Host" "$Override" | grep -v '^#' | awk '{print $2}')

if [[ -n "$overHost" ]]; then
	echo "Host override found: $overHost"
	directTo="$overHost"
fi

#######################
# Redirect #
#######################

echo
echo "Processing Redirect Overrides..."

grep '^Redirect:' "$Override" | grep -v '^#' | while read -r _ host target
do

	host="${host,,}"
	host="${host%.}"

	# Is this target a Group?
	group=$(awk -v g="$target" '$1=="Group:" && $2==g {print $3}' "$Override")

	[[ -n "$group" ]] && target="$group"

	# IP?
	if checkIP "$target"; then

		printf "address=/%s/%s\n" \
			"$host" \
			"$target" >>"$dnsmasqFile"

		echo "HOST $host -> $target"
	else
	fi
done

###################################
# IP Redirect Overrides (nftables) #
###################################

echo
echo "Processing IP Redirect Overrides..."

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Delete old table
nft delete table ip dreamcast 2>/dev/null

# Create nft table
nft list table ip dreamcast >/dev/null 2>&1 || {
    
    nft add table ip dreamcast

    nft 'add chain ip dreamcast prerouting {
        type nat hook prerouting priority dstnat;
        policy accept;
    }'
}


grep '^IPRedirect:' "$Override" | grep -v '^#' |
while read -r _ proto interface source target
do

    #
    # Format:
    #
    # IPRedirect: both eth1 192.168.1.1:* 192.168.1.19:*
    #

    if [[ "$proto" != "tcp" &&
          "$proto" != "udp" &&
          "$proto" != "both" ]]; then

        echo "Invalid protocol: $proto"
        continue

    fi


#################################
# Parse source #
#################################

    if [[ "$source" == *:* ]]; then

        srcIP="${source%%:*}"
        srcPort="${source##*:}"

    else

        srcIP="$source"
        srcPort="*"

    fi


#################################
# Parse destination #
#################################

    if [[ "$target" == *:* ]]; then

        dstIP="${target%%:*}"
        dstPort="${target##*:}"

    else

        dstIP="$target"
        dstPort=""

    fi


#################################
# DNAT target #
#################################

    if [[ "$dstPort" == "*" || -z "$dstPort" ]]; then
        dnatTarget="$dstIP"
    else
        dnatTarget="${dstIP}:${dstPort}"
    fi


    echo "$proto interface:$interface $srcIP:$srcPort -> $dnatTarget"



    #################################
    # Generate port rule #
    #################################

    make_port_rule()
    {
        local protocol=$1
        local port=$2


        if [[ "$port" == "*" ]]; then
            echo "$protocol"
            return
        fi


        if [[ "$port" == *-* ]]; then
            echo "$protocol dport {$port}"
        else
            echo "$protocol dport $port"
        fi
    }



#################################
# TCP #
#################################

if [[ "$proto" == "tcp" ||
      "$proto" == "both" ]]; then

    if [[ "$srcPort" == "*" ]]; then

        nft add rule ip dreamcast prerouting \
            iifname "$interface" \
            ip daddr "$srcIP" \
            meta l4proto tcp \
            dnat to "$dnatTarget"

    else

        nft add rule ip dreamcast prerouting \
            iifname "$interface" \
            ip daddr "$srcIP" \
            tcp dport "$srcPort" \
            dnat to "$dnatTarget"

    fi

fi



#################################
# UDP #
#################################

if [[ "$proto" == "udp" ||
      "$proto" == "both" ]]; then

    if [[ "$srcPort" == "*" ]]; then

        nft add rule ip dreamcast prerouting \
            iifname "$interface" \
            ip daddr "$srcIP" \
            meta l4proto udp \
            dnat to "$dnatTarget"

    else

        nft add rule ip dreamcast prerouting \
            iifname "$interface" \
            ip daddr "$srcIP" \
            udp dport "$srcPort" \
            dnat to "$dnatTarget"

    fi

fi
done

#################
# Domain
#################

echo
echo "Processing Domain Overrides..."

grep '^Domain:' "$Override" | grep -v '^#' | awk '{print $2}' |
while read -r domain
do

	domain="${domain,,}"
	domain="${domain%.}"

	printf "address=/%s/%s\n" \
		"$domain" \
		"$directTo" >>"$dnsmasqFile"

	echo "DOMAIN $domain -> $directTo"

done

echo
echo "Generated dnsmasq config:"
echo "------------------------"
cat "$dnsmasqFile"
echo "------------------------"

echo "Restarting: apache"
sudo service apache2 restart > /dev/null 2>&1

echo "Restarting: dnsmasq"
if command -v systemctl >/dev/null; 2>&1; then
	    sudo systemctl restart dnsmasq
else
	sudo service dnsmasq restart
fi

wait

fi

echo "Updating Settings - Complete"

