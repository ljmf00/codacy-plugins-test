#!/usr/bin/env bash

#
# Simple Wrapper to build a native binary for your sbt application.
#
# Configuration:
# * Target:
#   * `native` - Builds the binary for the machine arch (Requires GraalVM and Oracle JDK 8)
#   * `docker` - Builds the binary for linux using a docker (Requires Docker)
#
# Setup GraalVM and Oracle JDK 8:
#   * Install GraalVM (https://www.graalvm.org/docs/getting-started/).
#   * Install Oracle JDK 8 (http://www.oracle.com/technetwork/java/javase/downloads/jdk8-downloads-2133151.html).
#   * Add GraalVM native-image bin to the beginning of your PATH.
#   * Set Oracle JDK 8 as your JAVA_HOME, JDK_HOME and JRE_HOME.
#   * Add Oracle JDK 8 bin to the beginning of your PATH.
#
# Example:
# ./scripts/publish-native.sh -n codacy-plugins-test -m codacy.plugins.DockerTest -t docker 1.0.0
#

set -e

VERSION="1.0.0-$(git symbolic-ref --short HEAD)-SNAPSHOT"
TARGET="docker"
OS_TARGET="$(uname | awk '{print tolower($0)}')"

function usage() {
  echo >&2 "Usage: $0 -n <app-name> -m <main-class> [-t target (native)] [app-version (1.0.0-<branch-name>-SNAPSHOT)]"
}

while getopts :t:n:m:h opt
do
  case "$opt" in
    t)
      TARGET="$OPTARG"

      if [[ "$TARGET" == "docker" && "$OS_TARGET" == "darwin" ]]
      then
        echo >&2 "Target docker can only build binaries for linux."
        OS_TARGET="linux"
      fi
      ;;
    n)
      APP_NAME="$OPTARG"
      ;;
    m)
      APP_MAIN_CLASS="$OPTARG"
      ;;
    h | ?)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
	esac
done

shift $((OPTIND-1))

if [ -z "$APP_NAME" ]; then
  echo >&2 "App name was not provided."
  usage
  exit 1
fi

if [ -z "$APP_MAIN_CLASS" ]; then
  echo >&2 "Main class was not provided."
  usage
  exit 1
fi

if [ -n "$1" ]; then
  VERSION="$1"
fi

function app_classpath() {
  sbt 'export runtime:fullClasspath' < /dev/null | tail -n 1
}

function build_cmd() {
  local BINARY_NAME=$1
  local APP_MAIN_CLASS=$2
  local APP_CLASSPATH=$3
  local FLAGS="-O1 -J-Xmx4G -H:+ReportExceptionStackTraces --no-fallback --initialize-at-build-time --report-unsupported-elements-at-runtime"
  # Flags for debug
  # FLAGS+=" --allow-incomplete-classpath -H:+TraceClassInitialization"

  if [[ "$OS_TARGET" != "darwin" ]]
  then
    FLAGS+=" --static"
  fi

  echo 'native-image -cp '"$APP_CLASSPATH"' '"$FLAGS"' -H:Name='"$BINARY_NAME"' -H:Class='"$APP_MAIN_CLASS"
}

echo "Publishing $APP_NAME binary version $VERSION for $OS_TARGET"
BINARY_NAME="$APP_NAME-$OS_TARGET-$VERSION"
BUILD_CMD="$(build_cmd "$BINARY_NAME" "$APP_MAIN_CLASS" "$(app_classpath)")"

echo "Going to run $BUILD_CMD ..."
case "$TARGET" in
  native)
    $BUILD_CMD
    ;;
  docker)
    docker run \
      --rm=true \
      -it \
      -e JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS" \
      --user=root \
      --entrypoint=bash \
      -v "$HOME":"$HOME":ro \
      -v "$PWD":"$PWD" \
      findepi/graalvm:19.2.0.1-native \
        -c 'cd /tmp && '"$BUILD_CMD"' && mv '"$BINARY_NAME $PWD/$BINARY_NAME"
    ;;
  *)
    echo >&2 "Could not find command for target $TARGET"
    exit 1
    ;;
esac
