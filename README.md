# Generator Analysis

This repository provides utilities for working with GENIE.

## Generate cross-section ROOT file

Set the cross-section XML location:

```bash
export GENIEXSECFILE=/cvmfs/uboone.opensciencegrid.org/products/genie_xsec/v3_00_04_ub2/NULL/U1810a0211a-k250-e1000/data/gxspl-FNALsmall.xml
```

Convert the XML to a ROOT file:

```bash
gxrun "$GENIE_BIN/gspl2root" -f "$GENIEXSECFILE" -p 14 -t 1000180400 -o xsec.root
```

You can also run the included helper script:

```bash
./generate_xsec.sh
```
