#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-22 21:13:49 +0000 (Fri, 22 Jan 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                    S o l r
# ============================================================================ #
"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
SOLR_HOST="${SOLR_HOST%%:*}"
export SOLR_HOST

export SOLR_PORT="${SOLR_PORT:-8983}"
export SOLR_COLLECTION="${SOLR_COLLECTION:-test}"
export SOLR_CORE="${SOLR_COLLECTION:-${SOLR_CORE:-test}}"

# using my own Docker images now as official solr doesn't have builds < 5
#export DOCKER_IMAGE="solr"
export DOCKER_IMAGE="harisekhon/solr"
export DOCKER_CONTAINER="nagios-plugins-solr-test"

export SOLR_VERSIONS="${1:-3.1 3.6 4.10 5.5 6.0 latest}"
if is_travis; then
    export SOLR_VERSIONS="${1:-6.0 latest}"
fi

startupwait=10

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Hadoop checks!!!'
    exit 0
fi

test_solr(){
    local version="$1"
    travis_sample || continue
    echo "Setting up Solr $version docker test container"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" 8983
    if [ ${version:0:1} -ge 4 ]; then
        docker exec -ti "$DOCKER_CONTAINER" solr create_core -c "$SOLR_CORE" || :
        # TODO: fix this on Solr 5.x+
        docker exec -ti "$DOCKER_CONTAINER" bin/post -c "$SOLR_CORE" example/exampledocs/money.xml || :
    fi

    echo
    echo "Setup done, starting checks ..."

    if [ ${version:0:1} -ge 4 ]; then
        # 4.x+
        hr
        ./check_solr_version.py -e "$version"
    fi
    hr
    $perl -T $I_lib ./check_solr_api_ping.pl -v -w 500
    hr
    $perl -T $I_lib ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
    hr
    $perl -T $I_lib ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    hr
    num_expected_docs=4
    [ ${version:0:1} -lt 4 ] && num_expected_docs=0
    # TODO: fix Solr 5 + 6 doc insertion and then tighten this up
    $perl -T $I_lib ./check_solr_query.pl -n 0:4 -v
    hr
    $perl -T $I_lib ./check_solr_write.pl -vvv -w 1000 # because Travis is slow
    hr
    delete_container
    hr
    echo
}

for version in $SOLR_VERSIONS; do
    test_solr $version
done
