#!/bin/bash
#
# Script to check that the necessary software is installed,
# if not it will attempt to install it.
#

###################################
# Override file
###################################

Override="Override.txt"

[[ -n "$1" ]] && Override="$1"

###################################
# Detect package manager
###################################

if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"

elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"

elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"

elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"

elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"

else
    echo "Unsupported Linux distribution."
    exit 1
fi

###################################
# Package translation
###################################

packageName() {

    case "$PKG_MANAGER:$1" in

        apt:apache)
            echo apache2
            ;;

        dnf:apache|yum:apache)
            echo httpd
            ;;

        pacman:apache)
            echo apache
            ;;

        zypper:apache)
            echo apache2
            ;;

        apt:apache-php)
            echo libapache2-mod-php
            ;;

        dnf:apache-php|yum:apache-php)
            echo php
            ;;

        pacman:apache-php)
            echo php-apache
            ;;

        zypper:apache-php)
            echo apache2-mod_php8
            ;;

        *)
            echo "$1"
            ;;
    esac
}

###################################
# Check package
###################################

needPackage() {

    local pkg
    pkg=$(packageName "$1")

    case "$PKG_MANAGER" in

        apt)
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
                grep -q "install ok installed"
            ;;

        dnf|yum)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;

        pacman)
            pacman -Q "$pkg" >/dev/null 2>&1
            ;;

        zypper)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        echo "Need to install $pkg"
        return 1
    fi

    return 0
}

###################################
# Install package
###################################

installPackage() {

    local pkg
    pkg=$(packageName "$1")

    echo "Installing $pkg..."

    case "$PKG_MANAGER" in

        apt)
            sudo apt-get -y install "$pkg"
            ;;

        dnf)
            sudo dnf install -y "$pkg"
            ;;

        yum)
            sudo yum install -y "$pkg"
            ;;

        pacman)
            sudo pacman --noconfirm -S "$pkg"
            ;;

        zypper)
            sudo zypper --non-interactive install "$pkg"
            ;;
    esac
}

###################################
# Check required software
###################################

checkInstalled() {

    needPackage ppp
    needPPP=$?

    needPackage wvdial
    needWVDial=$?

    overWeb=$(grep "Webserver Off" "$Override" | grep -v '#')

    if [[ -z "$overWeb" ]]; then

        needPackage apache
        needApache=$?

        needPackage dnsmasq
        needDNS=$?

        needPackage php-common
        needPHP=$?

        needPackage apache-php
        needAP=$?

        needPackage php-cli
        needPHPcli=$?

        needPackage php-gd
        needGD=$?

    else

        needApache=0
        needDNS=0
        needPHP=0
        needAP=0
        needPHPcli=0
        needGD=0

    fi

    if [[ $needPPP == 1 ]] ||
       [[ $needWVDial == 1 ]] ||
       [[ $needApache == 1 ]] ||
       [[ $needDNS == 1 ]] ||
       [[ $needPHP == 1 ]] ||
       [[ $needAP == 1 ]] ||
       [[ $needPHPcli == 1 ]] ||
       [[ $needGD == 1 ]]; then
        return 0
    fi

    return 1
}

###################################
# Main
###################################

checkInstalled
hasAllPrograms=$?

if [[ $hasAllPrograms == 0 ]]; then

    echo "Preparing to install missing software..."

    [[ $needPPP == 1 ]] && installPackage ppp
    [[ $needWVDial == 1 ]] && installPackage wvdial
    [[ $needApache == 1 ]] && installPackage apache
    [[ $needDNS == 1 ]] && installPackage dnsmasq
    [[ $needPHP == 1 ]] && installPackage php-common
    [[ $needAP == 1 ]] && installPackage apache-php
    [[ $needPHPcli == 1 ]] && installPackage php-cli
    [[ $needGD == 1 ]] && installPackage php-gd

    checkInstalled
    hasAllPrograms=$?

    if [[ $hasAllPrograms == 0 ]]; then
        echo
        echo "Error: Missing necessary software."
        exit 1
    fi
fi

exit 0
#!/bin/bash
# Script to check that the necessary software is installed,
# if not it will attempt to get it.
#
# Usage:
# check-software.sh $Override
# Where:
# $Override	= The override file
#
# Author: Gregory Hoople
#
# Date Created: 2015-6-11
# Date Modified: 2016-3-31

# Set default variables
# Override File
Override="Override.txt"

# Debug:
# echo "Check Software - Recieved: $1"

# Check if arguments have been passed in
# Check for first argument (Override)
if [[ ! -z $1 ]]; then
	Override=$1
fi

# Check if a single package is installed
# $* - Name of the package to look for.
needPackage() {
	toCheck=$*

	# Run dpkg-query on specified package.
 	installedOK=$(dpkg-query -W -f='${Status}' $toCheck)

	if [[ ! $installedOK == *"install ok"* ]]; then
		echo "Need to install $toCheck"
		return 1
	fi

	return 0
}

# Check the necessary packages are installed:
checkInstalled() {

	# Check ppp is installed (for the server)
	needPackage "ppp"
	needPPP=$?

	# Check wvdial is installed (for modem scanning)
	needPackage "wvdial"
	needWVDial=$?

	# Check if the user has stated they don't want to
	# get the apache web server.
	overWeb=$(grep "Webserver Off" $Override | grep -v \#)

	# If they don't state "Webserver Off" we download
	# apache and dnsmasq, otherwise we skip them.
	if [[ -z $overWeb ]]; then
		# Check apache2 is installed (for webserver hosting)
		needPackage "apache2"
		needApache=$?

		# Check dnsmasq is installed (for webserver hosting)
		needPackage "dnsmasq"
		needDNS=$?

		# Check php5-common is installed (for webserver hosting)
		needPackage "php5-common"
		needPHP=$?

		# Check lib-apache2-mod-php5 is installed (for webserver hosting)
		needPackage "libapache2-mod-php5"
		needAP=$?

		# Check php5-cli is installed (for webserver hosting)
		needPackage "php5-cli"
		needPHPcli=$?

		# Check php5-gd is installed (for images on the webserver)
		needPackage "php5-gd"
		needGD=$?
	else
		needApache=0
		needDNS=0
		needPHP=0
		needAP=0
		needPHPcli=0
		needGD=0
	fi

	# If one of the software is not installed
	# we update repositories
	if  [[ 1 == $needPPP ]] || [[ 1 == $needWVDial ]] ||
		[[ 1 == $needPHP ]] || [[ 1 == $needApache ]] ||
		[[ 1 == $needAP  ]] || [[ 1 == $needPHPcli ]] ||
		[[ 1 == $needGD  ]] || [[ 1 == $needDNS    ]]; then
		return 0
	fi
	return 1
}

# Run the function to check for necessary software
checkInstalled

# Set the return to a variable
hasAllPrograms=$?

if [[ 0 == $hasAllPrograms ]]; then
	echo "Preparing to Download Software"
	echo "Updating Repositories"
	sudo apt-get update

	# Install ppp if it's not already
	if [[ 1 == $needPPP ]]; then
		echo "Installing PPP"
		sudo apt-get -y install ppp
	fi

	# Install wvdial if it's not already
	if [[ 1 == $needWVDial ]]; then
		echo "Installing WVDial"
		sudo apt-get -y install wvdial
	fi

	# Install apache2 if it's not already
	if [[ 1 == $needApache ]]; then
		echo "Installing Apache"
		sudo apt-get -y install apache2
	fi

	# Install php5-common if it's not already
	if [[ 1 == $needPHP ]]; then
		echo "Installing PHP5"
		sudo apt-get -y install php5-common
	fi

	# Install php5-common if it's not already
	if [[ $needAP ]]; then
		echo "Installing Apache PHP Library"
		sudo apt-get -y install libapache2-mod-php5
	fi

	# Install php5-common if it's not already
	if [[ 1 == $needPHPcli ]]; then
		echo "Installing PHP5-cli"
		sudo apt-get -y install php5-cli
	fi

	# Install php5-common if it's not already
	if [[ 1 == $needGD ]]; then
		echo "Installing PHP5-GD (For Images)"
		sudo apt-get -y install php5-gd
	fi

	# Install dnsmasq if it's not already
	if [[ 1 == $needDNS ]]; then
		echo "Installing dnsmasq"
		sudo apt-get -y install dnsmasq
	fi


	# Check that after the installing
	# the software is now all there.
	checkInstalled

	# Set the return to a variable
	hasAllPrograms=$?

	# We are missing necessary software,
	# so we quit with an error.
	if [[ 0 == $hasAllPrograms ]]; then
		echo "Error: Missing necessary software."
		exit 1
	fi
fi

exit 0
