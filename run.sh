#!/bin/sh

set -eu
export LC_ALL=C

DOCKER_IMAGE_NAMESPACE=hectormolinero
DOCKER_IMAGE_NAME=hblock-resolver
DOCKER_IMAGE_VERSION=latest
DOCKER_IMAGE=${DOCKER_IMAGE_NAMESPACE}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}
DOCKER_CONTAINER=${DOCKER_IMAGE_NAME}
DOCKER_VOLUME=${DOCKER_CONTAINER}-data

imageExists() { [ -n "$(docker images -q "$1")" ]; }
containerExists() { docker ps -aqf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }
containerIsRunning() { docker ps -qf name="$1" --format '{{.Names}}' | grep -Fxq "$1"; }

if ! imageExists "${DOCKER_IMAGE}"; then
	>&2 printf -- '%s\n' "${DOCKER_IMAGE} image doesn't exist!"
	exit 1
fi

if containerIsRunning "${DOCKER_CONTAINER}"; then
	printf -- '%s\n' "Stopping \"${DOCKER_CONTAINER}\" container..."
	docker stop "${DOCKER_CONTAINER}" >/dev/null
fi

if containerExists "${DOCKER_CONTAINER}"; then
	printf -- '%s\n' "Removing \"${DOCKER_CONTAINER}\" container..."
	docker rm "${DOCKER_CONTAINER}" >/dev/null
fi

if [ -z "${HBLOCK_HEADER_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/header' ]; then
	HBLOCK_HEADER_FILE=/etc/hblock-resolver/hblock.d/header
fi

if [ -z "${HBLOCK_FOOTER_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/footer' ]; then
	HBLOCK_FOOTER_FILE=/etc/hblock-resolver/hblock.d/footer
fi

if [ -z "${HBLOCK_SOURCES_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/sources.list' ]; then
	HBLOCK_SOURCES_FILE=/etc/hblock-resolver/hblock.d/sources.list
fi

if [ -z "${HBLOCK_WHITELIST_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/whitelist.list' ]; then
	HBLOCK_WHITELIST_FILE=/etc/hblock-resolver/hblock.d/whitelist.list
fi

if [ -z "${HBLOCK_BLACKLIST_FILE-}" ] && [ -f '/etc/hblock-resolver/hblock.d/blacklist.list' ]; then
	HBLOCK_BLACKLIST_FILE=/etc/hblock-resolver/hblock.d/blacklist.list
fi

if [ -z "${KRESD_CONF_FILE-}" ] && [ -f '/etc/hblock-resolver/kresd.conf' ]; then
	KRESD_CONF_FILE='/etc/hblock-resolver/kresd.conf'
fi

if [ -z "${KRESD_CONF_DIR-}" ] && [ -d '/etc/hblock-resolver/kresd.conf.d/' ]; then
	KRESD_CONF_DIR='/etc/hblock-resolver/kresd.conf.d/'
fi

if [ -z "${KRESD_EXTERNAL_CERT_KEY-}" ] && [ -f '/etc/hblock-resolver/ssl/server.key' ]; then
	KRESD_EXTERNAL_CERT_KEY='/etc/hblock-resolver/ssl/server.key'
fi

if [ -z "${KRESD_EXTERNAL_CERT-}" ] && [ -f '/etc/hblock-resolver/ssl/server.crt' ]; then
	KRESD_EXTERNAL_CERT='/etc/hblock-resolver/ssl/server.crt'
fi

printf -- '%s\n' "Creating \"${DOCKER_CONTAINER}\" container..."
docker run --detach \
	--name "${DOCKER_CONTAINER}" \
	--hostname "${DOCKER_CONTAINER}" \
	--restart on-failure:3 \
	--log-opt max-size=32m \
	--publish '127.0.0.1:53:53/tcp' \
	--publish '127.0.0.1:53:53/udp' \
	--publish '127.0.0.1:8053:8053/tcp' \
	--mount type=volume,src="${DOCKER_VOLUME}",dst='/var/lib/knot-resolver/' \
	${HBLOCK_HEADER_FILE+ \
		--mount type=bind,src="${HBLOCK_HEADER_FILE}",dst='/etc/hblock.d/header',ro \
	} \
	${HBLOCK_FOOTER_FILE+ \
		--mount type=bind,src="${HBLOCK_FOOTER_FILE}",dst='/etc/hblock.d/footer',ro \
	} \
	${HBLOCK_SOURCES_FILE+ \
		--mount type=bind,src="${HBLOCK_SOURCES_FILE}",dst='/etc/hblock.d/sources.list',ro \
	} \
	${HBLOCK_WHITELIST_FILE+ \
		--mount type=bind,src="${HBLOCK_WHITELIST_FILE}",dst='/etc/hblock.d/whitelist.list',ro \
	} \
	${HBLOCK_BLACKLIST_FILE+ \
		--mount type=bind,src="${HBLOCK_BLACKLIST_FILE}",dst='/etc/hblock.d/blacklist.list',ro \
	} \
	${KRESD_CONF_FILE+ \
		--mount type=bind,src="${KRESD_CONF_FILE}",dst='/etc/knot-resolver/kresd.conf',ro \
	} \
	${KRESD_CONF_DIR+ \
		--mount type=bind,src="${KRESD_CONF_DIR}",dst='/etc/knot-resolver/kresd.conf.d/',ro \
	} \
	${KRESD_NIC+ \
		--env KRESD_NIC="${KRESD_NIC}" \
	} \
	${KRESD_EXTERNAL_CERT_KEY+${KRESD_EXTERNAL_CERT+ \
		--publish '127.0.0.1:853:853/tcp' \
		--mount type=bind,src="${KRESD_EXTERNAL_CERT_KEY}",dst='/var/lib/knot-resolver/ssl/server.key',ro \
		--mount type=bind,src="${KRESD_EXTERNAL_CERT}",dst='/var/lib/knot-resolver/ssl/server.crt',ro \
		--env KRESD_CERT_MODE=external \
	}} \
	"${DOCKER_IMAGE}" "$@" >/dev/null

printf -- '%s\n\n' 'Done!'
exec docker logs -f "${DOCKER_CONTAINER}"
