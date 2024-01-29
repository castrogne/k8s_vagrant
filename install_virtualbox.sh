#!/bin/bash
# Oracle Repository
# Download and install .asc
wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor | tee /usr/share/keyrings/virtualbox.gpg &> /dev/null
# add repo
echo deb [arch=amd64 signed-by=/usr/share/keyrings/virtualbox.gpg] http://download.virtualbox.org/virtualbox/debian $(lsb_release -sc) contrib | tee /etc/apt/sources.list.d/virtualbox.list/virtualbox.list
apt update
# install vbox
apt -y install linux-headers-$(uname -r) build-essential gcc make perl dkms bridge-utils
apt -y install virtualbox-6.1
dpkg --configure -a && apt-get -f -y install
# install Extension Pack
export VBOX_VER=`VBoxManage --version | awk -Fr '{print $1}'`
wget -c http://download.virtualbox.org/virtualbox/$VBOX_VER/Oracle_VM_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
VBoxManage extpack install Oracle_VM_VirtualBox_Extension_Pack-$VBOX_VER.vbox-extpack
# configure
usermod -a -G vboxusers $USER
update-grub
/sbin/vboxconfig
echo "Done. Reboot"
# check service after reboot
systemctl status vboxdrv
