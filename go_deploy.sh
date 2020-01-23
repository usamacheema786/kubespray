#!/usr/bin/env bash

# function definitions
help(){
    echo "Usage: $0 [OPTION]..."
    echo "  -h, --help                 Show this help output"
    echo "  -s, --skip_python_install  Skip installing python for subsequent ansible runs"
    echo "  -t, --ansible_tags         ansible tags"
    echo "  -i, --inventory            inventory file path"
    echo ""
    exit 0;
}

# util functions
# verifies if pssh is installed else installs it
check_and_install_pssh(){
    if [ ! "$( command -v parallel-ssh )" ]; then
        echo "> pssh not found on your system installing it"
        sudo apt-get install pssh -y
    fi
}

# install python before doing a greenfield production deployment
install_python_on_remote_host(){
    local deployment_dir=$1

    check_and_install_pssh
    prod_hosts="$( egrep '^node-0*[[:blank:]]|ansible_ssh_host' ${deployment_dir}/${env_type} |
                awk -F '=' '{print $2 }')"

    # Clears host IPs from known-hosts
    echo "> Clearing host entries from known_hosts"
    for ip in $prod_hosts
    do
        ssh-keygen -f "${HOME}/.ssh/known_hosts" -R $ip
    done

    parallel-ssh -i  -H "$prod_hosts" -l root -x "-oStrictHostKeyChecking=no -i ${deployment_dir}/.ssh/id_rsa" 'dpkg -s python2.7 &> /dev/null'
    if [ $? -eq 0 ]; then
       echo "Python already installed"
    else
       echo "> Installing python on ${prod_hosts}"
       parallel-ssh -i  -H "$prod_hosts" -l root -x "-oStrictHostKeyChecking=no -i ${deployment_dir}/.ssh/id_rsa" 'apt-get update && apt-get install python -y'
    fi

}

# deploys prod env
DEPLOY_ERRORS=0
deploy_prod_env(){
    local current_dir="$( cd "$( dirname "$0" )" && pwd )"
    local deployment_dir="${current_dir}"

    # shame! new ubuntu images on DigitalOcean don't come with python pre-installed.
    if [ -z $skip_python_install ]; then
        install_python_on_remote_host $deployment_dir
    fi

    if [ -z $ansible_tags ]; then
        cd $deployment_dir && ansible-playbook site.yml -i ${env_type}
        DEPLOY_ERRORS=$?
    else
        if [ -z $extra_vars ]; then
            cd $deployment_dir && ansible-playbook site.yml -i ${env_type} --tags="${ansible_tags}"
        else
            cd $deployment_dir && ansible-playbook site.yml -i ${env_type} --tags="${ansible_tags}" -e "${redeploy_app}"
        fi
        DEPLOY_ERRORS=$?
    fi

    exit $DEPLOY_ERRORS
}




# default behavior
testargs=""
skip_python_install=""
ansible_tags=""
add_swarm_workers=""
extra_vars=""
dev_env=0
prod_env=0
env_type=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) shift; help;;
        -t|--ansible_tags) shift; ansible_tags=$1;;
        -e|--extra_vars) shift; extra_vars=$1;;
        -s|--skip_python_install) shift; skip_python_install=1;;
        -i|--inventory) shift;prod_env=1; env_type=$1;;
        *) testargs="$testargs $1"; shift;
    esac
done


if [ $prod_env -eq 1 ]; then
    deploy_prod_env
    exit $?
fi


help;
