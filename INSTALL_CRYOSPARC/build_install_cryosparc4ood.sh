#!/bin/bash

module load WebProxy

clustername=$(clustername)

if [ $clustername = "faster" ]; then
   http_proxy="http://10.72.8.25:8080"
elif [ $clustername = "grace" ]; then
   http_proxy="http://10.73.132.63:8080"
elif [ $clustername = "aces" ]; then
   http_proxy="http://10.71.8.1:8080"
elif [ $clustername = "faster" ]; then
   http_proxy="http://10.72.8.25:8080"
fi

build4cluster=$clustername
time_zone=$(timedatectl show | grep Timezone | sed 's,Timezone=,,')

function help {
    echo ""
    echo "------------------------------------------------------------------------"
    echo "   Builds a definition file and installs Singularity image"
    echo "------------------------------------------------------------------------"
    echo
    echo "Usage: $(basename $0) -l license_id -t America/Chicago -v version [-p http_proxy] [-b build4clustername]"
    echo ""
    echo "    Required:"
    echo "           -l license                     cryosparc license id"
    echo "           -v version                     cryosparc version that was downloaded"
    echo
    echo "    Optional:"
    echo "           -b build4clustername           build for a different cluster (will add appropriate http_proxy to config)"
    echo "           -p http://10.1.1.1:8080        proxy:port"
    echo "           -t America/Chicago             time zone"
    echo
    echo "    Example command:"
    echo "          srun --nodes=1 --time=7-00:00:00 --ntasks-per-node=1 --cpus-per-task=48 --mem=360G  --pty bash"
    echo
    echo "          ./build_install_cryosparc4ood.sh -l $LICENSE_ID -t America/Chicago -v 4.3.1"
    echo
    echo "    Files:"
    echo "        Need a directory named src with the master and worker files (not symlinks)"
    echo
    echo "    Download Files:"
    echo "        curl -L https://get.cryosparc.com/download/master-latest/$LICENSE_ID -o cryosparc_master.tar.gz"
    echo "        curl -L https://get.cryosparc.com/download/worker-latest/$LICENSE_ID -o cryosparc_worker.tar.gz"
    echo
}

while getopts ":hl:b:c:t:v:p:" opt; do
  case $opt in
    b)
      build4cluster=$OPTARG
      ;;
    l)
      license_id=$OPTARG
      ;;
    p)
      http_proxy=$OPTARG
      ;;
    t)
      time_zone=$OPTARG
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

if [ $build4cluster = "faster" ]; then
   http_proxy_in_config="http://10.72.8.25:8080"
elif [ $build4cluster = "grace" ]; then
   http_proxy_in_config="http://10.73.132.63:8080"
elif [ $build4cluster = "aces" ]; then
   http_proxy_in_config="http://10.71.8.1:8080"
elif [ $build4cluster = "faster" ]; then
   http_proxy_in_config="http://10.72.8.25:8080"
fi

# get length of license_id should be 35 characters
license_length=${#license_id}
if [[ $license_length != 36 ]]; then
    printf "\n====> Check license_id format\n\n"
    exit 1
fi
# for < 4.4.0              --cudapath /usr/local/cuda \

cat > src/install_cryosparc4ood_${clustername}-${cryosparc_version}.sh <<EOF
export LICENSE_ID="$license_id"

export USER=admin
export CRYOSPARC_FORCE_USER=true
export CRYOSPARC_FORCE_HOSTNAME=true

echo "extracting install packages"
tar xzf /mnt/cryosparc_master.tar.gz -C /
tar xzf /mnt/cryosparc_worker.tar.gz -C /
echo "DONE: extracting install packages"

# comment out CHECK HOSTNAME section of install.sh script lines for cryosparc3 (196-199) cryosparc4 (200-206) 4.6.0 (204-207)
sed -i '204,207s/^/#/' /cryosparc_master/install.sh

cd /cryosparc_master && ./install.sh --standalone --yes \
              --hostname localhost \
              --license $license_id \
              --worker_path /cryosparc_worker \
              --port 39000 \
              --nossd \
              --initial_email "admin@cryo.edu" \
              --initial_password "admin" \
              --initial_username "admin" \
              --initial_firstname "admin" \
              --initial_lastname "admin"

# add a new user
# cryosparcm createuser --email "user@organization" --password "init-password" --username "myuser" --firstname "John" --lastname "Doe"
sleep 60

/cryosparc_master/bin/cryosparcm stop

# create a script to remove previous compute node host
cat > /cryosparc_master/bin/remove_hosts.sh <<EOTF
#!/usr/bin/env bash
/cryosparc_master/bin/cryosparcm cli 'get_scheduler_targets()'  | /usr/bin/python3 -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | /usr/bin/jq '.[].name' | sed 's:"::g' | xargs -n1 -I \{\} /cryosparc_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'
EOTF
chmod +x /cryosparc_master/bin/remove_hosts.sh

# edit config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=\$(cat /cryosparc_license/license_id),' /cryosparc_master/config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=\$(cat /cryosparc_license/license_id),' /cryosparc_worker/config.sh
sed -i 's,export CRYOSPARC_MASTER_HOSTNAME=.\+,,' /cryosparc_master/config.sh
sed -i 's,source config.sh,source /cryosparc_master/config.sh,' /cryosparc_master/bin/cryosparcm

echo "export CRYOSPARC_HOSTNAME_CHECK=localhost" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_MASTER_HOSTNAME=localhost" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_FORCE_USER=true" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> /cryosparc_worker/config.sh

echo "export CRYOSPARC_HOSTNAME_CHECK=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_MASTER_HOSTNAME=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_USER=true" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> /cryosparc_master/config.sh
echo "export no_proxy=localhost,127.0.0.0/8" >> /cryosparc_master/config.sh

# WebProxy
if [[ -v http_proxy ]]; then
  echo "export http_proxy=$http_proxy_in_config" >> /cryosparc_master/config.sh
  echo "export https_proxy=$http_proxy_in_config" >> /cryosparc_master/config.sh
fi

mv /cryosparc_master/config.sh /cryosparc_master/run/
ln -s /cryosparc_master/run/config.sh /cryosparc_master/config.sh

tar czf /cryosparc_database_init_files-${cryosparc_version}.tar.gz /cryosparc_database/ && rm -rf /cryosparc_database/*
tar czf /cryosparc_master-run_init_files-${cryosparc_version}.tar.gz /cryosparc_master/run && rm -rf /cryosparc_master/run/*
EOF

cat > cryosparc4ood.def <<'EOF'
BootStrap: docker
#From: nvidia/cuda:11.8.0-devel-ubuntu22.04
From: nvidia/cuda:12.5.1-devel-ubuntu24.04

%environment
  export no_proxy=localhost,127.0.0.0/8
  export PATH=/cryosparc_master/bin:$PATH
  export PATH=/cryosparc_worker/bin:$PATH
EOF

if [[ $http_proxy ]]; then
cat >> cryosparc4ood.def <<EOF
  export http_proxy=$http_proxy
  export https_proxy=$http_proxy
EOF
fi

cat >> cryosparc4ood.def <<EOF

%post
  #Post setup, runs inside the image
  ln -snf /usr/share/zoneinfo/$time_zone /etc/localtime && echo $time_zone > /etc/timezone

  apt-get update
  apt-get upgrade -y
  apt-get install -y --no-install-recommends tzdata locales gnupg2 openssh-server openssh-client ssh-askpass lbzip2 zip

  # Configure default locale
  echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen en_US.utf8
  /usr/sbin/update-locale LANG=en_US.UTF-8
  export LANG="en_US.UTF-8"
  export LC_COLLATE="en_US.UTF-8"
  export LC_CTYPE="en_US.UTF-8"
  export LC_MESSAGES="en_US.UTF-8"
  export LC_MONETARY="en_US.UTF-8"
  export LC_NUMERIC="en_US.UTF-8"
  export LC_TIME="en_US.UTF-8"
  export LC_ALL="en_US.UTF-8"

  # system update
  apt-get update -y
  apt-get upgrade -y

  # install other import packages
  apt-get install -y software-properties-common wget curl less jq iputils-ping
  #apt-get install -y nvidia-driver-545 nvidia-dkms-545
  #apt-get install -y nvidia-driver-550 nvidia-dkms-550
  apt-get install -y nvidia-driver-560 nvidia-dkms-560

  ### gcc compiler is required for development using the cuda toolkit. to verify the version of gcc install enter
  gcc --version

  # Finally, to verify the installation, check
  nvcc -V
  nvcc --list-gpu-code

  bash /mnt/install_cryosparc4ood_${clustername}-${cryosparc_version}.sh -l $license_id -v $cryosparc_version -p $http_proxy

EOF

if [[ $http_proxy ]]; then
SINGULARITYENV_http_proxy=$http_proxy SINGULARITYENV_https_proxy=$http_proxy SINGULARITY_CACHEDIR=$TMPDIR SREGISTRY_DATABASE=$TMPDIR SINGULARITYENV_license_id=$license_id SINGULARITYENV_time_zone=$time_zone SINGULARITYENV_cryosparc_version=$cryosparc_version SINGULARITYENV_no_proxy="localhost,127.0.0.0/8" singularity build --nv --fakeroot -B $PWD/src/:/mnt cryosparc-${cryosparc_version}.sif  cryosparc4ood.def
else
SINGULARITY_CACHEDIR=$TMPDIR SREGISTRY_DATABASE=$TMPDIR SINGULARITYENV_license_id=$license_id SINGULARITYENV_time_zone=$time_zone SINGULARITYENV_cryosparc_version=$cryosparc_version SINGULARITYENV_no_proxy="localhost,127.0.0.0/8" singularity build --nv --fakeroot -B $PWD/src/:/mnt cryosparc-${cryosparc_version}.sif  cryosparc4ood.def
fi
