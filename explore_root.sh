#!/bin/bash
file=$1
root -l -b -q <<EOT
TFile f("$file");
f.ls();
EOT
