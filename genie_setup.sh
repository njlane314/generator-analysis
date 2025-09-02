# ---------- genie_setup.sh ----------
# Usage: source genie_setup.sh
# After sourcing: gxrun gevgen --version
# Optional env before sourcing:
#   export GENIE_VERSION=v3_02_02
#   export GENIE_QUALS="e20:prof"
#   export GENIE_TUNE="GPRD1810a0211b:e1000:k250"

# Be nice when sourced: don't 'set -e' globally; trap errors inside functions.
_genie_die() {
  echo "[genie-setup] ERROR: $*" >&2
  return 1
}

# 1) UPS + PRODUCTS
if ! type setup >/dev/null 2>&1; then
  if [ -r /cvmfs/fermilab.opensciencegrid.org/products/common/etc/setups ]; then
    # shellcheck disable=SC1091
    source /cvmfs/fermilab.opensciencegrid.org/products/common/etc/setups \
      || _genie_die "Failed to source UPS setups"
  else
    _genie_die "UPS setups not found on CVMFS"
  fi
fi

# Compose PRODUCTS (order matters)
_GENIE_PRODUCTS="/cvmfs/fermilab.opensciencegrid.org/products/genie/externals"
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/fermilab.opensciencegrid.org/products/genie/local"
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/larsoft.opensciencegrid.org/products"
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/fermilab.opensciencegrid.org/products/common/db"
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/dune.opensciencegrid.org/products/dune"
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/nova.opensciencegrid.org/externals"
# For cross sections:
_GENIE_PRODUCTS="$_GENIE_PRODUCTS:/cvmfs/uboone.opensciencegrid.org/products"

# Prepend (and dedupe very simply)
if [ -n "${PRODUCTS:-}" ]; then
  export PRODUCTS="${_GENIE_PRODUCTS}:${PRODUCTS}"
else
  export PRODUCTS="${_GENIE_PRODUCTS}"
fi
# Trim any trailing colon
export PRODUCTS="${PRODUCTS%%:}"

# 2) Choose a GENIE version/quals that exists on this node
_GENIE_CANDIDATES=()
_GENIE_CANDIDATES+=("${GENIE_VERSION:-v3_02_02} ${GENIE_QUALS:-e20:prof}")
_GENIE_CANDIDATES+=("v3_02_02 c7:prof")
_GENIE_CANDIDATES+=("v3_02_00 e20:prof")
_GENIE_CANDIDATES+=("v3_02_00 c7:prof")
_GENIE_CANDIDATES+=("v3_04_00 c14:prof")
_GENIE_CANDIDATES+=("v3_00_06k e19:prof")

_setup_one() {
  local ver="$1" ; local q="$2"
  # shellcheck disable=SC1090
  setup genie "$ver" -q "$q" || return 1
  command -v gevgen >/dev/null 2>&1 || return 1
  echo "$ver" > /tmp/.genie_version.$$ 2>/dev/null || true
  echo "$q"   > /tmp/.genie_quals.$$   2>/dev/null || true
  return 0
}

_GENIE_OK=0
for pair in "${_GENIE_CANDIDATES[@]}"; do
  ver="${pair% *}"
  q="${pair#* }"
  if _setup_one "$ver" "$q"; then
    GENIE_VERSION_CHOSEN="$ver"
    GENIE_QUALS_CHOSEN="$q"
    _GENIE_OK=1
    break
  fi
done
[ "$_GENIE_OK" -eq 1 ] || _genie_die "Could not setup any GENIE candidate."

# 3) Pick a cross-section XML that matches (or is compatible with) the GENIE major.minor
# We search uboone UPS area because 'setup genie_xsec' DB entries often aren't installable.
_xsec_try_versions=()
# Prefer same major.minor as GENIE
_mm="$(echo "$GENIE_VERSION_CHOSEN" | awk -F_ '{printf "v%s_%s_00",$2,$3}')"
_xsec_try_versions+=("${mm_override:-$_mm}")
# Nearby versions that are commonly present
_xsec_try_versions+=("v3_02_02" "v3_02_00" "v3_04_00" "v3_00_06")

_pick_xsec() {
  local base="/cvmfs/uboone.opensciencegrid.org/products/genie_xsec"
  for v in "${_xsec_try_versions[@]}"; do
    [ -d "$base/$v" ] || continue
    # Prefer the user's tune if provided
    if [ -n "${GENIE_TUNE:-}" ]; then
      # Convert ':' to path-friendly pattern and search deep
      tpat="$(echo "$GENIE_TUNE" | sed 's/:/[^/]*:/g')"
      xml=$(find "$base/$v" -type f -name '*.xml*' | grep -E "$tpat" | head -n1)
      if [ -n "$xml" ]; then echo "$xml"; return 0; fi
    fi
    # Otherwise grab the largest xsec XML under that version (usually the “full” one)
    xml=$(find "$base/$v" -type f -name '*.xml*' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1{print $2}')
    [ -n "$xml" ] && { echo "$xml"; return 0; }
  done
  return 1
}

GENIEXSECFILE="$(_pick_xsec)" || GENIEXSECFILE=""
export GENIEXSECFILE

# 4) container wrapper (Singularity/Apptainer) to avoid host missing libs
#    Always executes the tool in SL7 and *recreates* the UPS env inside.
_find_container() {
  for img in \
    /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-wn-sl7:latest \
    /cvmfs/singularity.opensciencegrid.org/opensciencegrid/osgvo-el7:latest \
    /cvmfs/singularity.opensciencegrid.org/fermilab/fnal-wn-sl7\:latest \
    /cvmfs/singularity.opensciencegrid.org/opensciencegrid/osgvo-el7\:latest
  do
    [ -r "$img" ] && { echo "$img"; return 0; }
  done
  return 1
}

# Choose runner
if command -v singularity >/dev/null 2>&1; then
  _RUN=singularity
elif command -v apptainer >/dev/null 2>&1; then
  _RUN=apptainer
else
  _RUN=""  # run on host as last resort
fi
export GENIE_RUNNER="${_RUN}"

GENIE_IMAGE="$(_find_container || true)"
export GENIE_IMAGE

gxrun() {
  # Usage: gxrun <GENIE-tool> [args...]
  # Recreate the env *inside* the container every time for reliability.
  if [ -n "${GENIE_RUNNER}" ] && [ -n "${GENIE_IMAGE}" ]; then
    ${GENIE_RUNNER} exec \
      -B /cvmfs -B "${HOME}" -B /tmp -B "$(pwd)" \
      --ipc --pid \
      "${GENIE_IMAGE}" \
      /bin/bash -lc '
        source /cvmfs/fermilab.opensciencegrid.org/products/common/etc/setups &&
        export PRODUCTS="'"${PRODUCTS}"'" &&
        source /cvmfs/fermilab.opensciencegrid.org/products/genie/bootstrap_genie_ups.sh &&
        setup genie '"${GENIE_VERSION_CHOSEN}"' -q '"${GENIE_QUALS_CHOSEN}"' &&
        [ -n "'"${GENIEXSECFILE}"'" ] && export GENIEXSECFILE="'"${GENIEXSECFILE}"'" || true &&
        '"$*"'
      '
  else
    # Host fallback (may fail with libnsl etc.)
    echo "[genie-setup] NOTE: no container runtime found; running on host." >&2
    "$@"
  fi
}

# 5) Diagnostics
echo "------------------------------------------------------------"
echo "[genie-setup] GENIE       : ${GENIE_VERSION_CHOSEN}  (quals: ${GENIE_QUALS_CHOSEN})"
echo "[genie-setup] gevgen path : $(command -v gevgen 2>/dev/null || echo '<not in host PATH>')"
if [ -n "${GENIEXSECFILE}" ]; then
  echo "[genie-setup] XSEC XML    : ${GENIEXSECFILE}"
else
  echo "[genie-setup] XSEC XML    : <not found> (you can set GENIEXSECFILE yourself)"
fi
if [ -n "${GENIE_RUNNER}" ] && [ -n "${GENIE_IMAGE}" ]; then
  echo "[genie-setup] Container   : ${GENIE_RUNNER} -> ${GENIE_IMAGE}"
else
  echo "[genie-setup] Container   : <none> (will run on host)"
fi
echo "[genie-setup] Wrapper     : use 'gxrun <tool> ...' e.g. 'gxrun gevgen --version'"
echo "------------------------------------------------------------"

# Optional quick smoke test helper
genie_smoke_test() {
  echo "[genie-setup] Running smoke tests…"
  gxrun gevgen --version || _genie_die "gevgen failed"
  if [ -n "${GENIEXSECFILE}" ] && [ -r "${GENIEXSECFILE}" ]; then
    tmp=$(mktemp -d)
    cd "$tmp" || return 1
    echo "[genie-setup] tmpdir: $tmp"
    gxrun gevgen -n 5 -p 14 -t 1000180400 -e 0,5 --seed 1 -r 1 \
                 --cross-sections "${GENIEXSECFILE}" \
                 --event-generator-list Default || _genie_die "gevgen run failed"
    ls -lh gntp.1.ghep.root || true
    echo "[genie-setup] OK."
  else
    echo "[genie-setup] Skipping event smoke test (no xsec XML)."
  fi
}
# ---------- end genie_setup.sh ----------

