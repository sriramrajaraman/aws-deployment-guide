#!/bin/bash

. "/etc/parallelcluster/cfnconfig"

if [ "${cfn_node_type}" == "MasterServer" ]; then
   CUDA_INSTALL_PATH=/shared/cuda
   CRYOSPARC_INSTALL_PATH=/shared/cryosparc
   LICENSE_ID=$2
   yum -y update

   # Install CUDA Toolkit (10.2 for CryoSPARC)
   mkdir -p ${CUDA_INSTALL_PATH}
   cd ${CUDA_INSTALL_PATH}
   wget http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_440.33.01_linux.run
   sh cuda_10.2.89_440.33.01_linux.run --defaultroot=/shared/cuda --toolkit --toolkitpath=${CUDA_INSTALL_PATH}/cuda-10.2 --samples --silent
   rm cuda_10.2.89_440.33.01_linux.run

   # Add CUDA to the path
   cat > /etc/profile.d/cuda.sh << 'EOF'
PATH=$PATH:@CUDA_INSTALL_PATH@/cuda-10.2/bin
EOF
   sed -i "s|@CUDA_INSTALL_PATH@|${CUDA_INSTALL_PATH}|g" /etc/profile.d/cuda.sh
   . /etc/profile.d/cuda.sh

   # Download cryoSPARC
   mkdir -p ${CRYOSPARC_INSTALL_PATH}
   cd ${CRYOSPARC_INSTALL_PATH}
   curl -L https://get.cryosparc.com/download/master-latest/${LICENSE_ID} -o cryosparc_master.tar.gz
   curl -L https://get.cryosparc.com/download/worker-latest/${LICENSE_ID} -o cryosparc_worker.tar.gz

   # Install master process
   tar -xf cryosparc_master.tar.gz
   cd cryosparc_master
   ./install.sh --license ${LICENSE_ID} \
      --hostname ${HOSTNAME} \
      --dbpath ${CRYOSPARC_INSTALL_PATH}/cryosparc_db \
      --port 45000 \
      --allowroot \
      --yes

   # Start cryoSPARC master package
   ${CRYOSPARC_INSTALL_PATH}/cryosparc_master/bin/cryosparcm start

   # Add CryoSPARC to the path
   cat > /etc/profile.d/cryosparc.sh << 'EOF'
PATH=$PATH:@CRYOSPARC_INSTALL_PATH@/cryosparc_master/bin
EOF
   sed -i "s|@CRYOSPARC_INSTALL_PATH@|${CRYOSPARC_INSTALL_PATH}|g" /etc/profile.d/cryosparc.sh
   . /etc/profile.d/cryosparc.sh


   echo "export CRYOSPARC_FORCE_USER=true" >> ${CRYOSPARC_INSTALL_PATH}/cryosparc_master/config.sh
   echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> ${CRYOSPARC_INSTALL_PATH}/cryosparc_master/config.sh

   # Install cryoSPARC work package
   cd ${CRYOSPARC_INSTALL_PATH}
   tar -xf cryosparc_worker.tar.gz
   cd cryosparc_worker
   ./install.sh --license ${LICENSE_ID} \
      --cudapath ${CUDA_INSTALL_PATH}/cuda-10.2 \
      --yes

   # Create cluster config files
   cat > ${CRYOSPARC_INSTALL_PATH}/cluster_info.json << 'EOF'
{
"qdel_cmd_tpl": "scancel {{ cluster_job_id }}",
"worker_bin_path": "@CRYOSPARC_INSTALL_PATH@/cryosparc_worker/bin/cryosparcw",
"title": "cryosparc-cluster",
"cache_path": "",
"qinfo_cmd_tpl": "sinfo",
"qsub_cmd_tpl": "sbatch {{ script_path_abs }}",
"qstat_cmd_tpl": "squeue -j {{ cluster_job_id }}",
"send_cmd_tpl": "{{ command }}",
"name": "gpu"
}
EOF

   sed -i "s|@CRYOSPARC_INSTALL_PATH@|${CRYOSPARC_INSTALL_PATH}|g" ${CRYOSPARC_INSTALL_PATH}/cluster_info.json

   cat > ${CRYOSPARC_INSTALL_PATH}/cluster_script.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=cryosparc_{{ project_uid }}_{{ job_uid }}
#SBATCH --output={{ job_log_path_abs }}
#SBATCH --error={{ job_log_path_abs }}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task={{ num_cpu }}
#SBATCH --gres=gpu:{{ num_gpu }}
#SBATCH --partition=gpu
{{ run_cmd }}
EOF

   rm ${CRYOSPARC_INSTALL_PATH}/*.tar.gz
   chown -R ec2-user: /shared/cryosparc

   # Start cluster
   /bin/su -c "${CRYOSPARC_INSTALL_PATH}/cryosparc_master/bin/cryosparcm start" - ec2-user

   # Connect worker nodes to cluster
   /bin/su -c "cd ${CRYOSPARC_INSTALL_PATH} && ${CRYOSPARC_INSTALL_PATH}/cryosparc_master/bin/cryosparcm cluster connect" - ec2-user

   # Restart master
   /bin/su -c "cd ${CRYOSPARC_INSTALL_PATH} && ${CRYOSPARC_INSTALL_PATH}/cryosparc_master/bin/cryosparcm restart" - ec2-user

fi
