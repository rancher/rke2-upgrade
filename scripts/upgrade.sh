#!/bin/sh -xe

info()
{
    echo '[INFO] ' "$@"
}

fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

get_rke2_process_info() {
  rke2_PID=$(ps -ef | grep -E "rke2 .*(server|agent)" | grep -E -v "(init|grep|channelserver)" | head -1 | awk '{print $1}')
  if [ -z "$rke2_PID" ]; then
    fatal "rke2 is not running on this server"
  fi
  info "rke2 binary is running with pid $rke2_PID"
  rke2_BIN_PATH=$(cat /host/proc/${rke2_PID}/cmdline | awk '{print $1}' | head -n 1)
  if [ "$rke2_PID" == "1" ]; then
    # add exception for k3d clusters
    rke2_BIN_PATH="/bin/rke2"
  fi
  if [ -z "$rke2_BIN_PATH" ]; then
    fatal "Failed to fetch the rke2 binary path from process $rke2_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/opt/rke2"
  FULL_BIN_PATH="/host$rke2_BIN_PATH"
  if [ ! -f $NEW_BINARY ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi
  info "Comparing old and new binaries"
  BIN_COUNT="$(sha256sum $NEW_BINARY $FULL_BIN_PATH | cut -d" " -f1 | uniq | wc -l)"
  if [ $BIN_COUNT == "1" ]; then
    info "Binary already been replaced"
    exit 0
  fi	  	
  info "Deploying new rke2 binary to $rke2_BIN_PATH"
  cp $NEW_BINARY $FULL_BIN_PATH
  info "rke2 binary has been replaced successfully"
  return
}

kill_rke2_process() {
    # the script sends SIGTERM to the process and let the supervisor
    # to automatically restart rke2 with the new version
    kill -SIGTERM $rke2_PID
    info "Successfully Killed old rke2 process $rke2_PID"
}

prepare() {
  set +e
  KUBECTL_BIN="/opt/rke2 kubectl"
  MASTER_PLAN=${1}
  if [ -z "$MASTER_PLAN" ]; then
    fatal "Master Plan name is not passed to the prepare step. Exiting"
  fi
  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  while true; do
    # make sure master plan does exist
    PLAN=$(${KUBECTL_BIN} get plan $MASTER_PLAN -o jsonpath='{.metadata.name}' -n $NAMESPACE 2>/dev/null)
    if [ -z "$PLAN" ]; then
	    info "master plan $MASTER_PLAN doesn't exist"
	    sleep 5
	    continue
    fi
    NUM_NODES=$(${KUBECTL_BIN} get plan $MASTER_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
    if [ "$NUM_NODES" == "0" ]; then
      break
    fi
    info "Waiting for all master nodes to be upgraded"
    sleep 5
  done
  verify_masters_versions
}

verify_masters_versions() {
  while true; do
    all_updated="true"
    MASTER_NODE_VERSION=$(${KUBECTL_BIN} get nodes --selector='node-role.kubernetes.io/master' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    if [ -z "$MASTER_NODE_VERSION" ]; then
      sleep 5
      continue
    fi
    if [ "$MASTER_NODE_VERSION" == "$SYSTEM_UPGRADE_PLAN_LATEST_VERSION" ]; then
        info "All master nodes has been upgraded to version to $MASTER_NODE_VERSION"
		    break
		fi
    info "Waiting for all master nodes to be upgraded to version $MODIFIED_VERSION"
	  sleep 5
	  continue
  done
}

upgrade() {
  get_rke2_process_info
  replace_binary
  kill_rke2_process
}

"$@"
