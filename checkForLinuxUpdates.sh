#!/bin/bash

set -o errtrace

export TERM=linux
declare results="${PWD}/results.txt"
declare status=./status.groovy

declare nodeName=${1:-$(hostname -s)}
shift

function onexit()
{
    echo
    echo
    [ -e "$results" ] || return 0
    echo 'show what was done'
    cat "$results"
    mv "$results" "$nodeName.txt"
}
trap onexit ERR
trap onexit INT
trap onexit PIPE

function latestUpdates()
{
    echo
    echo
    echo 'get latest updates'
    sudo /usr/bin/apt-get update -y &>> "$results"
    sudo /usr/bin/apt-get dist-upgrade -y &>> "$results"
}

function main()
{
    :> "$results"
    :> "$status"

    removeLocks
    showWhatNeedsDone
    latestUpdates
    report
    showLinuxVersions
    removeOldLinux
}

function removeLocks()
{
    echo
    echo 'removeLocks'
    local pid="$(ps -efwH | grep '/usr/bin/apt-get' | grep -v 'grep' | awk '{print $2}')"
    if [ "${pid:-}" ]; then
        # kill any old 'apt-get' and remove locks
        kill "$pid"
        echo 'WARNING: removing old locks'
        rm /var/lib/apt/lists/lock
        rm /var/cache/apt/archives/lock
        rm /var/lib/dpkg/lock*
        updateStatus "addErrorBadge('${nodeName}: removed locks')"
     fi
}

function removeOldLinux()
{
    local installs=$(dpkg --get-selections | grep -e 'linux.*-4' | grep -v "$(uname -r | sed s/-generic//)" | awk '{ print  $1 }' | tr '\n' ' ')
    if [ "$installs" ]; then
        sudo /usr/bin/apt-get remove -y $installs
        sudo /usr/bin/apt-get purge -y $installs
        sudo /usr/bin/apt-get autoremove -y
        sudo /usr/bin/apt autoremove -y

        showLinuxVersions
    fi
}

function report()
{
    echo
    echo
    echo 'report if we need to reboot and/or run fsck'
    local -a checks=('/var/lib/update-notifier/fsck-at-reboot' '/var/run/reboot-required')
    for fl in "${checks[@]}" ; do
        echo "checking $fl"
        [ -s "$fl" ] || continue
        cat "$fl"
        fl="$(basename "$fl")"
        updateStatus "addWarningBadge('${nodeName}: ${fl//-/ }')"
    done
}

function showLinuxVersions()
{
    echo
    echo
    echo 'report our linux installations'
    dpkg --get-selections | grep 'linux.*-4'
}

function showWhatNeedsDone()
{
    local text

    echo
    echo 'show what needs done'

    text=$(/usr/lib/update-notifier/apt-check --human-readable) || :
    echo "$text"
    text=$(grep 'packages can be updated.' <<< "$text" ||:)
    [ -z "$text" ] || [ $(awk '{print $1}' <<< "$text") -eq 0 ] || updateStatus "addBadge('completed.gif','${nodeName}: ${text}')"

    text=$(/usr/lib/ubuntu-release-upgrader/check-new-release --check-dist-upgrade-only) || :
    echo "$text"
    local txt=$(grep 'New release' <<< "$text" ||:)
    [ -z "$txt" ] || updateStatus "addBadge('yellow.gif','${nodeName}: ${txt}')"
}

function updateStatus()
{
    local text=${1:?}

    [ -s "$status" ] || echo "manager.$1" >> $status
}


main "$@"
