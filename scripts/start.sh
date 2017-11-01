#!/bin/bash
# start.sh
#
# Start Goesr application
# 
# Author: Eduardo Ferreira
#
# Version 1: Build and run functions for Goers

set -e

CONTAINER_NAME="goesr"
REGISTRY="eduprivate"
SKIP_COMPILE="${SKIP_COMPILE:-false}"

function info() {
	printf '\e[1;32m%-6s\e[m\n' " - $1"
}

function error() {
	printf '\e[1;31m%-6s\e[m\n' " - $1"
}

verifyDocker() {
	docker version > /dev/null

	EXISTS="$(docker network ls -qf "name=development")"
	if [ -z "$EXISTS" ]; then
		docker network create development
	fi
}

verifyConfig() {
	info "Checking app configs"
	if [ ! -f local.env ]; then
		cp local.env{.sample,}
	fi

	SPRING_APPLICATION_JSON="$(cat local.env | grep SPRING_APPLICATION_JSON | awk -F"=" '{print $2}')"
	JSON="$(echo $SPRING_APPLICATION_JSON | jq -e '.')"
	RET=$?

	if [ $RET -ne 0 ] || [ -z "$JSON" ]; then
		error "Variable SPRING_APPLICATION_JSON contain a invalid json!"
		exit 1
	fi
}

compile() {
	if [ "${SKIP_COMPILE}" == "false" ]; then
		info "Compiling Goesr"
		mvn install
	fi
}

startLocal() {
	verifyConfig
	compile
	GOESR_VERSION="$(mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | grep -Ev '(^\[|Download\w+:)')"
	
	cat local.env \
		| grep -vxE '[[:blank:]]*([#;].*)?' \
		| awk -F"=" '{sep = index($0,"=");  if ($1 == "SPRING_APPLICATION_JSON") printf("%s=%s\n", $1, substr($0, sep+1)); else printf("%s=\"%s\"\n", $1, substr($0, sep+1))}' \
		> /tmp/goesr.env

	set -a
	source /tmp/goesr.env
	
	export SPRING_APPLICATION_JSON="$(grep SPRING_APPLICATION_JSON local.env | awk -F"=" '{print $2}')"
	echo "${SPRING_APPLICATION_JSON}"
	java $JAVA_OPTS -jar target/goesr-${FRENZY_VERSION}.jar
}

function startGoesr() {
	RUNNING="$(docker ps -q -f "name=$CONTAINER_NAME" | wc -l)"

	if [ $RUNNING -eq 0 ]; then
		verifyConfig

		EXISTS=$(docker images -qa "$REGISTRY/$CONTAINER_NAME" | wc -l)
		if [ $EXISTS -eq 0 ]; then
			buildFrenzy
		fi

		info "Container [${CONTAINER_NAME}] is not running, starting ${CONTAINER_NAME}"
		docker run \
			--rm=true \
			--detach=true \
			--name $CONTAINER_NAME \
			--network=development \
			--env-file local.env \
			-p 8000:8000 \
			-p 8877:8877 \
			${REGISTRY}/${CONTAINER_NAME}
	else
		info "Container [${CONTAINER_NAME}] is running."
	fi
}

function buildGoesr() {
	verifyConfig
	compile

	info "Creating image ${CONTAINER_NAME}"
}

function reCreateGoesr() {
	destroyGoesr
	buildGoesr
	startGoesr
}

function destroyGoesr() {
	info "Removing container ${CONTAINER_NAME}"
	docker ps -qa -f "name=${CONTAINER_NAME}" | xargs docker rm -f

	info "Removing $CONTAINER_NAME"
	docker image ls -qa --filter "reference=$REGISTRY/$CONTAINER_NAME" | xargs docker rmi -f
}

function stopGoesr() {
	info "Stoping container ${CONTAINER_NAME}"
	docker ps -q -f "name=$CONTAINER_NAME" | xargs docker stop
}


# **** Start Here ****
DIR=$(dirname $0)

verifyDocker

case "$1" in
	"start")
		startFrenzy
		;;
	"stop")
		stopFrenzy
		;;
	"status")
		docker ps -f "name=${CONTAINER_NAME}"
		;;
	"recreate")
		reCreateGoesr
		;;
	"restart")
		stopGoesr
		sleep 1
		startGoesr
		;;
	"cleanup")
		destroyGoesr
		;;
	"startLocal")
		startLocal
		;;
	*)
		error "Usage: $0 start|stop|recreate|restart|cleanup|startLocal"
		exit 1
		;;
esac