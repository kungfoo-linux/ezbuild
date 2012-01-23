#!/bin/bash
# Copyright 2010-2011, Asio Software Technologies
# Distributed under the terms of the GNU General Public License v2

PROGRESS=/var/run/dispatch-progress

# Outputs error message and aborts script execution
die() {
	eerror $1
	exit $2
}

# Sets progress of dispatch process
dispatchProgress() {
	export DISPATCH_STAGE=$1
	echo "DISPATCH_STAGE=$1" > ${PROGRESS}
}

# Load necessary files
. /etc/profile
source /etc/init.d/functions.sh

# Track progress of the dispatching process
[[ -e ${PROGRESS} ]] && source ${PROGRESS}
export DISPATCH_STAGE=${DISPATCH_STAGE:-0}

# Check if system is dispatched already or if process has been aborted
if [ ${DISPATCH_STAGE} -ge 3 ]; then
	ewarn "Your system has been dispatched already!"
	ewarn "It is not recommended to re-dispatch."
	ewarn "Press ENTER to continue or CTRL+C to abort..."
	read
	dispatchProgress 0
elif [ ${DISPATCH_STAGE} -gt 0 ]; then
	einfo "Resuming dispatch at stage #${DISPATCH_STAGE}..."
fi

# Display warning when user aborts or process gets killed
trap 'die "Process killed! This may lead into unexpected problems. Be warned!" 9' ABRT INT KILL QUIT TERM

# Check system requirements
einfo "The process of dispatching may take a while. Please be patient..."
einfo "Checking system requirements..."
[[ ! -e /dev/random ]] && die "The /dev directory seems to be not mounted!"
[[ ! -e /proc/mounts ]] && die "The /proc directory seems to be not mounted!"
ping -c 1 google.com &> /dev/null
[[ "$?" -ne "0" ]] && die "There seems to be no Internet connectivity!"

# Get necessary variables
einfo "Obtaining necessary variables..."
export ENV_EXPORTS="GENTOO_MIRRORS PORTDIR DISTDIR PKGDIR PORTAGE_TMPDIR
		CFLAGS CHOST CXXFLAGS MAKEOPTS ACCEPT_KEYWORDS PROXY HTTP_PROXY
		FTP_PROXY FEATURES STAGE1_USE"
eval $(python -c 'import portage, os, sys; sys.stdout.write("".join(["export %s=\"%s\"; [[ -z \"%s\" ]] || einfo %s=\\\"%s\\\";\n" % (k, portage.settings[k], portage.settings[k], k, portage.settings[k]) for k in os.getenv("ENV_EXPORTS").split()]))') &> /dev/null
unset ENV_EXPORTS

# Begin stage #0
if [ ${DISPATCH_STAGE} -eq 0 ]; then
	einfo "Backing up files..."
	mkdir -p /tmp/regen2-dispatch
	cp -ap ${PORTDIR}/sys-apps/portage /tmp/regen2-dispatch/
	dispatchProgress 1
fi

# Begin stage #1
if [ ${DISPATCH_STAGE} -eq 1 ]; then
	einfo "Generating manifests..."
	cd ${PORTDIR}/sys-apps/portage
	find * -maxdepth 0 -type f -name '*.ebuild' | while read FILE; do
		ebuild ${FILE} manifest &> /dev/null || die "Unable to generate manifest!" 1
	done
	einfo "Installing reGen2 portage..."
	cd ${PORTDIR}/scripts
	export CONFIG_PROTECT="-*"
	export EMERGE_DEFAULT_OPTS=""
	export FEATURES="${FEATURES} -collision-protect"
	emerge -1 --nodeps portage &> /dev/null || die "Unable to install sys-apps/portage!" 1
	dispatchProgress 2
fi

# Begin stage #2
if [ ${DISPATCH_STAGE} -eq 2 ]; then
	einfo "Testing new portage..."
	export FEATURES="${FEATURES} mini-manifest"
	rm -rf ${PORTDIR}/sys-apps/portage
	cp -ap /tmp/regen2-dispatch/portage ${PORTDIR}/sys-apps/
	emerge -1 --nodeps portage &> /dev/null || die "reGen2 portage seems to be broken!" 2
	einfo "Regenerating local cache..."
	rm -rf /var/cache/edb/mtimedb
	emerge --metadata &> /dev/null || die "Unable to regenerate metadata!" 2
	dispatchProgress 3
fi

# Begin stage #3
if [ ${DISPATCH_STAGE} -eq 3 ]; then
	einfo "Dispatching system..."
	emerge -1 --nodeps baselayout &> /dev/null || die "Unable to emerge baselayout!" 3
	emerge -1 --nodeps openrc &> /dev/null || die "Unable to emerge openrc!" 3
	dispatchProgress 4
fi

# Begin stage #4
if [ ${DISPATCH_STAGE} -eq 4 ]; then
	einfo "Cleaning up..."
	rm -rf /tmp/regen2-dispatch
	einfo "All done!"
	einfo "Enjoy reGen2!"
fi
