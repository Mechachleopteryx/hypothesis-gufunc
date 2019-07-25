#!/bin/bash

set -ex
set -o pipefail

# Set conda paths
export CONDA_PATH=./tmp/conda
export CONDA_ENVS=env
PY_VERSIONS=( "3.6" )

# Handy to know what we are working with
git --version

# Cleanup workspace, src for any old -e installs
git clean -x -f -d
rm -rf src/

# Install miniconda
if command -v conda 2>/dev/null; then
    echo "Conda already installed"
else
    # We need to use miniconda since we can't figure out ho to install py3.6 in
    # this env image. We could also use Miniconda3-latest-Linux-x86_64.sh but
    # pinning version to make reprodicible.
    echo "Installing miniconda"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # In future let's also try, for reprodicibility:
        # curl -L -o miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-4.5.12-MacOSX-x86_64.sh;
        curl -L -o miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-latest-MacOSX-x86_64.sh;
    else
        # In future let's also try, for reprodicibility:
        # curl -L -o miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-4.5.12-Linux-x86_64.sh;
        curl -L -o miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh;
    fi
    chmod +x ./miniconda.sh
    ./miniconda.sh -b -p $CONDA_PATH
    rm ./miniconda.sh
fi
export PATH=$CONDA_PATH/bin:$PATH

# Setup env just for installing pre-commit to run hooks on all files
rm -rf "$CONDA_ENVS"
ENV_PATH="${CONDA_ENVS}/gufunc_commit_hooks"
conda create -y -q -p $ENV_PATH python=3.6
echo $ENV_PATH
source activate $ENV_PATH
python --version
pip freeze | sort
# not listing 2nd order deps here, but probably ok
pip install pre-commit==1.15.2
# Now run hooks on all files, don't need to install hooks since run directly
pre-commit run --all-files
# Now can leave env with  pre-commit
conda deactivate
# Also check no changes to files by hooks
test -z "$(git diff)"
# clean up for good measure, but need to keep miniconda tmp folder
git clean -x -f -d --exclude=tmp

# Tool to get compare only the package names in pip file
# On mac, sed -r needs to be seed -E
nameonly () { grep -i '^[a-z0-9]' | sed -r "s/([^=]*)==.*/\1/g" | tr _ - | sort -f; }
pipcheck () { cat $@ | grep -i '^[a-z0-9]' | awk '{print $1}' | sort -f | uniq >ask.log && pip freeze | sed -r /^certifi==/d | sort -f >got.log && diff -i ask.log got.log; }

# Set up environments for all Python versions and loop over them
rm -rf "$CONDA_ENVS"
for i in "${PY_VERSIONS[@]}"
do
    # Now test the deps
    ENV_PATH="${CONDA_ENVS}/deps_test"
    conda create -y -q -p $ENV_PATH python=$i
    echo $ENV_PATH
    source activate $ENV_PATH
    python --version
    pip freeze | sort

    # Install all requirements, make sure they are mutually compatible
    pip install -r requirements/base.txt
    pipcheck requirements/base.txt
    pip install -r requirements/test.txt
    pipcheck requirements/base.txt requirements/test.txt

    # Install package
    python setup.py install
    pipcheck requirements/*.txt

    # Install pipreqs and pip-compile, not listing 2nd order deps here, but probably ok
    pip install pipreqs==0.4.9
    pip install pip-tools==3.8.0
    pip install pip-compile-multi==1.4.0

    # Make sure .in file corresponds to what is imported
    nameonly <requirements/base.in >ask.log
    pipreqs hypothesis_gufunc/ --savepath requirements_chk.in
    nameonly < requirements_chk.in >got.log
    diff ask.log got.log

    nameonly <requirements/test.in >ask.log
    pipreqs test/ --savepath requirements_chk.in
    nameonly <requirements_chk.in >got.log
    diff ask.log got.log

    # Make sure txt file corresponds to pip compile
    pip-compile-multi -o chk

    nameonly <requirements/base.txt >ask.log
    nameonly <requirements/base.chk >got.log
    diff ask.log got.log

    nameonly <requirements/test.txt >ask.log
    nameonly <requirements/test.chk >got.log
    diff ask.log got.log

    # Deactivate virtual environment
    conda deactivate
done

# Set up environments for all Python versions and loop over them
rm -rf "$CONDA_ENVS"
for i in "${PY_VERSIONS[@]}"
do
    # Now test the deps
    ENV_PATH="${CONDA_ENVS}/unit_test"
    conda create -y -q -p $ENV_PATH python=$i
    echo $ENV_PATH
    source activate $ENV_PATH
    python --version
    pip freeze | sort

    pip install -r requirements/test.txt
    python setup.py install

    pytest test/ -v -s --cov=hypothesis_gufunc --cov-report html --hypothesis-seed=0
done