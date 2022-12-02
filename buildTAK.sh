#!/bin/bash
# Verbose output
set -x

# Stop on Error
set -e

PREBUILD=0
CLEAN=0
SKIP=0
newTAK=

usage() { printf "Usage: $0 [-psc ] -f flavor\n\t-p\tJust run prebuild\n\t\n\t-s\tskip prebuild-c\tclean everything\n\n" 1>&2; exit 1; }

while getopts "scpf:" options;
do
    case "${options}" in
        p)
            PREBUILD=1
            ;;
	    s)
	        SKIP=1
	        ;;
        c)
            CLEAN=1
            ;;
        f)
            newTAK=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z ${newTAK} ];
then
    usage
fi

PWD=`pwd`
export ANDROID_NDK_HOME=${PWD}/android-ndk-r12b
export ANDROID_NDK=${PWD}/android-ndk-r12b
export ANDROID_SDK_ROOT=${PWD}/sdk
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
ANDROID_SDK_ROOT=${PWD}/sdk
CMAKE_DIR=${PWD}/cmake-3.14.7-Linux-x86_64
PATH=${PATH}:${CMAKE_DIR}/bin

# Install the pre-requisites to build the system
sudo apt -y install git git-lfs python3-pip dos2unix cmake build-essential tcl ninja-build libxml2-dev \
libssl-dev sqlite3 zlib1g-dev ant openjdk-8-jdk automake autoconf libtool swig cmake apg g++ \
make tcl patch libogdi-dev

pip3 install conan
 
if [ ! -d ${ANDROID_NDK_HOME} ];
then
    wget https://dl.google.com/android/repository/android-ndk-r12b-linux-x86_64.zip
    unzip -q android-ndk-r12b-linux-x86_64.zip
fi

if [ ! -d ${ANDROID_SDK_ROOT} ];
then
    wget https://dl.google.com/android/repository/commandlinetools-linux-8512546_latest.zip
    unzip -q commandlinetools-linux-8512546_latest.zip
    echo "y" | ./cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --licenses
    echo "y" | ./cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_SDK_ROOT} --install "platforms;android-29"
fi

if [ ! -d cmake-3.14.7-Linux-x86_64 ]; 
then
    wget https://cmake.org/files/v3.14/cmake-3.14.7-Linux-x86_64.tar.gz
    tar -zxpf cmake-3.14.7-Linux-x86_64.tar.gz
fi

if [ ! -d ${newTAK} ];
then
    git clone https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV.git ${newTAK}

    cd ${newTAK}

    git lfs install --local
    git lfs fetch
    git lfs checkout
    git submodule update --init --recursive

    cp ../prebuild.sh scripts
    cd scripts
    ./prebuild.sh

    cd ../atak
else
    cd ${newTAK}

    # If the user wants a clean then whack everything
    if [ ${CLEAN} == 1 ];
    then
        rm -rf assimp gdal takengine/thirdparty libLAS LASzip takthirdparty/builds
    fi

    if [ ${SKIP} == 0 ];
    then
        cp ../prebuild.sh scripts
        cd scripts
        ./prebuild.sh

        # If the user just wants to run prebuild then exit
        if [ ${PREBUILD} == 1 ]; 
        then
            printf "Finished building ATAK requirements\n"
            exit
        fi
  	
   	cd ../
    else
	printf "Skipping prebuild script, per user request\n"
    fi
    cd atak
fi

KEYFILE="`pwd`/${newTAK}.keystore"

if [ -f ${KEYFILE} ]; 
then
    rm -f ${KEYFILE}
fi

STOREPASSWORD="1qazxsw2${newTAK}"
KEYPASSWORD="1qazxsw2${newTAK}"
keytool -keystore ${newTAK}.keystore -genkey -noprompt -keyalg RSA -alias debug -dname "CN=Unknown, OU=Unknown, O=\"Vertex Geospatial, Inc.\", L=New Hartford, ST=New York, C=US" -storepass ${STOREPASSWORD} -keypass ${KEYPASSWORD}
keytool -keystore ${newTAK}.keystore -genkey -noprompt -keyalg RSA -alias release -dname "CN=Unknown, OU=Unknown, O=\"Vertex Geospatial, Inc.\", L=New Hartford, ST=New York, C=US" -storepass ${STOREPASSWORD} -keypass ${KEYPASSWORD}

if [ ! -f android_keystore ]; 
then
    ln -s ${KEYFILE} android_keystore
fi

cp ../../template_local.properties local.properties

sed -i "s#{NDKDIR}#${ANDROID_NDK_HOME}#g" local.properties
sed -i "s#{SDKDIR}#${ANDROID_SDK_ROOT}#g" local.properties
sed -i "s#{CMAKEDIR}#${CMAKE_DIR}#g" local.properties
sed -i "s#{KEYFILE}#${KEYFILE}#g" local.properties
sed -i "s/{KEYPASSWORD}/${KEYPASSWORD}/g" local.properties
sed -i "s/{STOREPASSWORD}/${STOREPASSWORD}/g" local.properties

export takRepoConanUrl=
export takRepoUsername=
export takRepoPassword=

# Do NOT Stop on Error
set +e

./gradlew generateJniHeaders assembleCivRelease

cd ../scripts

# Khronos
cp khronos-conanfile.py ../khronos/conanfile.py
pushd ../khronos
conan export-pkg . -f
popd

cd ../atak

./gradlew assembleCivRelease
