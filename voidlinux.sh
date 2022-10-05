#!/bin/bash

#
# voidlinux.sh
#
# Void Linux installation helper script.
#
# Usage
#
#   bash < (curl https://raw.githubusercontent/${_USER}/dotfiles/voidlinux/src/voidlinux.sh)
#
# See also
#
#  - https://docs.voidlinux.org/installation/guides/fde.html
#  - https://docs.voidlinux.org/installation/guides/chroot.html
#

_APP_NAME="voidlinux-installer"

_SYSTEM_DISK=/dev/sda
_SYSTEM_LANG="en_US.UTF-8"
_SYSTEM_LOCALE="en_US.UTF-8 UTF-8"
_SYSTEM_NAME="voidlinux"
_SYSTEM_ROOT_PARTITION_SIZE_GB=64
_SYSTEM_SWAP_PARTITION_SIZE_GB=16
_SYSTEM_UEFI_BOOT="true"

_HOSTNAME="${_USER}-0"
_USER="${_USER}"

__prompt() {
  echo "Continue? "
  read _
}

_set_next() {
  local -r _next="${1:?}"
  echo "${_next}" > /tmp/${_APP_NAME}.dir/${_APP_NAME}.next
}

_get_next() {
  if [ -e /tmp/${_APP_NAME}.dir/${_APP_NAME}.next ]
  then
    echo $(cat /tmp/${_APP_NAME}.dir/${_APP_NAME}.next)
  elif [ "$(hostname)" == "void-live" ]
  then
    echo 1
  else
    echo 0
  fi
}

_step_B_0() {
  cat << EOF

        #######################
        ### ${_APP_NAME}.sh ###
        #######################

EOF
}

_step_B_1() {
  cat << EOF
  1. Download Void Linux at https://voidlinux.org/download/.
  2. Download balenaEtcher at https://www.balena.io/etcher/.
  3. Burn the Void Linux ISO to a bootable USB with Etcher.
  4. Boot using the USB and login with user 'root' and password 'voidlinux'.
  5. Run 
    # xbps-install -Syu xbps curl
    # mkdir -p /tmp/${_APP_NAME}.dir
    # curl <url> | tr -d '\r' > /tmp/${_APP_NAME}.dir/${_APP_NAME}.sh
    # chmod +x /tmp/${_APP_NAME}.dir/${_APP_NAME}.sh
    # /tmp/${_APP_NAME}.dir/${_APP_NAME}.sh
  ```
EOF
}

_step_B_2() {
    if [ "${_SYSTEM_UEFI_BOOT}" ]
    then
      cat << EOF
  1. Delete all partitions.
  2. Create one 128M primary partition.
  3. Mark the 128M partition as bootable.
  4. Create a primary partition with the remaining free space.
  5. Write, then quit.
EOF
  else 
    cat << EOF
  1. Delete all partitions.
  2. Create a primary partition with all free space.
  2. Write, then quit.
EOF
  fi
}

_step_A_3() {
  cfdisk ${_SYSTEM_DISK}
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then
    cryptsetup luksFormat --type luks1 ${_SYSTEM_DISK}2
    cryptsetup luksOpen ${_SYSTEM_DISK}2 ${_SYSTEM_NAME}
  else
    cryptsetup luksFormat --type luks1 ${_SYSTEM_DISK}1
    cryptsetup luksOpen ${_SYSTEM_DISK}1 ${_SYSTEM_NAME}
  fi
  vgcreate ${_SYSTEM_NAME} /dev/mapper/${_APP_NAME}
  lvcreate --name root -L ${_SYSTEM_ROOT_PARTITION_SIZE_GB}G ${_SYSTEM_NAME}
  lvcreate --name swap -L ${_SYSTEM_SWAP_PARTITION_SIZE_GB}G ${_SYSTEM_NAME}
  lvcreate --name home -l 100%FREE ${_SYSTEM_NAME}
  mkfs.xfs -L root /dev/${_SYSTEM_NAME}/root
  mkfs.xfs -L home /dev/${_SYSTEM_NAME}/home
  mkswap /dev/${_SYSTEM_NAME}/swap
  mount /dev/${_SYSTEM_NAME}/root /mnt
  for dir in dev proc sys run; do mkdir -p /mnt/$dir ; mount --rbind /$dir /mnt/$dir ; mount --make-rslave /mnt/$dir ; done
  mkdir -p /mnt/home
  mount /dev/${_SYSTEM_NAME}/home /mnt/home
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then 
    mkfs.vfat ${_SYSTEM_DISK}1
    mkdir -p /mnt/boot/efi
    mount ${_SYSTEM_DISK}1 /mnt/boot/efi 
  fi
  mkdir -p /mnt/var/db/xbps/keys
  cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
  xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt base-system cryptsetup lvm2 curl
  if [ "${_SYSTEM_UEFI_BOOT}" ] 
  then
    xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt grub-x86_64-efi
  else
    xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt grub
  fi
}

_step_B_4() {
  cp -r /tmp/${_APP_NAME}.dir /mnt/tmp/
}

_step_B_5() {
  cat << EOF
  1. Run 'chmod +x /tmp/${_APP_NAME}.dir/${_APP_NAME}.sh && /tmp/${_APP_NAME}.dir/${_APP_NAME}.sh'.
  1. Uncomment the line that contains '%wheel', then do <ESC>-:wq.
EOF
}

_step_A_6() {
  chroot /mnt
}

_step_A_7() {
  chown root:root /
  chmod 755 /
  passwd root
  echo ${_HOSTNAME} > /etc/hostname
  echo "LANG=${_SYSTEM_LANG}" > /etc/locale.conf
  echo "${_SYSTEM_LOCALE}" >> /etc/default/libc-locales
  xbps-reconfigure -f glibc-locales
cat > /etc/fstab << EOF
# <file system> <dir> <type> <options> <dump> <pass>
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
/dev/${_SYSTEM_NAME}/root / xfs defaults 0 0
/dev/${_SYSTEM_NAME}/home /home xfs defaults 0 0
/dev/${_SYSTEM_NAME}/swap swap swap defaults 0 0
EOF
  if [ "${_SYSTEM_UEFI_BOOT}" ] 
  then
    echo "${_SYSTEM_DISK}1 /boot/efi vfat defaults 0 0" >> /etc/fstab
  fi
  echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
  local _uuid=''
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then
    _uuid=`blkid -o value -s UUID ${_SYSTEM_DISK}2` 
  else
    _uuid=`blkid -o value -s UUID ${_SYSTEM_DISK}1`
  fi
  sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=4 rd.lvm.vg=${_SYSTEM_NAME} rd.luks.uuid=${_uuid}\"/" /etc/default/grub
  dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then
    cryptsetup luksAddKey ${_SYSTEM_DISK}2 /boot/volume.key
  else
    cryptsetup luksAddKey ${_SYSTEM_DISK}1 /boot/volume.key
  fi
  chmod 000 /boot/volume.key
  chmod -R g-rwx,o-rwx /boot
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then
    echo "${_SYSTEM_NAME} ${_SYSTEM_DISK}2 /boot/volume.key luks" >> /etc/crypttab 
  else
    echo "${_SYSTEM_NAME} ${_SYSTEM_DISK}1 /boot/volume.key luks" >> /etc/crypttab
  fi
  echo 'install_items+=" /boot/volume.key /etc/crypttab "' > /etc/dracut.conf.d/10-crypt.conf
  if [ "${_SYSTEM_UEFI_BOOT}" ]
  then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi
  else
    grub-install ${_SYSTEM_DISK}
  fi
  xbps-reconfigure -fa
  useradd -m -s $(which bash) ${_USER}
  usermod -aG wheel ${_USER}
  passwd ${_USER}
  visudo
  ln -sf /etc/sv/dhcpcd /var/service/
}

_step_B_8() {
  cat << EOF
  1. Wait for reboot, then login as root.
  2. Run 'su ${_USER}'.
  3. Run '/tmp/${_APP_NAME}.dir/${_APP_NAME}.sh'.
EOF
}

_step_A_9() {
  reboot
}

_actor_0() {
  _step_B_0
  _step_B_1
}

_actor_1() {
  _step_B_2
  __prompt
  _step_A_3
  _set_next 2
  _step_B_4
  _step_B_5
  _step_A_6
  __prompt
}

_actor_2() {
  _step_A_7
  _set_next 3
}

_actor_3() {
  _step_B_8
  __prompt
  _step_A_9
  _set_next 4
}

_actor_4() {
  sudo sv up dhcpcd
  sudo xbps-install -Syu \
    curl \
    dmenu \
    firefox \
    git \
    i3 \
    zsh \
    make \
    i3status \
    rxvt-unicode \
    xorg
  sudo usermod -aG input,tty,users,video ${_USER}
  sudo chsh --shell /usr/bin/zsh ${_USER}
  echo 'exec i3' > ~/.xinitrc
  ssh-keygen -o
  echo "git user.email="
  read _GIT_USER_NAME
  git config --global user.name "${_GIT_USER_NAME}"
  echo 'git user.name='
  read _GIT_USER_NAME
  git config --global user.email "${_GIT_USER_EMAIL}"
  _set_next 5
  _actor_5
  __prompt
  startx
}

_actor_5() {
  cat << EOF
    1. Get public SSH key with 'cat ~/.id_rsa.pub' 
    2. Add to git server, e.g. 'https://github.com/settings.keys'.
    3. Clone git repos, e.g. 'git clone --recursive git@github.com:${_USER}/root ~/Github/${_USER}/root'.
EOF
}

___main___() {
  mkdir -p /tmp/${_APP_NAME}.dir
  (
  set -ouex pipefail
  case $(_get_next) in 
    0)
      _actor_0
      ;;
    1)
      _actor_1
      ;;
    2)
      _actor_2
      ;;
    3)
      _actor_3
      ;;
    4)
      _actor_4
      ;;
    5)
      _actor_5
      ;;
  esac
  ) | tee /tmp/${_APP_NAME}.dir/$(date -Is).log
}

(___main___)
