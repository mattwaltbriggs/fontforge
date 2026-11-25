#!/usr/bin/env bash

set -e -o pipefail
SCRIPT_BASE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INVOKE_BASE="$(pwd)"

APPDIR=$(realpath $1)
HASH=${2:0:7}
PYTHON="$3"

if [ -z "$APPDIR" ]; then
    echo "Usage: `basename $0` appdir hash"
    echo "  appdir is the location to the FontForge.app that cmake generated"
    echo "  hash is the version hash of this build"
    echo
    echo "  This script does not support overwriting an existing bundle."
    exit 1
fi

builddate=`date +%Y-%m-%d`

if [ -z "$LDDX" ]; then
    LDDX="$SCRIPT_BASE/lddx"
    if [ ! -f "$LDDX" ]; then
        LDDX="$INVOKE_BASE/lddx"
        if [ ! -f "$LDDX" ]; then
            echo "Fetching lddx..."
            curl -L https://github.com/jtanx/lddx/releases/download/v0.1.0/lddx-0.1.0.tar.xz | tar -Jxf - -C "$INVOKE_BASE"
        fi
    fi
fi

# Now we bundle the Python libraries
echo "Bundling Python libraries..."

PY_DLLS_PATH=`$PYTHON -c "import sysconfig as sc; print(sc.get_path('platlib', 'posix_prefix', vars={'platbase': '.'}))"`

PYLIB=$(otool -L $APPDIR/Contents/Resources/opt/local/bin/fontforge | grep -i python | sed -e 's/ \(.*\)//')
PYVER=$(echo $PYLIB | rev | cut -d/ -f2 | rev)
PYTHON=python$PYVER
pycruft=$(realpath $(dirname $PYLIB)/../../..)

echo "pycruft: $pycruft"
mkdir -p $APPDIR/Contents/Frameworks
cp -a $pycruft/Python.framework $APPDIR/Contents/Frameworks
pushd $APPDIR/Contents/Frameworks/Python.framework/Versions/$PYVER/lib/$PYTHON/
rm site-packages || rm -rf site-packages
ln -s ../../../../../../Resources/opt/local/$PY_DLLS_PATH
popd

pushd $APPDIR/Contents/Resources/opt/local/$PY_DLLS_PATH
cp -Rn "$pycruft/Python.framework/Versions/$PYVER/lib/$PYTHON/site-packages/" .
popd

find "$APPDIR/Contents/Frameworks/Python.framework" -type f -name '*.pyc' | xargs rm -rf

pushd $APPDIR/Contents/Resources/opt/local
echo "Collecting and patching dependent libraries..."
$LDDX --overwrite --modify-special-paths --recursive --ignore-prefix /opt/X11 --collect lib \
    bin/ $APPDIR/Contents/Frameworks/Python.framework/ lib/
popd

# Homebrew's certifi ships a symlink to a location that does not exist inside
# the bundle. Replace it with the system CA bundle so the bundle can be
# codesigned and so Python's SSL module works when launched from the .app.
CACERT="$APPDIR/Contents/Resources/opt/local/lib/python$PYVER/site-packages/pip/_vendor/certifi/cacert.pem"
if [ -L "$CACERT" ] && [ ! -e "$CACERT" ]; then
    rm -f "$CACERT"
    cp /etc/ssl/cert.pem "$CACERT"
fi

mkdir -p $APPDIR/Contents/MacOS
ln -s ../Frameworks/Python.framework/Versions/$PYVER/bin/$PYTHON "$APPDIR/Contents/MacOS/FFPython"

# Relocated Mach-O files need a fresh signature. A Developer ID identity is
# recommended for notarization; an ad-hoc signature (-) runs after the user
# removes the download quarantine. codesign --deep only signs nested bundles,
# not the loose dylibs that lddx relocates under Contents/Resources, so sign
# every Mach-O file first and then re-seal the bundle and its frameworks.
if [ -n "${FONTFORGE_CODESIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$FONTFORGE_CODESIGN_IDENTITY"
    SIGN_ARGS=(--force)
    if [ "$SIGN_IDENTITY" = "-" ]; then
        SIGN_ARGS+=(--sign -)
    else
        SIGN_ARGS+=(--options runtime --timestamp --sign "$SIGN_IDENTITY")
    fi

    echo "Codesigning bundle with $SIGN_IDENTITY..."
    signed=0
    while IFS= read -r -d '' file; do
        case "$file" in
            */_CodeSignature/*) continue ;;
        esac
        if file -b "$file" | grep -q '^Mach-O'; then
            codesign "${SIGN_ARGS[@]}" "$file"
            signed=$((signed + 1))
        fi
    done < <(find "$APPDIR" -type f -print0)
    echo "Signed $signed individual Mach-O files."

    codesign "${SIGN_ARGS[@]}" --deep "$APPDIR"
    codesign --verify --deep --strict "$APPDIR"
fi

# Package it up
if [ ! -z "$CI" ]; then
    echo "Creating the dmg..."
    if [[ "$PYVER" < "3" ]]; then
        dmgname=FontForge-$builddate-${HASH:0:7}-$PYTHON.app.dmg
    else
        dmgname=FontForge-$builddate-${HASH:0:7}.app.dmg
    fi

    hdiutil create -size 800m   \
        -volname   FontForge     \
        -srcfolder $APPDIR       \
        -ov        -format UDBZ  \
        $dmgname
fi
