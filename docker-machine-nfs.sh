#!/bin/bash
#
# The MIT License (MIT)
# Copyright © 2015 Toni Van de Voorde <toni.vdv@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

set -o errexit

# BEGIN _functions

# @info:    Prints the ascii logo
asciiLogo ()
{
  echo
  echo
  echo '                       ##         .'
  echo '                 ## ## ##        ==               _   _ _____ ____'
  echo '              ## ## ## ## ##    ===              | \ | |  ___/ ___|'
  echo '          /"""""""""""""""""\___/ ===            |  \| | |_  \___ \'
  echo '     ~~~ {~~ ~~~~ ~~~ ~~~~ ~~~ ~ /  ===- ~~~     | |\  |  _|  ___) |'
  echo '          \______ o           __/                |_| \_|_|   |____/'
  echo '            \    \         __/'
  echo '             \____\_______/'
  echo
  echo
}

# @info:    Prints the usage
usage ()
{

  asciiLogo

  cat <<EOF
Usage: $0 <machine-name> [options]

Options:

  -f, --force               Force reconfiguration of nfs
  -n, --nfs-config          NFS configuration to use in /etc/exports. (default to '-alldirs -mapall=\$(id -u):\$(id -g)')
  -s, --shared-folder,...   Folder to share (default to /Users)
  -m, --mount-opts          NFS mount options (default to 'noacl,async,nfsvers=3')
  -i, --use-ip-range        Changes the nfs export ip to a range (e.g. -network 192.168.99.100 becomes -network 192.168.99)
  -p, --ip                  Configures the docker-machine to connect to your host machine via a specific ip address
  -t, --timeout             Configures how long the timeout should be for docker-machine commands

Examples:

  $ docker-machine-nfs test

    > Configure the /Users folder with NFS

  $ docker-machine-nfs test --shared-folder=/Users --shared-folder=/var/www

    > Configures the /Users and /var/www folder with NFS

  $ docker-machine-nfs test --shared-folder=/var/www --nfs-config="-alldirs -maproot=0"

    > Configure the /var/www folder with NFS and the options '-alldirs -maproot=0'

  $ docker-machine-nfs test --mount-opts="noacl,async,nolock,nfsvers=3,udp,noatime,actimeo=1"

    > Configure the /User folder with NFS and specific mount options.

  $ docker-machine-nfs test --ip 192.168.1.12

    > docker-machine will connect to your host machine via this address
EOF
  exit 0
}

# @info:    Prints error messages
# @args:    error-message
echoError ()
{
  printf "\033[0;31mFAIL\n\n$1 \033[0m\n"
}

# @info:    Prints warning messages
# @args:    warning-message
echoWarn ()
{
  printf "\033[0;33m$1 \033[0m\n"
}

# @info:    Prints success messages
# @args:    success-message
echoSuccess ()
{
  printf "\033[0;32m$1 \033[0m\n"
}

# @info:    Prints check messages
# @args:    success-message
echoInfo ()
{
  printf "\033[1;34m[INFO] \033[0m$1"
}

# @info:    Prints property messages
# @args:    property-message
echoProperties ()
{
  printf "\t\033[0;35m- $1 \033[0m\n"
}

# @info:    Checks if a given property is set
# @return:  true, if variable is not set; else false
isPropertyNotSet()
{
  if [ -z ${1+x} ]; then return 0; else return 1; fi
}

# @info:    Sets the default properties
setPropDefaults()
{
  prop_machine_name=
  prop_shared_folders=()
  prop_nfs_config="-alldirs -mapall="$(id -u):$(id -g)
  prop_mount_options="noacl,async,nfsvers=3"
  prop_force_configuration_nfs=false
  prop_use_ip_range=false
  prop_timeout=
}

# @info:    Resolve APFS firmlinks to their actual location
resolveHostPath()
{
  firmlinked_dir="/System/Volumes/Data$1"
  if [ -d "$firmlinked_dir" ] ; then
    echo $firmlinked_dir
  else
    echo $1
  fi
}

# @info:    Parses and validates the CLI arguments
parseCli()
{

  [ "$#" -ge 1 ] || usage

  prop_machine_name=$1

  for i in "${@:2}"
  do
    case $i in
      -s=*|--shared-folder=*)
      local shared_folder="${i#*=}"
      shift

      if [ ! -d "$shared_folder" ]; then
        echoError "Given shared folder '$shared_folder' does not exist!"
        exit 1
      fi

      prop_shared_folders+=("$shared_folder")
      ;;

      -n=*|--nfs-config=*)
        prop_nfs_config="${i#*=}"
      ;;

      -m=*|--mount-opts=*)
        prop_mount_options="${i#*=}"
      ;;

      -f|--force)
      prop_force_configuration_nfs=true
      ;;

      -i|--use-ip-range)
      prop_use_ip_range=true
      ;;

      -p=*|--ip=*)
      prop_use_ip="${i#*=}"
      ;;

      -t=*|--timeout=*)
      prop_timeout="-t ${i#*=}"
      ;;

      *)
        echoError "Unknown argument '$i' given"
        echo #EMPTY
        usage
      ;;
    esac
  done

  if [ "$(isWsl)" = "true" ]; then
    local default_shared_foder="/c/Users"
  else
    local default_shared_foder="/Users"
  fi

  if [ ${#prop_shared_folders[@]} -eq 0 ]; then
    prop_shared_folders+=("${default_shared_foder}")
  fi;

  echoInfo "Configuration:"

  echo #EMPTY
  echo #EMPTY

  echoProperties "Machine Name: $prop_machine_name"
  for shared_folder in "${prop_shared_folders[@]}"
  do
    echoProperties "Shared Folder: $shared_folder"
  done

  echoProperties "Mount Options: $prop_mount_options"
  echoProperties "Force: $prop_force_configuration_nfs"

  echo #EMPTY

}

# @info:    Checks if the machine is present
# @args:    machine-name
# @return:  (none)
checkMachinePresence ()
{
  echoInfo "machine presence ... \t\t\t"

  machine_name=$(docker-machine ls $2 --filter "Name=^$1$" -q)

  if [ "" = "${machine_name}" ]; then
    echoError "Could not find the machine '$1'!"; exit 1;
  fi

  echoSuccess "OK"
}

# @info:    Checks if the machine is running
# @args:    machine-name
# @return:  (none)
checkMachineRunning ()
{
  echoInfo "machine running ... \t\t\t"

  machine_state=$(docker-machine ls $2 --filter "Name=^$1$" --format "{{.State}}")

  if [ "Running" != "${machine_state}" ]; then
    echoError "The machine '$1' is not running but '${machine_state}'!";
    exit 1;
  fi

  echoSuccess "OK"
}

# @info:    Returns the driver used to create the machine
# @args:    machine-name
# @return:  The driver used to create the machine
getMachineDriver ()
{
  docker-machine ls $2 --filter "Name=^$1$" --format "{{.DriverName}}"
}

# @info:    Loads mandatory properties from the docker machine
lookupMandatoryProperties ()
{
  echoInfo "Lookup mandatory properties ... \t\t"

  prop_machine_ip=$(docker-machine ip $1)

  prop_machine_driver=$(getMachineDriver $1 "$2")

  if [ "$prop_machine_driver" = "vmwarefusion" ] || [ "$prop_machine_driver" = "vmware" ]; then
    prop_network_id="Shared"
    prop_nfshost_ip=${prop_use_ip:-"$(ifconfig -m `route get $prop_machine_ip | awk '{if ($1 ~ /interface:/){print $2}}'` | awk 'sub(/inet /,""){print $1}')"}
    if [ "" = "${prop_nfshost_ip}" ]; then
      echoError "Could not find the vmware fusion net IP!"; exit 1
    fi
    local nfsd_line="nfs.server.mount.require_resv_port = 0"
    echoSuccess "\t\tOK"

    echoInfo "Check NFS config settings ... \n"
    if [ "$(cat /etc/nfs.conf | grep -c "$nfsd_line")" == "1" ]; then
      echoInfo "/etc/nfs.conf is setup correctly!"
    else
      echoWarn "\n !!! Sudo will be necessary for editing /etc/nfs.conf !!!"
      # Backup /etc/nfs.conf file
      sudo cp /etc/nfs.conf /etc/nfs.conf.bak && \
      echo "nfs.server.mount.require_resv_port = 0" | \
        sudo tee /etc/nfs.conf > /dev/null
      echoWarn "\n !!! Backed up /etc/nfs.conf to /nfs.conf.bak !!!"
      echoWarn "\n !!! Added 'nfs.server.mount.require_resv_port = 0' to /etc/nfs.conf !!!"
    fi
    echoSuccess "\n\t\t\t\t\t\tOK"
    return
  fi

  if [[ "$prop_machine_driver" =~ (xhyve|hyperkit|vmwarevsphere) ]]; then
    prop_network_id="Shared"
    prop_nfshost_ip=${prop_use_ip:-"$(ifconfig -m `route get $prop_machine_ip | awk '{if ($1 ~ /interface:/){print $2}}'` | awk 'sub(/inet /,""){print $1}')"}
    if [ "" = "${prop_nfshost_ip}" ]; then
      echoError "Could not find a route to the ${prop_machine_driver} docker-machine"; exit 1
    fi
    echoSuccess "OK"
    return
  fi

  if [ "$prop_machine_driver" = "parallels" ]; then
    prop_network_id="Shared"
    prop_nfshost_ip=${prop_use_ip:-"$(prlsrvctl net info \
      ${prop_network_id} | grep 'IPv4 address' | sed 's/.*: //')"}

    if [ "" = "${prop_nfshost_ip}" ]; then
      echoError "Could not find the parallels net IP!"; exit 1
    fi

    echoSuccess "OK"
    return
  fi

  if [ "$prop_machine_driver" != "virtualbox" ]; then
    echoError "Unsupported docker-machine driver: $prop_machine_driver"; exit 1
  fi

  prop_network_id=$(VBoxManage showvminfo $1 --machinereadable |
    grep hostonlyadapter | cut -d'"' -f2)
  if [ "" = "${prop_network_id}" ]; then
    echoError "Could not find the virtualbox net name!"; exit 1
  fi

  prop_nfshost_ip=$(VBoxManage list hostonlyifs | tr -d '\r' |
    grep "${prop_network_id}$" -A 3 | grep IPAddress |
    cut -d ':' -f2 | xargs);
  if [ "" = "${prop_nfshost_ip}" ]; then
    echoError "Could not find the virtualbox net IP!"; exit 1
  fi

  echoSuccess "OK"
}

# @info:    Configures the NFS
configureNFSUnix()
{
  echoInfo "Configure NFS ... \n"

  if isPropertyNotSet $prop_machine_ip; then
    echoError "'prop_machine_ip' not set!"; exit 1;
  fi

  echoWarn "\n !!! Sudo will be necessary for editing /etc/exports !!!"

  #-- Update the /etc/exports file and restart nfsd

  local exports_begin="# docker-machine-nfs-begin $prop_machine_name #"
  local exports_end="# docker-machine-nfs-end $prop_machine_name #"

  # Remove old docker-machine-nfs exports
  local exports=$(cat /etc/exports | \
    tr "\n" "\r" | \
    sed "s/${exports_begin}.*${exports_end}//" | \
    tr "\r" "\n"
  )

  # Write new exports blocks beginning
  exports="${exports}\n${exports_begin}\n"

  local machine_ip=$prop_machine_ip
  if [ "$prop_use_ip_range" = true ]; then
    machine_ip="-network ${machine_ip%.*}"
  fi

  for shared_folder in "${prop_shared_folders[@]}"
  do
    # Add new exports
    exports="${exports}\"$(resolveHostPath "$shared_folder")\" $machine_ip $prop_nfs_config\n"
  done

  # Write new exports block ending
  exports="${exports}${exports_end}"
  #Export to file
  printf "$exports" | sudo tee /etc/exports >/dev/null

  sudo nfsd stop && sudo nfsd start; sleep 2 && sudo nfsd checkexports

  echoSuccess "\t\t\t\t\t\tOK"
}

configureNFSWsl()
{
  echoInfo "Configure NFS ... \n"

  local nfsdPath=$(sc.exe qc nfsserver | grep BINARY_PATH_NAME | awk '{split($0,a," : "); print a[2]}' | awk '{sub("nfsd.exe","",$0);}1' | awk '{sub("\\","/",$0);}1')
  local wslnfsdPath=$(wslpath -a "$nfsdPath" | tr -d '\r')
  wslnfsdPath+="exports"

  if [ ! -f "$wslnfsdPath" ]; then
    echoError "Configuration file was not found in $wslnfsdPath, please check installation of haneWin server"
    exit 1
  fi

  for shared_folder in "${prop_shared_folders[@]}"
  do
    local wsl_shared_folder=$(wslpath -w $shared_folder)
    echo "$wsl_shared_folder -alldirs -exec -mapall:1000,1000 #Added by docker-machine-nfs" >> "$wslnfsdPath"
  done

  echoProperties "$(net.exe stop nfsserver)"
  echoProperties "$(net.exe start nfsserver)"

  echoInfo "NFS server ... \t\t\t\t"
  echoSuccess "OK"
}

# @info:    Configures the VirtualBox Docker Machine to mount nfs
configureBoot2Docker()
{
  echoInfo "Configure Docker Machine ... \t\t"

  if isPropertyNotSet $prop_machine_name; then
    echoError "'prop_machine_name' not set!"; exit 1;
  fi
  if isPropertyNotSet $prop_nfshost_ip; then
    echoError "'prop_nfshost_ip' not set!"; exit 1;
  fi

  # render bootlocal.sh and copy bootlocal.sh over to Docker Machine
  # (this will override an existing /var/lib/boot2docker/bootlocal.sh)

  local bootlocalsh="#!/bin/sh"

  if [ "$(isWsl)" = "true" ]; then
    bootlocalsh="${bootlocalsh}
    sudo umount /c/Users"
  else
    bootlocalsh="${bootlocalsh}
    sudo umount /Users"
  fi

  for shared_folder in "${prop_shared_folders[@]}"
  do
    bootlocalsh="${bootlocalsh}
    sudo mkdir -p \""$shared_folder"\""
  done

  bootlocalsh="${bootlocalsh}
    sudo /usr/local/etc/init.d/nfs-client start"

  for shared_folder in "${prop_shared_folders[@]}"
  do
    bootlocalsh="${bootlocalsh}
    sudo mount -t nfs -o "$prop_mount_options" "$prop_nfshost_ip":\""$(resolveHostPath "$shared_folder")"\" \""$shared_folder"\""
  done

  local file="/var/lib/boot2docker/bootlocal.sh"

  docker-machine ssh $prop_machine_name \
    "echo '$bootlocalsh' | sudo tee $file && sudo chmod +x $file && sync" < /dev/null > /dev/null
  
  sleep 2

  echoSuccess "OK"
}

# @info:    Restarts Docker Machine
restartDockerMachine()
{
  echoInfo "Restart Docker Machine ... \t\t"

  if isPropertyNotSet $prop_machine_name; then
    echoError "'prop_machine_name' not set!"; exit 1;
  fi

  docker-machine restart $prop_machine_name > /dev/null

  echoSuccess "OK"
}

# @return:  'true', if NFS is mounted; else 'false'
isNFSMounted()
{
  for shared_folder in "${prop_shared_folders[@]}"
  do
    local nfs_mount=$(docker-machine ssh $prop_machine_name "sudo mount" < /dev/null | 
      grep "$prop_nfshost_ip:$(resolveHostPath "$shared_folder") on")
    if [ "" = "$nfs_mount" ]; then
      echo "false";
      return;
    fi
  done

  echo "true"
}

# @info:    Verifies that NFS is successfully mounted
verifyNFSMount()
{
  echoInfo "Verify NFS mount ... \t\t\t"

  local attempts=10

  while [ ! $attempts -eq 0 ]; do
    sleep 1
    [ "$(isNFSMounted)" = "true" ] && break
    attempts=$(($attempts-1))
  done

  if [ $attempts -eq 0 ]; then
    echoError "Cannot detect the NFS mount :("; exit 1
  fi

  echoSuccess "OK"
}

# @info:    Displays the finish message
showFinish()
{
  printf "\033[0;36m"
  echo "--------------------------------------------"
  echo
  echo " The docker-machine '$prop_machine_name'"
  echo " is now mounted with NFS!"
  echo
  echo " ENJOY high speed mounts :D"
  echo
  echo "--------------------------------------------"
  printf "\033[0m"
}

# WSL

# @return:  'true', if platform is WSL; else 'false'
isWsl()
{
  if [ "$(uname -r | grep 'Microsoft')" != "" ]; then
    echo "true"
  else
    echo "false"
  fi
}

if [ "$(isWsl)" = "true" ]; then
  printf "\033[0;32mPlaform WSl detected\033[0m\n"

# @info:    translate docker-machine to .exe
  function docker-machine()
  {
    docker-machine.exe "$@"
  }
  export -f docker-machine
fi

# END _functions

setPropDefaults

parseCli "$@"

checkMachinePresence $prop_machine_name "$prop_timeout"
checkMachineRunning $prop_machine_name "$prop_timeout"

lookupMandatoryProperties $prop_machine_name "$prop_timeout"

if [ "$(isNFSMounted)" = "true" ] && [ "$prop_force_configuration_nfs" = "false" ]; then
    echoSuccess "\n NFS already mounted." ; showFinish ; exit 0
fi

echo #EMPTY LINE

echoProperties "Machine IP: $prop_machine_ip"
echoProperties "Network ID: $prop_network_id"
echoProperties "NFSHost IP: $prop_nfshost_ip"

echo #EMPTY LINE

if [ "$(isWsl)" = "true" ]; then
  configureNFSWsl
else
  configureNFSUnix
fi

configureBoot2Docker
restartDockerMachine

verifyNFSMount

showFinish
