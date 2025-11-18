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
  RKE2_PID=$(ps -ef | grep -E "(/usr|/usr/local|/opt/rke2)/bin/rke2 .*(server|agent)" | grep -E -v "(init|grep)" | awk '{print $1}')

  if [ -z "$RKE2_PID" ]; then
    fatal "rke2 is not running on this server"
  fi

  if [ "$(echo $RKE2_PID | wc -w)" != "1" ]; then
    for PID in $RKE2_PID; do
      ps -fp $PID || true
    done
    fatal "Found multiple rke2 pids"
  fi

  info "rke2 binary is running with pid $RKE2_PID"

  RKE2_BIN_PATH=$(awk 'NR==1 {print $1}' /host/proc/${RKE2_PID}/cmdline)
  if [ -z "$RKE2_BIN_PATH" ]; then
    fatal "Failed to fetch the rke2 binary path from pid $RKE2_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/opt/rke2"
  FULL_BIN_PATH="/host$RKE2_BIN_PATH"

  if [ ! -f "$NEW_BINARY" ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi

  info "Comparing old and new binaries"
  BIN_CHECKSUMS="$(sha256sum $NEW_BINARY $FULL_BIN_PATH)"

  if [ "$?" != "0" ]; then
    fatal "Failed to calculate binary checksums"
  fi

  BIN_COUNT="$(echo "${BIN_CHECKSUMS}" | awk '{print $1}' | uniq | wc -l)"
  if [ "$BIN_COUNT" == "1" ]; then
    info "Binary already been replaced"
    exit 0
  fi

  RKE2_CONTEXT=$(getfilecon $FULL_BIN_PATH 2>/dev/null | awk '{print $2}' || true)
  info "Deploying new rke2 binary to $RKE2_BIN_PATH"
  cp $NEW_BINARY $FULL_BIN_PATH

  if [ -n "${RKE2_CONTEXT}" ]; then
    info 'Restoring rke2 bin context'
    setfilecon "${RKE2_CONTEXT}" $FULL_BIN_PATH
  fi
  info "rke2 binary has been replaced successfully"
  return
}

ensure_home_env() {
  info "Ensuring presence of HOME environment variable"
  RKE2_BIN_DIR=$(dirname $RKE2_BIN_PATH)
  FULL_SYSTEM_PATH="/host$RKE2_BIN_DIR/../lib/systemd/system/"
  for C in server agent; do
    ENV_FILE_PATH="$FULL_SYSTEM_PATH/rke2-$C.env"
    grep -sq '^HOME=' $ENV_FILE_PATH || echo -e "\nHOME=/root" >> $ENV_FILE_PATH
  done
}

kill_rke2_process() {
    # the script sends SIGTERM to the process and let the supervisor
    # to automatically restart rke2 with the new version
    CHILD_PIDS=$(pgrep -lP $RKE2_PID | grep -Eo '[0-9]+ (containerd|kubelet)' | awk 'BEGIN{ORS=" "}{print $1}')
    kill -SIGTERM $RKE2_PID $CHILD_PIDS
    info "Successfully killed old rke2 pid $RKE2_PID and containerd/kubelet pid $CHILD_PIDS"
}

prepare() {
  set +e
  CONTROLPLANE_PLAN=${1}

  if [ -z "$CONTROLPLANE_PLAN" ]; then
    fatal "Control-plane Plan name is not passed to the prepare step. Exiting"
  fi

  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  while true; do
    # make sure control-plane plan does exist
    PLAN=$(kubectl get plan $CONTROLPLANE_PLAN -o jsonpath='{.metadata.name}' -n $NAMESPACE 2>/dev/null)
    if [ -z "$PLAN" ]; then
	    info "Waiting for control-plane Plan $CONTROLPLANE_PLAN to be created"
	    sleep 5
	    continue
    fi
    NUM_NODES=$(kubectl get plan $CONTROLPLANE_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
    if [ "$NUM_NODES" == "0" ]; then
      break
    fi
    info "Waiting for all control-plane nodes to be upgraded"
    sleep 5
  done
  verify_controlplane_versions
}

verify_controlplane_versions() {
  while true; do
    all_updated="true"
    CONTROLPLANE_NODE_VERSION=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    if [ -z "$CONTROLPLANE_NODE_VERSION" ]; then
      sleep 5
      continue
    fi
    K8S_IMAGE_TAG=$(bash /bin/semver-parse.sh $SYSTEM_UPGRADE_PLAN_LATEST_VERSION k8s)
    if [ "$CONTROLPLANE_NODE_VERSION" == "$K8S_IMAGE_TAG" ]; then
        info "All control-plane nodes have been upgraded to version to $CONTROLPLANE_NODE_VERSION"
		    break
		fi
    info "Waiting for all control-plane nodes to be upgraded to version $MODIFIED_VERSION"
	  sleep 5
	  continue
  done
}

upgrade() {
  get_rke2_process_info
  replace_binary
  ensure_home_env
  kill_rke2_process
}

"$@"
