#!/bin/bash

function help {
    echo ""
    echo "------------------------------------------------------------------------"
    echo "   cryoSPARC installer to be used inside Singularity definition file"
    echo "------------------------------------------------------------------------"
    echo
    echo "Usage: $(basename $0) -v version"
    echo ""
    echo "    Required:"
    echo "           -l license_id"
    echo "           -v cryosparc_version"
    echo
    echo "    Optional:"
    echo "           -p http://proxy:port        # required if your cluster uses proxy for internet connectivity"
    echo
}

while getopts ":hl:v:p:" opt; do
  case $opt in
    l)
      license_id=$OPTARG
      ;;
    p)
      http_proxy=$OPTARG
      ;;
    v)
      cryosparc_version=$OPTARG
      ;;
    h)
      help
      exit
      ;;
    *)
      help
      exit
      ;;
  esac
done

#shift the command line options so that all the option will be processed. Otherwise, only the first one is processed.
shift $((OPTIND-1))

if [[ ! -v license_id ]]; then
    printf "\n====> Required option: -l license_id\n\n"
    help
    exit 1
fi

if [[ ! -v cryosparc_version ]]; then
    printf "\n====> Required Option: -v cryosparc_version\n\n"
    help
    exit 1
fi

# get length of license_id should be 35 characters
license_length=${#license_id}
if [[ $license_length != 36 ]]; then
    printf "\n====> Check license_id format\n\n"
    exit 1
fi

# the LICENSE_ID is only needed for the installation; each OOD app user will provide their own license
export LICENSE_ID="$license_id"

export USER=admin
export CRYOSPARC_FORCE_USER=true
export CRYOSPARC_FORCE_HOSTNAME=true

echo "extracting install packages"
tar xzf /mnt/cryosparc_master.tar.gz -C /
tar xzf /mnt/cryosparc_worker.tar.gz -C /
echo "DONE: extracting install packages"

# comment out CHECK HOSTNAME section of install.sh script lines for cryosparc3 (196-199) cryosparc4 (200-206)
sed -i '200,203s/^/#/' /cryosparc_master/install.sh

cd /cryosparc_master && ./install.sh --standalone --yes \
              --hostname localhost \
              --license $LICENSE_ID \
              --worker_path /cryosparc_worker \
              --cudapath /usr/local/cuda \
              --port 39000 \
              --nossd \
              --initial_email "admin@cryo.edu" \
              --initial_password "admin" \
              --initial_username "admin" \
              --initial_firstname "admin" \
              --initial_lastname "admin"

sleep 60

/cryosparc_master/bin/cryosparcm stop

# create a script to remove previous compute node host
cat > /cryosparc_master/bin/remove_hosts.sh <<EOF
#!/usr/bin/env bash
/cryosparc_master/bin/cryosparcm cli 'get_scheduler_targets()'  | /usr/bin/python3 -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | /usr/bin/jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} /cryosparc_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'
EOF
chmod +x /cryosparc_master/bin/remove_hosts.sh

# edit config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=$(cat /cryosparc_license/license_id),' /cryosparc_master/config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=$(cat /cryosparc_license/license_id),' /cryosparc_worker/config.sh

sed -i 's,export CRYOSPARC_MASTER_HOSTNAME=.\+,,' /cryosparc_master/config.sh
sed -i 's,source config.sh,source /cryosparc_master/config.sh,' /cryosparc_master/bin/cryosparcm

echo "export CRYOSPARC_HOSTNAME_CHECK=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_MASTER_HOSTNAME=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_USER=true" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> /cryosparc_master/config.sh
echo "export no_proxy=localhost,127.0.0.0/8" >> /cryosparc_master/config.sh

# WebProxy
if [[ -v http_proxy ]]; then
  echo "export http_proxy=$http_proxy" >> /cryosparc_master/config.sh
  echo "export https_proxy=$http_proxy" >> /cryosparc_master/config.sh
fi

mv /cryosparc_master/config.sh /cryosparc_master/run/
ln -s /cryosparc_master/run/config.sh /cryosparc_master/config.sh

tar czf /cryosparc_database_init_files-${cryosparc_version}.tar.gz /cryosparc_database/ && rm -rf /cryosparc_database/*
tar czf /cryosparc_master-run_init_files-${cryosparc_version}.tar.gz /cryosparc_master/run && rm -rf /cryosparc_master/run/*


