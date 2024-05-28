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
  info "rke2 binary is running with pid $RKE2_PID"
  RKE2_BIN_PATH=$(cat /host/proc/${RKE2_PID}/cmdline | awk '{print $1}' | head -n 1)
  if [ -z "$RKE2_BIN_PATH" ]; then
    fatal "Failed to fetch the rke2 binary path from process $RKE2_PID"
  fi
  return
}

replace_binary() {
  NEW_BINARY="/opt/rke2"
  FULL_BIN_PATH="/host$RKE2_BIN_PATH"
  if [ ! -f $NEW_BINARY ]; then
    fatal "The new binary $NEW_BINARY doesn't exist"
  fi
  info "Comparing old and new binaries"
  BIN_COUNT="$(sha256sum $NEW_BINARY $FULL_BIN_PATH | cut -d" " -f1 | uniq | wc -l)"
  if [ $BIN_COUNT == "1" ]; then
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
    info "Successfully Killed old rke2 process $RKE2_PID and containerd/kubelet processes $CHILD_PIDS"
}

prepare() {
  set +e
  MASTER_PLAN=${1}
  if [ -z "$MASTER_PLAN" ]; then
    fatal "Master Plan name is not passed to the prepare step. Exiting"
  fi
  NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  while true; do
    # make sure master plan does exist
    PLAN=$(kubectl get plan $MASTER_PLAN -o jsonpath='{.metadata.name}' -n $NAMESPACE 2>/dev/null)
    if [ -z "$PLAN" ]; then
	    info "master plan $MASTER_PLAN doesn't exist"
	    sleep 5
	    continue
    fi
    NUM_NODES=$(kubectl get plan $MASTER_PLAN -n $NAMESPACE -o json | jq '.status.applying | length')
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
    MASTER_NODE_VERSION=$(kubectl get nodes --selector='node-role.kubernetes.io/master' -o json | jq -r '.items[].status.nodeInfo.kubeletVersion' | sort -u | tr '+' '-')
    if [ -z "$MASTER_NODE_VERSION" ]; then
      sleep 5
      continue
    fi
    K8S_IMAGE_TAG=$(bash /bin/semver-parse.sh $SYSTEM_UPGRADE_PLAN_LATEST_VERSION k8s)
    if [ "$MASTER_NODE_VERSION" == "$K8S_IMAGE_TAG" ]; then
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
  ensure_home_env
  kill_rke2_process
}

"$@"
