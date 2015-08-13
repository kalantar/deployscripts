#!/bin/bash

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#MK#set -x

install_cf() {
  local which_cf=$(which cf)
  if [[ -n ${which_cf} ]]; then __target_loc=$(dirname ${which_cf})
  else __target_loc="/usr/local/bin"; fi
  
  if [[ -z ${which_cf} || -z $(cf --version | grep "version 6\.11\.3") ]]; then
    local __tmp=/tmp/cf$$.tgz
    wget -O ${__tmp} 'https://cli.run.pivotal.io/stable?release=linux64-binary&version=6.11.3&source=github-rel'
    tar -C ${__target_loc} -xzf ${__tmp}
    rm -f ${__tmp}
  fi
}

install_active_deploy() {
  #if [[ -z $(cf list-plugin-repos | grep "bluemix-staging") ]]; then
  #  cf add-plugin-repo bluemix-staging http://plugins.stage1.ng.bluemix.net
  #fi
  cf uninstall-plugin active-deploy || true
  # cf install-plugin active-deploy -r bluemix-staging
  cf install-plugin ${SCRIPTDIR}/active-deploy-linux-amd64-01.18
}

phase_id () {
  local __phase="${1}"
  
  if [[ -z ${__phase} ]]; then
    echo "ERROR: Phase expected"
    return -1
  fi

  case "${__phase}" in
    Initial|initial|start|Start)
    __id=0
    ;;
    Rampup|rampup|RampUp|rampUp)
    __id=1
    ;;
    Test|test|trial|Trial)
    __id=2
    ;;
    Rampdown|rampdown|RampDown|rampDown)
    __id=3
    ;;
    Final|final|End|end)
    __id=4
    ;;
    *)
    >&2 echo "ERROR: Invalid phase $phase"
    return -1
  esac

  echo ${__id}
}

wait_for_update (){
    local WAITING_FOR=$1
    local WAITING_FOR_PHASE=$2
    local WAIT_FOR=$3
    
    if [[ -z ${WAITING_FOR} ]]; then
        >&2 echo "ERROR: Expected update identifier to be passed into wait_for"
        return 1
    fi
    [[ -z ${WAITING_FOR_PHASE} ]] && WAITING_FOR_PHASE="Final"
    WAITING_FOR_PHASE_ID=$(phase_id ${WAITING_FOR_PHASE})
    [[ -z ${WAIT_FOR} ]] && WAIT_FOR=600 
    
    start_time=$(date +%s)
    end_time=$(expr ${start_time} + ${WAIT_FOR})
    >&2 echo "wait from ${start_time} to ${end_time} for update to complete"
    counter=0
    while (( $(date +%s) < ${end_time} )); do
        let counter=counter+1
        status_phase=$(cf active-deploy-list | grep -v "^Id " | grep "^${WAITING_FOR}" | awk '{print $2" "$5}')
        if [[ -z ${status_phase} ]]; then
          >&2 echo "ERROR: Update ${WAITING_FOR} not in progress"
          return 2
        fi
        local STATUS=$(echo ${status_phase} | cut -d' ' -f1)
        local PHASE=$(echo ${status_phase} | cut -d' ' -f2)
        
        # Echo status only occassionally
        if (( ${counter} > 9 )); then
          >&2 echo "After $(expr $(date +%s) - ${start_time})s phase of ${WAITING_FOR} is ${PHASE} (${STATUS})"
          counter=0
        fi
        
        PHASE_ID=$(phase_id ${PHASE})
        
        if [[ "${STATUS}" == "COMPLETED" && "${WAITING_FOR_PHASE}" != "Initial" ]]; then return 0; fi
        
        if [[ "${STATUS}" == "FAILED" ]]; then return 5; fi
        
        if [[ "${STATUS}" == "ABORTING" && "${WAITING_FOR_PHASE}" != "Initial" ]]; then return 5; fi
          
        if [[ "${STATUS}" == "ABORTED" ]]; then
          if [[ "${WAITING_FOR_PHASE}" == "Initial" && "${PHASE}" == "Initial" ]]; then return 0
          else return 5; fi
        fi
        
        if [[ "${STATUS}" == "IN_PROGRESS" ]]; then
          if (( ${PHASE_ID} > ${WAITING_FOR_PHASE_ID} )); then return 0; fi 
        fi
        
        sleep 3
    done
    
    >&2 echo "ERROR: Failed to update group"
    return 3
}

function get_originals(){
  local __prefix=$(echo ${PREFIX} | cut -c 1-16)
  local __originals=${2}

  local originals

  if [[ "CCS" == "${BACKEND}" ]]; then
    read -a originals <<< $(ice group list | grep -v 'Group Id' | grep " ${__prefix}" | awk '{print $1}')
  elif [[ "APPS" == "${BACKEND}" ]]; then
    read -a originals <<< $(cf apps | grep -v "^Getting" | grep -v "^OK" | grep -v "^name" | grep ${_prefix} | awk '{print $1}')
  else
    >&2 echo "ERROR: Unknown backend ${BACKEND}; expected one of \"CCS\" or \"APPS\""
    return 3
  fi
  
  echo ${#originals[@]} original groups found: ${originals[@]}
  eval $__originals="'$originals'"
}

###################################################################################
###################################################################################

if [[ -z ${BACKEND} ]]; then
  echo "ERROR: Backend not specified"
  exit 1
fi

install_cf
install_active_deploy

get_originals $PREFIX ORIGINAL

#G_O## Identify original group(s)
#G_O#PREFIX=${CONTAINER_NAME}
#G_O#
#G_O#TRUNC_PREFIX=$(echo ${PREFIX} | cut -c 1-16)
#G_O#read -a ORIGINAL <<< $(ice group list | grep -v 'Group Id' | grep " ${TRUNC_PREFIX}" | awk '{print $1}')
#G_O## This gave us a whole list of group ids
#G_O#
#G_O#echo ${#ORIGINAL[@]} original groups found: ${ORIGINAL[@]}

# Determine which original groups has the desired route --> the current original
ROUTED=()
export route="${ROUTE_HOSTNAME}.${ROUTE_DOMAIN}" 
for original in ${ORIGINAL[@]}; do
  ROUTED=( ${ROUTED[@]} $(group_id=${original} python ${SCRIPTDIR}/foo.py) )
done
echo ${#ROUTED[@]} of original groups routed to ${route}: ${ROUTED[@]}

if (( 1 < ${#ROUTED[@]} )); then
  echo "WARNING: Selecting only oldest to reroute"
fi

if (( 0 < ${#ROUTED[@]} )); then
  original_grp_id=${ROUTED[$(expr ${#ROUTED[@]} - 1)]}
  original_grp=$(ice group inspect $original_grp_id | grep '"Name":' | awk '{print $2}' | sed 's/"//g' | sed 's/,//')
fi

#MK## Deploy new group
#MK#echo "Create successor group"
#MK#${SCRIPTDIR}/deploygroup.sh || true
successor_grp=${CONTAINER_NAME}_${BUILD_NUMBER}

echo "Original group: ${original_grp} (${original_grp_id})"
echo "Successor group: ${successor_grp}"

cf active-deploy-list --timeout 60s

# Do update if there is an original group
if [[ -n "${original_grp}" ]]; then
  echo "Beginning active-deploy update..."
  create_command="cf active-deploy-create ${original_grp} ${successor_grp} --quiet --label Explore_${BUILD_NUMBER} --timeout 60s"
  if [[ -n "${RAMPUP}" ]]; then create_command="${create_command} --rampup ${RAMPUP}s"; fi
  if [[ -n "${TEST}" ]]; then create_command="${create_command} --test ${TEST}s"; fi
  if [[ -n "${RAMPDOWN}" ]]; then create_command="${create_command} --rampdown ${RAMPDOWN}s"; fi
  echo "Executing update: ${create_command}"
  update=$(eval ${create_command})
  cf active-deploy-show $update --timeout 60s

  # Wait for completion
  wait_for_update $update rampdown 600 && rc=$? || rc=$?
  echo "wait result is $rc"
  # cf active-deploy-check-phase $update --phase rampdown --wait 600s --timeout 60s
  
  cf active-deploy-list
  
  if (( $rc )); then
    echo "ERROR: update failed"
    echo cf-active-deploy-rollback $update
    wait_for_update $update initial 300 && rc=$? || rc=$?
    cf active-deploy-delete $update
    exit 1
  fi

  # Cleanup
  cf active-deploy-delete $update
fi


#MK## Delete $ORIGINAL groups
#MK#deleted=()
#MK#versions_to_key=$(expr ${CONCURRENT_VERSIONS} - 1)
#MK#if [[ ${#ORIGINAL[@]} -gt ${versions_to_keep} ]]; then
#MK#  for orig in "${ORIGINAL[@]:${versions_to_keep}}"; do
#MK#    ice group rm ${orig}
#MK#    deleted=( deleted[@] ${orig} )
#MK#  done
#MK#fi
#MK#
#MK## Ensure deleted groups are deleted (keep this?)
#MK#for orig in ${deleted[@]}; do
#MK#  wait_group_rm ${orig}
#MK#done
