#!/bin/bash
###Autor: Li Guoqiang from VMware China. ###
###install cloud-init. ### 
yum install -y cloud-init
###System Update###
yum update -y

###eanble root and password login for ssh. ###
sudo sed -i 's/^disable_root: 1/disable_root: 0/g' /etc/cloud/cloud.cfg
sudo sed -i 's/^ssh_pwauth:   0/ssh_pwauth:   1/g' /etc/cloud/cloud.cfg

###disable vmware customization for cloud-init. ###
sed -i 's/^disable_vmware_customization: false/disable_vmware_customization: true/g' /etc/cloud/cloud.cfg
###setting datasouce is OVF only. ### 
sed -i '/^disable_vmware_customization: true/a\datasource_list: [OVF]' /etc/cloud/cloud.cfg
###disalbe clean tmp folder. ### 
SOURCE_TEXT="v /tmp 1777 root root 10d"
DEST_TEXT="#v /tmp 1777 root root 10d"
sudo sed -i "s@${SOURCE_TEXT}@${DEST_TEXT}@g" /usr/lib/tmpfiles.d/tmp.conf
sed -i "s/\(^.*10d.*$\)/#\1/" /usr/lib/tmpfiles.d/tmp.conf
###Add After=dbus.service to vmtoolsd. ### 
sed -i '/^After=vgauthd.service/a\After=dbus.service' /usr/lib/systemd/system/vmtoolsd.service

###disable cloud-init in first boot,we use vmware tools exec customization. ### 
touch /etc/cloud/cloud-init.disabled

###Create a runonce script for re-exec cloud-init. ###
cat <<EOF > /etc/cloud/runonce.sh
#!/bin/bash

if [ -e /tmp/guest.customization.stderr ]
then
  sudo rm -rf /etc/cloud/cloud-init.disabled
  sudo systemctl restart cloud-init.service
  sudo systemctl restart cloud-config.service
  sudo systemctl restart cloud-final.service
  sudo systemctl disable runonce
  sudo touch /tmp/cloud-init.success
fi

exit
EOF

###Create a runonce service for exec runonce.sh with system after reboot. ### 
cat <<EOF > /etc/systemd/system/runonce.service
[Unit]
Description=Run once
Requires=network-online.target
Requires=cloud-init-local.sevice
After=network-online.target
After=cloud-init-local.service

[Service]
###wait for vmware customization to complete, avoid executing cloud-init at the first startup.###
ExecStartPre=/bin/sleep 10
ExecStart=/etc/cloud/runonce.sh

[Install]
WantedBy=multi-user.target
EOF
###Create a cleanup script for build vra template. ### 
cat <<EOF > /etc/cloud/clean.sh
#!/bin/bash

#clear audit logs
if [ -f /var/log/audit/audit.log ]; then
cat /dev/null > /var/log/audit/audit.log
fi
if [ -f /var/log/wtmp ]; then
cat /dev/null > /var/log/wtmp
fi
if [ -f /var/log/lastlog ]; then
cat /dev/null > /var/log/lastlog
fi

#cleanup persistent udev rules
if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
rm /etc/udev/rules.d/70-persistent-net.rules
fi

#cleanup /tmp directories
rm -rf /tmp/*
rm -rf /var/tmp/*

#cleanup current ssh keys
#rm -f /etc/ssh/ssh_host_*

#cat /dev/null > /etc/hostname

#cleanup apt
yum clean all

#Clean Machine ID

truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

#Clean Cloud-init
cloud-init clean --logs --seed

#Disabled Cloud-init
touch /etc/cloud/cloud-init.disabled

#cleanup shell history
echo > ~/.bash_history
history -cw
EOF
###change script execution permissions. ### 
chmod +x /etc/cloud/runonce.sh /etc/cloud/clean.sh
###reload runonce.service. ### 
systemctl deamon-reload
###enable runonce.service on system boot. ### 
systemctl enable runonce.service
###clean template. ### 
/etc/cloud/clean.sh
###shutdown os. ###
Shutdown -h now


