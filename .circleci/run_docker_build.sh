#!/usr/bin/env bash

REPO_ROOT=$(cd "$(dirname "$0")/.."; pwd;)
IMAGE_NAME="condaforge/linux-anvil"

docker info

config=$(cat <<CONDARC

channels:
 - mcs07
 - conda-forge
 - defaults

always_yes: true
show_channel_urls: true

CONDARC
)

# In order for the conda-build process in the container to write to the mounted
# volumes, we need to run with the same id as the host machine, which is
# normally the owner of the mounted volumes, or at least has write permission
HOST_USER_ID=$(id -u)
# Check if docker-machine is being used (normally on OSX) and get the uid from
# the VM
if hash docker-machine 2> /dev/null && docker-machine active > /dev/null; then
    HOST_USER_ID=$(docker-machine ssh $(docker-machine active) id -u)
fi

cat << EOF | docker run -i \
                        -v ${REPO_ROOT}:/home/conda/conda-recipes \
                        -a stdin -a stdout -a stderr \
                        -e HOST_USER_ID=${HOST_USER_ID} \
                        $IMAGE_NAME \
                        bash -ex || exit $?

if [ "${BINSTAR_TOKEN}" ];then
    export BINSTAR_TOKEN=${BINSTAR_TOKEN}
fi

# Unused, but needed by conda-build currently... :(
export CONDA_NPY='19'

echo "$config" > ~/.condarc

# A lock sometimes occurs with incomplete builds. The lock file is stored in build_artifacts.
conda clean --lock

conda install conda-forge-ci-setup=1.* conda-forge-pinning networkx anaconda-client
source run_conda_forge_build_setup

# yum installs anything from a "yum_requirements.txt" file that isn't a blank line or comment.
find ~/conda-recipes -mindepth 2 -maxdepth 2 -type f -name "yum_requirements.txt" \
    | xargs -n1 cat | grep -v -e "^#" -e "^$" | \
    xargs -r /usr/bin/sudo -n yum install -y

conda info
conda config --get

python ~/conda-recipes/.ci_support/build_all.py ~/conda-recipes/recipes
EOF
