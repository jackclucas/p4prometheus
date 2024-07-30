#!/bin/bash
# install_swarm_metrics.sh
# Installs the swarm_metrics.sh script and sets up a cron job to run it

# This script requires Bash version >= 4
if [[ -z "${BASH_VERSINFO}" ]] || [[ -z "${BASH_VERSINFO[0]}" ]] || [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "This script requires Bash version >= 4";
    exit 1;
fi

# ============================================================
# Configuration section

# Default metrics directory
metrics_root=/var/metrics

# Default config file path
config_file=/opt/perforce/swarm/data/config.php

# ============================================================

function msg () { echo -e "$*"; }
function bail () { msg "\nError: ${1:-Unknown Error}\n"; exit "${2:-1}"; }

function usage
{
   declare errorMessage=${2:-Unset}
 
   if [[ "$errorMessage" != Unset ]]; then
      echo -e "\\n\\nUsage Error:\\n\\n$errorMessage\\n\\n" >&2
   fi
 
   echo "USAGE for install_swarm_metrics.sh:

install_swarm_metrics.sh [-m <metrics_root>] [-c <config_file>] [-osuser <osuser>] 

    <metrics_root>  is the directory where metrics will be written - default: $metrics_root
    <config_file>   is the Swarm PHP config file - default: $config_file
    <osuser>        Operating system user, e.g. perforce, under which to install crontab

Examples:

sudo ./install_swarm_metrics.sh
sudo ./install_swarm_metrics.sh -m /custom/metrics -c /custom/config.php -osuser perforce

"
}

# Command Line Processing
 
declare -i shiftArgs=0
declare OsUser=""

set +u
while [[ $# -gt 0 ]]; do
    case $1 in
        (-h) usage -h  && exit 1;;
        (-m) metrics_root=$2; shiftArgs=1;;
        (-c) config_file=$2; shiftArgs=1;;
        (-osuser) OsUser="$2"; shiftArgs=1;;
        (-*) usage -h "Unknown command line option ($1)." && exit 1;;
    esac
 
    # Shift (modify $#) the appropriate number of times.
    shift; while [[ "$shiftArgs" -gt 0 ]]; do
        [[ $# -eq 0 ]] && usage -h "Incorrect number of arguments."
        shiftArgs=$shiftArgs-1
        shift
    done
done
set -u

if [[ $(id -u) -ne 0 ]]; then
   echo "$0 can only be run as root or via sudo"
   exit 1
fi

# Validate required binaries
wget=$(which wget)
[[ $? -eq 0 ]] || bail "Failed to find wget in path"

# Install the swarm_metrics.sh script
install_swarm_metrics () {
    script_url="https://github.com/jackclucas/p4prometheus/raw/master/scripts/swarm_metrics.sh"
    script_path="/etc/metrics/swarm_metrics.sh"

    msg "\nDownloading and installing swarm_metrics.sh from $script_url\n"
    wget -O "$script_path" "$script_url"
    if [[ ! -s "$script_path" ]]; then
        bail "Failed to download swarm_metrics.sh or the file is empty"
    fi
    chmod +x "$script_path"
    [[ -n "$OsUser" ]] && chown "$OsUser" "$script_path"
}

# Install the cron job
install_cron_job () {
    mytab="/tmp/mycron"
    script_path="/etc/metrics/swarm_metrics.sh"
    cron_entry="*/5 * * * * $script_path -c $config_file > /dev/null 2>&1 ||:"

    if [[ -n "$OsUser" ]]; then
        sudo -u "$OsUser" crontab -l > "$mytab" 2>/dev/null || true
        if ! grep -q "$script_path" "$mytab" ;then
            echo "$cron_entry" >> "$mytab"
        fi
        sudo -u "$OsUser" crontab "$mytab"
    else
        crontab -l > "$mytab" 2>/dev/null || true
        if ! grep -q "$script_path" "$mytab" ;then
            echo "$cron_entry" >> "$mytab"
        fi
        crontab "$mytab"
    fi

    # List things out for review
    msg "\nCrontab after updating - showing swarm_metrics entries:\n"
    if [[ -n "$OsUser" ]]; then
        sudo -u "$OsUser" crontab -l | grep "$script_path"
    else
        crontab -l | grep "$script_path"
    fi
}

install_swarm_metrics
install_cron_job

msg "\nInstallation complete. Check crontab -l output above (as user ${OsUser:-root}) to ensure the entry is present.\n"

