#!/bin/bash

SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

set -x

install_cf() {
  local __target_loc=${1}
  
#  if [[ -z $(which cf) ]]; then
    local __tmp=/tmp/cf$$.tgz
    wget -O ${__tmp} 'https://cli.run.pivotal.io/stable?release=linux64-binary&version=6.11.3&source=github-rel'
    tar -C ${__target_loc} -xzf ${__tmp}
    rm -f ${__tmp}
#  fi
}

install_active_deploy() {
  #if [[ -z $(cf list-plugin-repos | grep "bluemix-staging") ]]; then
  #  cf add-plugin-repo bluemix-staging http://plugins.stage1.ng.bluemix.net
  #fi
  cf uninstall-plugin active-deploy || true
  # cf install-plugin active-deploy -r bluemix-staging
  cf install-plugin ${SCRIPTDIR}/active-deploy-linux-amd64-01.18
}

which ice
ice version
ice info

which cf
cf --version
install_cf $(dirname $(which cf))
cf --version
cf target
cf plugins

cf list-plugin-repos
install_active_deploy
cf plugins

cf active-deploy-list

ice group list
ice ps
ice images

PREFIX=priya_homestead

# Identify any existing group
TRUNC_PREFIX=$(echo ${PREFIX} | cut -c 1-16)
read -a ORIGINAL <<< $(ice group list | grep -v 'Group Id' | grep " ${TRUNC_PREFIX}" | awk '{print $1}')
# This gave us a whole list of group ids

echo "Original groups: ${ORIGINAL[@]}"

# Determine which original groups has the desired route --> the current original
for orig in ${ORIGINAL}; do
  echo "Processing ${orig}
  group_id=$orig route=python ${SCRIPTDIR}/foo.py
  echo "Done processing ${orig}
done


# Delete $ORIGINAL groups
deleted=()
if [[ ${#ORIGINAL[@]} -gt ${CONCURRENT_VERSIONS} ]]; then
  for orig in "${ORIGINAL[@]:${CONCURRENT_VERSIONS}}"; do
    echo ice group rm ${orig}
    deleted+=(${orig})
  done
fi

# Ensure deleted groups are deleted (keep this?)
for orig in ${deleted}; do
  echo wait_group_rm ${orig}
done
