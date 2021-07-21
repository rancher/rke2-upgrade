#!/bin/bash

set -e

if [ -z $1 ]; then
    echo "error: tag required as argument"
    exit 1
fi

if [ -z $2 ]; then
    echo "error: version required as argument"
    exit 1
fi

TAG=$1
VERSION=$2
MAJOR=""
MINOR=""
PATCH=""
RKE2=""

if [[ "${TAG}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)\-([a-zA-Z0-9]+)\-?[-+](.*)?$ ]]; then
    MAJOR=${BASH_REMATCH[1]}
    MINOR=${BASH_REMATCH[2]}
    PATCH=${BASH_REMATCH[3]}
    RC=${BASH_REMATCH[4]}
    RKE2_PATCH=${BASH_REMATCH[5]}
fi

if [ "${VERSION}" = "minor" ]; then
    echo "${MINOR}"
elif [ "${VERSION}" = "major" ]; then
    echo "${MAJOR}"
elif [ "${VERSION}" = "patch" ]; then
    echo "${PATCH}"
elif [ "${VERSION}" = "all" ]; then
    echo "v${MAJOR}.${MINOR}.${PATCH}"
elif [ "${VERSION}" = "rke2" ]; then
    echo "${RKE2}"
elif [ "${VERSION}" = "k8s" ]; then
    echo "v${MAJOR}.${MINOR}.${PATCH}-${RKE2_PATCH}"
else
    echo "error: unrecognized version"
    exit 2
fi
