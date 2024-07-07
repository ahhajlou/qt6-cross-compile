#!/bin/bash

# https://wiki.qt.io/Cross-Compile_Qt_6_for_Raspberry_Pi

export RED="\e[31m"
export BOLDRED="\e[1;31m"
export GREEN="\e[32m"
export CYAN="\e[36m"
export ENDCOLOR="\e[0m"

export IPV4_REGEX='^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

export QT_SRC_DOWNLOAD_URL="https://download.qt.io/official_releases/qt/6.7/6.7.2/single/qt-everywhere-src-6.7.2.tar.xz"


function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 9 ]]; then
				echo "⚠️ Your version of Debian is not supported."
				echo ""
				echo "However, if you're using Debian >= 9 or unstable/testing then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported."
				echo ""
				echo "However, if you're using Ubuntu >= 16.04 or beta, then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/system-release ]]; then
		source /etc/os-release
		if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
			OS="fedora"
		fi
		if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
			OS="centos"
			if [[ $VERSION_ID -lt 7 ]]; then
				echo "⚠️ Your version of CentOS is not supported."
				echo ""
				echo "The script only support CentOS 7 and CentOS 8."
				echo ""
				exit 1
			fi
		fi
		if [[ $ID == "ol" ]]; then
			OS="oracle"
			if [[ ! $VERSION_ID =~ (8) ]]; then
				echo "Your version of Oracle Linux is not supported."
				echo ""
				echo "The script only support Oracle Linux 8."
				exit 1
			fi
		fi
		if [[ $ID == "amzn" ]]; then
			OS="amzn"
			if [[ $VERSION_ID != "2" ]]; then
				echo "⚠️ Your version of Amazon Linux is not supported."
				echo ""
				echo "The script only support Amazon Linux 2."
				echo ""
				exit 1
			fi
		fi
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2, Oracle Linux 8 or Arch Linux system"
		exit 1
	fi
}

function rasppbery_pi_ip_username_prompt() {
    echo ""
	echo "Raspberry Pi IP V4: "
	until [[ $RASPBERRY_PI_IP =~ $IPV4_REGEX ]]; do
		read -rp "IP V4: " RASPBERRY_PI_IP
	done

    echo ""
    echo "Raspberry Pi Username: "
    until [[ $RASPBERRY_PI_USERNAME != "" ]]; do
        read -rp "Username: " RASPBERRY_PI_USERNAME
    done
}



if [ "$EUID" -eq 0 ]; then
    echo -e "${BOLDRED}You should not execute this script as root${ENDCOLOR}"
    exit 1
fi

checkOS
if [[ "$OS" == "ubuntu" && ( MAJOR_UBUNTU_VERSION -eq 20 || MAJOR_UBUNTU_VERSION -eq 22 ) ]]; then
    echo -e "${GREEN}Your Linux distro and version is ok${ENDCOLOR}"
else
    echo -e "${BOLDRED}Your Linux distro and version is not match with the criteria${ENDCOLOR}"
    exit 1
fi

rasppbery_pi_ip_username_prompt

if [[ -d ~/qt6 ]]; then
    echo -e "${BOLDRED}$(realpath qt6) exists${ENDCOLOR}"
    exit 4
fi


mkdir ~/qt6
export BULD_DIR_PATH=$(realpath ~/qt6)


function check_ip_connectivity() {
    ping -c 5 "$RASPBERRY_PI_IP" &> /dev/null
    return "$?"
}

echo -e "${GREEN}Check raspberry pi connectivity${ENDCOLOR}"
check_ip_connectivity
if [[ "$?" -ne 0 ]]; then
    echo -e "${BOLDRED}Can not ping raspberry pi${ENDCOLOR}"
    exit 2
fi


# Generate ssh key and copy it to raspberry pi
cd "$BULD_DIR_PATH" || exit 1

if [[ ! -f "$BULD_DIR_PATH"/tmp/sshkey ]]; then
    echo -e "${GREEN}Generate temporary ssh key${ENDCOLOR}"
    mkdir tmp
    ssh-keygen -b 2048 -t rsa -f "$BULD_DIR_PATH"/tmp/sshkey -q -N ""
    echo 'iam here'
    if [[ "$?" -ne 0 ]]; then
        echo -e "${BOLDRED}Failed to create ssh key${ENDCOLOR}"
        exit 3
    fi
fi

echo -e "${GREEN}Copy ssh ket to raspberry pi${ENDCOLOR}"
ssh-copy-id -f -i "$BULD_DIR_PATH"/tmp/sshkey.pub "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP"
if [[ "$?" -ne 0 ]]; then
    echo -e "${BOLDRED}ssh-copy-id exited${ENDCOLOR}"
    exit 2
fi





# Update and upgarde raspberry pi
echo -e "${GREEN}Update and upgrade raspberry pi${ENDCOLOR}"
ssh -i $BULD_DIR_PATH/tmp/sshkey "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP" -C "sudo apt-get update && sudo apt-get full-upgrade -y && sudo reboot"
if [[ "$?" -ne 0 ]]; then
    echo -e "${BOLDRED}Remote ssh command execution is failed${ENDCOLOR}"
    exit 2
fi


echo -e "${CYAN}Raspberry pi is rebooted${ENDCOLOR}"

# wait until reboot command is successfully done
sleep 10
raspberry_pi_is_up="0"
for count in {1..20}; do
    echo -e "${CYAN}Checking if raspberry pi is up...${ENDCOLOR}"
    ping -c 1 "$RASPBERRY_PI_IP" &>/dev/null
    if [[ "$?" -eq 0 ]]; then
        raspberry_pi_is_up="1"
        break
    fi
    sleep 1
done

if [[ "$raspberry_pi_is_up" -eq 0 ]]; then
    echo -e "${BOLDRED}Raspbeery pi was not booted in the specified duration${ENDCOLOR}"
    exit 6
fi





# Install necessary dependencies on raspberry pi
echo -e "${GREEN}Install necessary dependencies${ENDCOLOR}"
ssh -i $BULD_DIR_PATH/tmp/sshkey "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP" -C "sudo apt-get install -y libboost-all-dev libudev-dev libinput-dev libts-dev libmtdev-dev libjpeg-dev libfontconfig1-dev libssl-dev libdbus-1-dev libglib2.0-dev libxkbcommon-dev libegl1-mesa-dev libgbm-dev libgles2-mesa-dev mesa-common-dev libasound2-dev libpulse-dev gstreamer1.0-omx libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev  gstreamer1.0-alsa libvpx-dev libsrtp2-dev libsnappy-dev libnss3-dev "^libxcb.*" flex bison libxslt-dev ruby gperf libbz2-dev libcups2-dev libatkmm-1.6-dev libxi6 libxcomposite1 libfreetype6-dev libicu-dev libsqlite3-dev libxslt1-dev"
if [[ "$?" -ne 0 ]]; then
    echo -e "${BOLDRED}Remote ssh command execution is failed${ENDCOLOR}"
    exit 2
fi

# Install necessary dependencies on raspberry pi
echo -e "${GREEN}Install necessary dependencies${ENDCOLOR}"
ssh -i $BULD_DIR_PATH/tmp/sshkey "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP" -C "sudo apt-get install -y libavcodec-dev libavformat-dev libswscale-dev libx11-dev freetds-dev libsqlite3-dev libpq-dev libiodbc2-dev firebird-dev libxext-dev libxcb1 libxcb1-dev libx11-xcb1 libx11-xcb-dev libxcb-keysyms1 libxcb-keysyms1-dev libxcb-image0 libxcb-image0-dev libxcb-shm0 libxcb-shm0-dev libxcb-icccm4 libxcb-icccm4-dev libxcb-sync1 libxcb-sync-dev libxcb-render-util0 libxcb-render-util0-dev libxcb-xfixes0-dev libxrender-dev libxcb-shape0-dev libxcb-randr0-dev libxcb-glx0-dev libxi-dev libdrm-dev libxcb-xinerama0 libxcb-xinerama0-dev libatspi2.0-dev libxcursor-dev libxcomposite-dev libxdamage-dev libxss-dev libxtst-dev libpci-dev libcap-dev libxrandr-dev libdirectfb-dev libaudio-dev libxkbcommon-x11-dev"
if [[ "$?" -ne 0 ]]; then
    echo -e "${BOLDRED}Remote ssh command execution is failed${ENDCOLOR}"
    exit 2
fi


# >>>>>>> Error when trying install libgst-dev on raspbian bookworm on raspberry pi 5
# # Install necessary dependencies on raspberry pi
# echo -e "${GREEN}Install necessary dependencies${ENDCOLOR}"
# ssh -i $BULD_DIR_PATH/tmp/sshkey "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP" -C "sudo apt-get install -y libgst-dev"
# if [[ "$?" -ne 0 ]]; then
#     echo -e "${BOLDRED}Remote ssh command execution is failed${ENDCOLOR}"
#     exit 2
# fi





# Set exit variable -- not sure
set -e

echo -e "${GREEN}Execute apt-get update${ENDCOLOR}"
sudo apt-get update || exit 5
echo -e "${GREEN}Execute apt-get upgrade${ENDCOLOR}"
sudo apt-get upgrade -y || exit 5


# Create directories on host
echo -e "${GREEN}Create necessary directories on host${ENDCOLOR}"
cd "$BULD_DIR_PATH" || exit 1
mkdir rpi-sysroot rpi-sysroot/usr rpi-sysroot/opt
mkdir qt-host qt-raspi qt-hostbuild qtpi-build

# Install dependencies on host
echo -e "${GREEN}Install dependency on host${ENDCOLOR}"
sudo apt-get install -y make cmake build-essential libclang-dev clang ninja-build gcc git bison python3 gperf pkg-config libfontconfig1-dev libfreetype6-dev libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxi-dev libxrender-dev libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev libxcb-image0-dev libxcb-shm0-dev libxcb-icccm4-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev libxcb-randr0-dev libxcb-render-util0-dev libxcb-util-dev libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev libatspi2.0-dev libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev
sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
sudo apt-get install -y rsync
sudo apt-get install -y symlinks

# Building Sysroot from Raspberry Pi Device
echo -e "${GREEN}Building Sysroot from Raspberry Pi Device${ENDCOLOR}"
cd "$BULD_DIR_PATH" || exit 1

# unset exit flag temporarly because of
set +e
rsync -avzS --rsync-path="rsync" -e "ssh -i $BULD_DIR_PATH/tmp/sshkey" --delete "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP":/lib/* rpi-sysroot/lib
mkdir "$BULD_DIR_PATH"/rpi-sysroot/usr
rsync -avzS --rsync-path="rsync" -e "ssh -i $BULD_DIR_PATH/tmp/sshkey" --delete "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP":/usr/include/* rpi-sysroot/usr/include
rsync -avzS --rsync-path="rsync" -e "ssh -i $BULD_DIR_PATH/tmp/sshkey" --delete "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP":/usr/lib/* rpi-sysroot/usr/lib


# executable on the Raspberry Pi. Note: Your Raspberry Pi might not have a directory named 
# , and it is fine. Usually this directory contains proprietary Broadcom libraries, 
# but during the testing the author did not find any issue with the lack of this directory
mkdir "$BULD_DIR_PATH"/rpi-sysroot/opt

 

rsync -avzS --rsync-path="rsync" -e "ssh -i $BULD_DIR_PATH/tmp/sshkey" --delete "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP":/opt/vc rpi-sysroot/opt/vc
set -e

# Fix symlinks
echo -e "${GREEN}Fix symlinks${ENDCOLOR}"
symlinks -rc rpi-sysroot

# Download Qt source
echo -e "${GREEN}Downloading Qt source${ENDCOLOR}"
cd "$BULD_DIR_PATH" || exit 1
qt_src_file_name=$(echo "$QT_SRC_DOWNLOAD_URL" | awk -F'/' '{print $NF}')
wget -O "$qt_src_file_name" "$QT_SRC_DOWNLOAD_URL"
tar xf "$qt_src_file_name"

qt_src_dir="${qt_src_file_name%.tar.xz}"
# Build Qt on host
echo -e "${GREEN}Build Qt on host${ENDCOLOR}"
cd "$BULD_DIR_PATH"/qt-hostbuild/
cmake ../"$qt_src_dir" -GNinja -DCMAKE_BUILD_TYPE=Release -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX="$BULD_DIR_PATH"/qt-host
cmake --build . --parallel $(nproc)
cmake --install .

# Create a Toolchain File
echo -e "${GREEN}Create toolchain file${ENDCOLOR}"
cat<<EOF >"$BULD_DIR_PATH"/toolchain.cmake
cmake_minimum_required(VERSION 3.18)
include_guard(GLOBAL)

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(TARGET_SYSROOT $BULD_DIR_PATH/rpi-sysroot)
set(CMAKE_SYSROOT \${TARGET_SYSROOT})

set(ENV{PKG_CONFIG_PATH} \$PKG_CONFIG_PATH:/usr/lib/aarch64-linux-gnu/pkgconfig)
set(ENV{PKG_CONFIG_LIBDIR} /usr/lib/pkgconfig:/usr/share/pkgconfig/:\${TARGET_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:\${TARGET_SYSROOT}/usr/lib/pkgconfig)
set(ENV{PKG_CONFIG_SYSROOT_DIR} \${CMAKE_SYSROOT})

# if you use other version of gcc and g++ than gcc/g++ 9, you must change the following variables
set(CMAKE_C_COMPILER /usr/bin/aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER /usr/bin/aarch64-linux-gnu-g++)

set(CMAKE_C_FLAGS "\${CMAKE_C_FLAGS} -I\${TARGET_SYSROOT}/usr/include")
set(CMAKE_CXX_FLAGS "\${CMAKE_C_FLAGS}")

set(QT_COMPILER_FLAGS "-march=armv8-a")
set(QT_COMPILER_FLAGS_RELEASE "-O2 -pipe")

#set(QT_LINKER_FLAGS "-Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed")
set(QT_LINKER_FLAGS "-Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed -ldbus-1")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
set(CMAKE_BUILD_RPATH \${TARGET_SYSROOT})


include(CMakeInitializeConfigs)

function(cmake_initialize_per_config_variable _PREFIX _DOCSTRING)
  if (_PREFIX MATCHES "CMAKE_(C|CXX|ASM)_FLAGS")
    set(CMAKE_\${CMAKE_MATCH_1}_FLAGS_INIT "\${QT_COMPILER_FLAGS}")
        
    foreach (config DEBUG RELEASE MINSIZEREL RELWITHDEBINFO)
      if (DEFINED QT_COMPILER_FLAGS_\${config})
        set(CMAKE_\${CMAKE_MATCH_1}_FLAGS_\${config}_INIT "\${QT_COMPILER_FLAGS_\${config}}")
      endif()
    endforeach()
  endif()


  if (_PREFIX MATCHES "CMAKE_(SHARED|MODULE|EXE)_LINKER_FLAGS")
    foreach (config SHARED MODULE EXE)
      set(CMAKE_\${config}_LINKER_FLAGS_INIT "\${QT_LINKER_FLAGS}")
    endforeach()
  endif()

  _cmake_initialize_per_config_variable(\${ARGV})
endfunction()

set(XCB_PATH_VARIABLE \${TARGET_SYSROOT})

set(GL_INC_DIR \${TARGET_SYSROOT}/usr/include)
set(GL_LIB_DIR \${TARGET_SYSROOT}:\${TARGET_SYSROOT}/usr/lib/aarch64-linux-gnu/:\${TARGET_SYSROOT}/usr:\${TARGET_SYSROOT}/usr/lib)

set(EGL_INCLUDE_DIR \${GL_INC_DIR})
set(EGL_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libEGL.so)

set(OPENGL_INCLUDE_DIR \${GL_INC_DIR})
set(OPENGL_opengl_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libOpenGL.so)

set(GLESv2_INCLUDE_DIR \${GL_INC_DIR})
set(GLESv2_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libGLESv2.so)

set(gbm_INCLUDE_DIR \${GL_INC_DIR})
set(gbm_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libgbm.so)

set(Libdrm_INCLUDE_DIR \${GL_INC_DIR})
set(Libdrm_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libdrm.so)

set(XCB_XCB_INCLUDE_DIR \${GL_INC_DIR})
set(XCB_XCB_LIBRARY \${XCB_PATH_VARIABLE}/usr/lib/aarch64-linux-gnu/libxcb.so)
EOF


# Not tested
cd "$BULD_DIR_PATH"/rpi-sysroot/usr/lib/aarch64-linux-gnu
unlink libdbus-1.so
# exact version of library may be changed
ln -s libdbus-1.so.3.32.4 libdbus-1.so
# ----------

# Build Qt for raspberry pi on host
echo -e "${GREEN}Build and cross compile Qt for raspberry pi${ENDCOLOR}"
cd "$BULD_DIR_PATH"/qtpi-build
cmake ../"$qt_src_dir"  -GNinja -DCMAKE_BUILD_TYPE=Release -DINPUT_opengl=es2 -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DQT_HOST_PATH="$BULD_DIR_PATH"/qt-host -DCMAKE_STAGING_PREFIX="$BULD_DIR_PATH"/qt-raspi -DCMAKE_INSTALL_PREFIX=/usr/local/qt6 -DCMAKE_TOOLCHAIN_FILE="$BULD_DIR_PATH"/toolchain.cmake -DQT_QMAKE_TARGET_MKSPEC=devices/linux-rasp-pi4-aarch64 -DQT_FEATURE_xcb=ON -DFEATURE_xcb_xlib=ON -DQT_FEATURE_xlib=ON
cmake --build . --parallel $(nproc)
cmake --install .

echo -e "${GREEN}Copy compiled files to raspberry pi${ENDCOLOR}"
rsync -avz --rsync-path="sudo rsync" -e "ssh -i $BULD_DIR_PATH/tmp/sshkey" "$BULD_DIR_PATH"/qt-raspi/* "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP":/usr/local/qt6

# Set LD_LIBRARY_PATH Environment variable in .bashrc on raspberry pi
ssh -i $BULD_DIR_PATH/tmp/sshkey "$RASPBERRY_PI_USERNAME"@"$RASPBERRY_PI_IP" -C 'bash -c "echo '\''export LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}:/usr/local/qt6/lib/'\'' >> ~/.bashrc"'