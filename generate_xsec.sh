#!/bin/bash
# generate_xsec.sh - produce ROOT cross-section file from XML

export GENIEXSECFILE=/cvmfs/uboone.opensciencegrid.org/products/genie_xsec/v3_00_04_ub2/NULL/U1810a0211a-k250-e1000/data/gxspl-FNALsmall.xml

gxrun "$GENIE_BIN/gspl2root" -f "$GENIEXSECFILE" -p 14 -t 1000180400 -o xsec.root
