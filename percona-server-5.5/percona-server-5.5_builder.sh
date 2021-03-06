#!/bin/sh

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is 1 src rpm will be built
        --build_source_deb  If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --build_tarball     If it is 1 tarball will be built
        --install_deps      Install build dependencies(root previlages are required)
        --branch            Branch for build
        --repo              Repo for build
        --yassl             build tarball with yassl
        
        --help) usage ;;
Example $0 --builddir=/tmp/PS55 --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "$(shell_quote_string "$1")
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi
  
    for arg do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --build_tarball=*) TARBALL="$val" ;;
            --branch=*) BRANCH="$val" ;;
            --repo=*) REPO="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --yassl=*) YASSL="$val" ;;
            --help) usage ;;      
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
        then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

add_percona_yum_repo(){
    if [ ! -f /etc/yum.repos.d/percona-dev.repo ]
    then
        cat >/etc/yum.repos.d/percona-dev.repo <<EOL
[percona-dev-$basearch]
name=Percona internal YUM repository for build slaves \$releasever - \$basearch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/\$basearch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1

[percona-dev-noarch]
name=Percona internal YUM repository for build slaves \$releasever - noarch
baseurl=http://jenkins.percona.com/yum-repo/\$releasever/RPMS/noarch
gpgkey=http://jenkins.percona.com/yum-repo/PERCONA-PACKAGING-KEY
gpgcheck=0
enabled=1
EOL
    fi
    return
}

add_percona_apt_repo(){
  if [ ! -f /etc/apt/sources.list.d/percona-dev.list ]; then
    cat >/etc/apt/sources.list.d/percona-dev.list <<EOL
deb http://jenkins.percona.com/apt-repo/ @@DIST@@ main
deb-src http://jenkins.percona.com/apt-repo/ @@DIST@@ main
EOL
    sed -i "s:@@DIST@@:$OS_NAME:g" /etc/apt/sources.list.d/percona-dev.list
  fi
  
  add_key="apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys 9334A25F8507EFA5"
  until ${add_key}; do
    sleep 1
    echo "waiting"
  done
  return
}

get_sources(){
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi

    git clone "$REPO"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi

    cd percona-server
    if [ ! -z "$BRANCH" ]
    then
        git reset --hard
        git clean -xdf
        git checkout "$BRANCH"
    fi

    REVISION=$(git rev-parse --short HEAD)
    git reset --hard
    #
    source VERSION
    cat VERSION > ../percona-server-5.5.properties
    #
    echo "REVISION=${REVISION}" >> ../percona-server-5.5.properties
    BRANCH_NAME="$(echo ${BRANCH} | awk -F '/' '{print $(NF)}')"
    echo "BRANCH_NAME=${BRANCH}" >> ../percona-server-5.5.properties
    echo "PRODUCT=Percona-Server-${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}" >> ../percona-server-5.5.properties
    echo "PRODUCT_FULL=Percona-Server-${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}${MYSQL_VERSION_EXTRA}" >> ../percona-server-5.5.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> ../percona-server-5.5.properties
    echo "BUILD_ID=${BUILD_ID}" >> ../percona-server-5.5.properties
    #
    if [ -z "${DESTINATION}" ]; then
    export DESTINATION=experimental
    fi 
    #
    echo "DESTINATION=${DESTINATION}" >> ../percona-server-5.5.properties
    #
    cmake . -DENABLE_DTRACE=OFF
    make dist

    EXPORTED_TAR=$(basename $(find . -type f -name percona-server*.tar.gz | sort | tail -n 1))
    #
    cp $EXPORTED_TAR $WORKDIR
    cd $WORKDIR
    PSDIR=${EXPORTED_TAR%.tar.gz}
    rm -fr ${PSDIR}
    tar xzf ${EXPORTED_TAR}
    rm -f ${EXPORTED_TAR}
    #
    cd ${PSDIR}
    #
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/debian/rules
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/debian/rules
    sed -i "s:@@PERCONA_VERSION_EXTRA@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/debian/yakkety.rules
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/debian/yakkety.rules
    #
    sed -i "s:@@MYSQL_VERSION@@:${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}:g" build-ps/percona-server.spec
    sed -i "s:@@PERCONA_VERSION@@:${MYSQL_VERSION_EXTRA#-}:g" build-ps/percona-server.spec
    sed -i "s:@@REVISION@@:${REVISION}:g" build-ps/percona-server.spec
    #
    cd ${WORKDIR}
    # create a PS tar
    tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${PSDIR}.tar.gz ${PSDIR}
    rm -fr ${PSDIR}
    
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PSDIR}.tar.gz $WORKDIR/source_tarball
    cp ${PSDIR}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf percona-server  
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ ! $( id -u ) -eq 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    if [ "x$OS" = "xrpm" ]; then
        add_percona_yum_repo
        yum -y install epel-release git redhat-lsb
        yum clean metadata
        yum -y install libtool rpm-build gcc-c++ gperf ncurses-devel perl readline-devel openssl-devel jemalloc 
        yum -y install time zlib-devel libaio-devel bison cmake pam-devel libeatmydata jemalloc-devel
        yum -y install perl-Time-HiRes || true
        yum -y install selinux-policy-devel || true
    else
        add_percona_apt_repo
      	apt-get update
        apt-get -y install dirmngr || true
        apt-get -y install lsb-release
        apt-get -y purge eatmydata || true
    	apt-get -y install git libtool curl bison cmake perl libssl-dev gcc g++ libaio-dev libldap2-dev libwrap0-dev gdb
  	apt-get -y install lsb-release libmecab-dev libncurses5-dev libreadline-dev libpam-dev zlib1g-dev 
  	apt-get -y install libnuma-dev libjemalloc-dev libeatmydata
        apt-get -y install cmake autotools-dev autoconf automake build-essential devscripts debconf debhelper fakeroot 
        apt-get -y install chrpath ghostscript gawk bison cmake libaio-dev libmecab-dev libncurses5-dev lsb-release perl po-debconf psmisc zlib1g-dev libreadline-dev libpam-dev libssl-dev libnuma-dev libwrap0-dev libldap2-dev dh-systemd || true
    fi
    if [ ! -d /usr/local/percona-subunit2junitxml ]; then
        cd /usr/local
        git clone https://github.com/percona/percona-subunit2junitxml.git
        rm -rf /usr/bin/subunit2junitxml
        ln -s /usr/local/percona-subunit2junitxml/subunit2junitxml /usr/bin/subunit2junitxml
        cd ${CURPLACE}
    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'percona-server*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'percona-server*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "percona-server*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "percona-server*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    ls | grep -v percona-server*.tar.* | xargs rm -rf
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}

    TARFILE=$(find . -name 'percona-server*.tar.gz' | sort | tail -n1)
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    #
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    cd ${WORKDIR}/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/build-ps/*.spec' --strip=2
    
    cd ${WORKDIR}/rpmbuild/SOURCES
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/build-ps/rpm/*.patch' --strip=3
    #
    cd ${WORKDIR}
    #
    cp ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .generic" rpmbuild/SPECS/percona-server.spec

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    return
}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'Percona-Server-*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'Percona-Server-*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/
    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .$OS_NAME" --rebuild rpmbuild/SRPMS/$SRC_RPM

    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
    
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    rm -rf percona-server*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.debian.tar.gz *.changes
    #
    TARFILE=$(basename $(find . -name 'percona-server-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    export DEBIAN=$(lsb_release -sc)
    export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    NEWTAR=${NAME}-${SHORTVER}_${VERSION}-${RELEASE}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}
#
    tar zxf ${NEWTAR}
    cd ${NAME}-${VERSION}-${RELEASE}
    cp -ap build-ps/debian/ .

    dch -D unstable --force-distribution -v "${VERSION}-${RELEASE}-1" "Update to new upstream release Percona Server ${VERSION}-${RELEASE}"

    dpkg-buildpackage -S
    cd ../
    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb
    cp *.debian.tar.* $WORKDIR/source_deb
    cp *_source.changes $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.debian.tar.* $CURDIR/source_deb
    cp *_source.changes $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrpm" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes' 'debian.tar*'
    do
        get_deb_sources $file
    done
    cd $WORKDIR
    rm -fv *.deb
    #
    export DEBIAN_VERSION=$(lsb_release -sc)
    export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
    #
    echo "DEBIAN_VERSION=${DEBIAN_VERSION}" >> percona-server-5.5.properties
    echo "ARCH=${ARCH}" >> percona-server-5.5.properties
    
    #
    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n1))
    DIRNAME=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $1"-"$2"-"$3"-"$4"-"$5}')
    VERSION=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $4}')
    RELEASE=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $5}')

    #
    dpkg-source -x ${DSC}
    #
    cd ${DIRNAME}
    #

    if [ ${DEBIAN_VERSION} = "artful" -o ${DEBIAN_VERSION} = "bionic" ]; then
        sed -i 's|MYSQL_BUILD_CXX:-g++|MYSQL_BUILD_CXX:-g++ -Wno-error=date-time -Wimplicit-fallthrough=0 |' debian/rules 
        sed -i 's/fno-rtti/fno-rtti -Wno-error=date-time -Wimplicit-fallthrough=0 /' debian/rules
        sed -i 's|MYSQL_BUILD_CC:-gcc|MYSQL_BUILD_CC:-gcc -Wno-error=date-time -Wimplicit-fallthrough=0 |' debian/rules
        sed -i 's/-O2 -g -fno-strict-aliasing/-O2 -g -fno-strict-aliasing -Wno-error=date-time -Wimplicit-fallthrough=0 /' debian/rules    
    fi

    dch -m -D "$DEBIAN_VERSION" --force-distribution -v "${EPOCH:-}${VERSION}-rel${RELEASE}-1.${DEBIAN_VERSION}" 'Update distribution'
    #
    dpkg-buildpackage -rfakeroot -uc -us -b
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.deb $WORKDIR/deb
    cp $WORKDIR/*.deb $CURDIR/deb
}

build_tarball(){
    if [ $TARBALL = 0 ]
    then
        echo "Binary tarball will not be created"
        return;
    fi
    get_tar "source_tarball"
    cd $WORKDIR
    TARFILE=$(basename $(find . -name 'percona-server-*.tar.gz' | sort | tail -n1))
    if [ -f /etc/debian_version ]; then
      export OS_RELEASE="$(lsb_release -sc)"
    fi
    #
    if [ -f /etc/redhat-release ]; then
      export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
      RHEL=$(rpm --eval %rhel)
    fi
    #

    ARCH=$(uname -m 2>/dev/null||true)
    TARFILE=$(basename $(find . -name 'percona-server-*.tar.gz' | sort | grep -v "tools" | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1"-"$2}')
    VERSION=$(echo ${TARFILE}| awk -F '-' '{print $3}')
    #
    SHORTVER=$(echo ${VERSION} | awk -F '.' '{print $1"."$2}')
    TMPREL=$(echo ${TARFILE}| awk -F '-' '{print $4}')
    RELEASE=${TMPREL%.tar.gz}
    #
    export CFLAGS=$(rpm --eval %{optflags} | sed -e "s|march=i386|march=i686|g")
    export CXXFLAGS="${CFLAGS}"
    if [ "${YASSL}" = 0 ]; then
        if [ -f /etc/redhat-release ]; then
            SSL_VER_TMP=$(yum list installed|grep -i openssl|head -n1|awk '{print $2}'|awk -F "-" '{print $1}'|sed 's/\.//g'|sed 's/[a-z]$//')
            export SSL_VER=".ssl${SSL_VER_TMP}"
        else
            SSL_VER_TMP=$(dpkg -l|grep -i libssl|grep -v "libssl\-"|head -n1|awk '{print $2}'|awk -F ":" '{print $1}'|sed 's/libssl/ssl/g'|sed 's/\.//g')
            export SSL_VER=".${SSL_VER_TMP}"
        fi
    fi
    #
    rm -fr TARGET && mkdir TARGET
    rm -rf jemalloc 
    git clone https://github.com/jemalloc/jemalloc
    (
    cd jemalloc
    git checkout 3.6.0
    bash autogen.sh
    )
    #
    rm -fr ${TARFILE%.tar.gz}
    tar xzf ${TARFILE}
    cd ${TARFILE%.tar.gz}
    if [ "${YASSL}" = 1 ]; then
        DIRNAME="tarball_yassl"
        bash -xe ./build-ps/build-binary.sh --with-jemalloc=../jemalloc/ --with-yassl ../TARGET
    else
        bash -xe ./build-ps/build-binary.sh --with-jemalloc=../jemalloc/ ../TARGET
        DIRNAME="tarball"
    fi
    mkdir -p ${WORKDIR}/${DIRNAME}
    mkdir -p ${CURDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${WORKDIR}/${DIRNAME}
    cp ../TARGET/*.tar.gz ${CURDIR}/${DIRNAME}
}

#main

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/percona-server-5.5.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REVISION=0
BRANCH="5.5"
YASSL=0
REPO="git://github.com/percona/percona-server.git"
PRODUCT=Percona-Server-5.5
MYSQL_VERSION_MAJOR=5
MYSQL_VERSION_MINOR=5
MYSQL_VERSION_PATCH=60
MYSQL_VERSION_EXTRA=-38.12
RODUCT_FULL=Percona-Server-5.5.60-38.12
parse_arguments PICK-ARGS-FROM-ARGV "$@"
if [ ${YASSL} = 1 ]; then
  TARBALL=1
fi

check_workdir
get_system
install_deps
get_sources
build_tarball
build_srpm
build_source_deb
build_rpm
build_deb

