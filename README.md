This repo is a guide to install CryoSPARC as an Open OnDemand portal app

After cloning the repo, move the install_cryosparc4ood.sh to a build directory and update path to sif image in template/script.sh.erb file when the build is complete
Update the Proxy in the .def file to your proxy IP:port

# Summary

1. Build OS image as root 
2. Create a sandbox as non-root user
3. Launch a singularity shell and install CryoSPARC in sandbox as non-root user
4. Create final image as non-root user

# Details

1. as root

`singularity build --nv cryosparc_4.3.0_for_sandbox.sif cuda-11.8.0-devel-ubuntu22.04_for_cryosparc-4.3.0.def`

2. as non-root user

`singularity build --sandbox cryosparc_4.3.0_sandbox cryosparc_4.3.0_for_sandbox.sif`

3. as non-root user

`singularity shell -w --nv -B $PWD:/mnt cryosparc_4.3.0_sandbox`

*if compute nodes do not have internet access, use your proxy IP for -p since CryoSPARC needs to communicate with cryosparc.com server to verify license*

Singularity> `/mnt/install_cryosparc4ood.sh -l $LICENSE_ID -v 4.3.0 -p http://10.73.132.63:8080`

4. as non-root user

Singularity> `singularity build cryosparc_4.3.0.sif cryosparc_4.3.0_sandbox`
