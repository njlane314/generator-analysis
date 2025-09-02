#!/bin/bash

: '
apptainer shell \
          -B /cvmfs \
          -B /exp/uboone \
          -B /pnfs/uboone \
          -B /run/user \
          -B /etc/hosts \
          -B /etc/localtime \
          -s /bin/bash \
          --env UPS_OVERRIDE='-H Linux64bit+3.10-2.17' \
          /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:jsl
'

#/cvmfs/uboone.opensciencegrid.org/bin/shell_apptainer.sh -i /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:jsl
/cvmfs/uboone.opensciencegrid.org/bin/shell_apptainer.sh
