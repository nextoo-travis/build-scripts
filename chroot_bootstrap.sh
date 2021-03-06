#!/bin/bash

# Get directory containing scripts
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

source "${SCRIPT_DIR}/utils.sh"

if [[ -z "${TARGET_PROFILE}" ]]; then
	error "TARGET_PROFILE is undefined"
	exit 1
fi


echo -e "${RESET}${GREEN}${BOLD}Nextoo Chroot Bootstrap Script${RESET} ${BOLD}version <TAG ME>${RESET}"


status 'Updating environment...'
	env-update


status 'Sourcing profile...'
	source /etc/profile

if [[ -z "${PS1}" ]]; then
	status 'Not configuring prompt (not a terminal)'
else
	status 'Configuring prompt...'
	export PROMPT_COMMAND="export RETVAL=\${?}"
	export PS1="\[$(tput bold)\]\[$(tput setaf 6)\][Nextoo] \[$(tput setaf 1)\]\u@\h \[$(tput setaf 4)\]\w \[$(tput setaf 3)\]\${RETVAL} \[$(tput setaf 7)\][\j] \[$(tput setaf 4)\]\\$\[$(tput sgr0)\] "
fi


status 'Locating make.conf...'
	# Set default make.conf file location
	MAKE_CONF="/etc/portage/make.conf"
	# Make sure the make.conf location is set correctly
	if [[ ! -f "${MAKE_CONF}" ]]; then
		MAKE_CONF="/etc/make.conf"
		if [[ ! -f "${MAKE_CONF}" ]]; then
			# Is this even a gentoo install?
			error "Unable to locate your system's make.conf"
			exit 1
		fi
	fi


if ! egrep "^\s*MAKEOPTS=" "${MAKE_CONF}" >/dev/null; then
	ncpus="$(($(nproc) + $(nproc) / 2))"
	status "Configuring MAKEOPTS (-j${ncpus})..."
	echo "MAKEOPTS=\"-j${ncpus}\"" >> "${MAKE_CONF}"
else
	status "Skipped MAKEOPTS configuration (already defined in make.conf)"
fi


#if ! egrep "^\s*PORTAGE_BINHOST=" "${MAKE_CONF}" >/dev/null; then
#	status "Configuring PORTAGE_BINHOST..."
#	echo 'PORTAGE_BINHOST="http://packages.nextoo.org/nextoo-desktop/nextoo-kde/amd64"' >> "${MAKE_CONF}"
#fi


#if ! egrep "^\s*EMERGE_DEFAULT_OPTS=" "${MAKE_CONF}" >/dev/null; then
#	status "Configuring EMERGE_DEFAULT_OPTS..."
#	echo "EMERGE_DEFAULT_OPTS=\"--quiet --jobs=1\"" >> "${MAKE_CONF}"
#fi

# ONLY DO THIS ON A BUILD MACHINE, CLIENTS MUST STILL ACKNOWLEDGE AND ACCEPT LICENSES!
if ! egrep "^\s*ACCEPT_LICENSE=" "${MAKE_CONF}" >/dev/null; then
	status "Configuring ACCEPT_LICENSE"
	echo "ACCEPT_LICENSE=\"*\"" >> "${MAKE_CONF}"
fi


if [[ "${NEXTOO_BUILD}" == 'true' ]]; then
	if ! egrep '^\s*FEATURES=' "${MAKE_CONF}" | grep "buildpkg" >/dev/null; then
		status "Enabling portage 'buildpkg' feature..."
		echo 'FEATURES="${FEATURES} buildpkg"' >> "${MAKE_CONF}"
	else
		status "Skipping portage 'buildpkg' feature (already enabled)"
	fi
fi


status "Creating missing directories..."
	status ".../run/lock"
	run mkdir -p /run/lock


if grep "time zone must be set" /etc/localtime >/dev/null; then
	status "Updating timezone to 'America/Los_Angeles'..."
	cd /etc
	run rm localtime
	run ln -s ../usr/share/zoneinfo/America/Los_Angeles localtime
	cd - >/dev/null
else
	status "Not touching timezone"
fi


status "Merging 'layman'..."
	run emerge --noreplace --quiet app-portage/layman


status "Configuring layman..."
	dest="http://www.nextoo.org/layman/repositories.xml"
	if ! egrep 'http://www.nextoo.org/layman/repositories.xml$' /etc/layman/layman.cfg >/dev/null; then
		#run sed -i "${arg}" /etc/layman/layman.cfg
		run sed -i "/^\s*overlays\s*:/ a\\\\t${dest}" /etc/layman/layman.cfg
	fi


status "Syncing layman..."
	run layman --sync-all


if ! layman --list-local | egrep " * nextoo " >/dev/null; then
	status "Adding Nextoo overlay..."
	run layman --add nextoo
else
	status "Skipping add Nextoo overlay (already added)"
fi


# Temporary debug stuffs
status "Printing emerge info..."
	run emerge --info


status "Updating system make file..."
	if ! egrep '^\s*source /var/lib/layman/make.conf$' "${MAKE_CONF}" >/dev/null; then
		echo 'source /var/lib/layman/make.conf' >> "${MAKE_CONF}"
	fi


status "Setting profile to ${TARGET_PROFILE}..."
	# Might want to check to see if the profile is already set. Use eselect profile show...
	eselect profile set ${TARGET_PROFILE}

status "Environment setup complete"

# Temporary debug stuffs
status "Printing emerge info..."
	run emerge --info

status "Merging Nextoo kernel..."
	run emerge nextoo-kernel

status "Checking for profile-specific bootstrap.sh in /etc/portage/make.profile/..."
	if [[ -x /etc/portage/make.profile/bootstrap.sh ]]; then
		status "Executing profile-specific bootstrap.sh..."
		run /etc/portage/make.profile/bootstrap.sh
	else
		status "No profile-specific bootstrap.sh"
	fi

# Temporary debug stuffs
status "Printing emerge info..."
	run emerge --info

status "Emerging world..."
	emerge -DNu @world

status "Emerge complete!"

# Check some flag for pushing binaries to a depot

if [[ "${DEBUG}" != "true" ]]; then
	status "Exiting chroot..."
	exit
fi

cd "${HOME}"
set +e
