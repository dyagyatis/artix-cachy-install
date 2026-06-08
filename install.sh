#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
   echo "Запусти скрипт от root!"
   exit 1
fi

echo "=== Доступные диски ==="
lsblk -do NAME,SIZE,MODEL
echo "========================"
read -p "Введите имя диска для установки (например, nvme0n1 или sda): " TARGET_DISK_NAME
TARGET_DISK="/dev/$TARGET_DISK_NAME"

if [[ ! -b "$TARGET_DISK" ]]; then
    echo "Ошибка: Диск $TARGET_DISK не найден."
    exit 1
fi

read -p "ВНИМАНИЕ: Все данные на $TARGET_DISK будут УДАЛЕНЫ. Продолжить? (y/n): " confirm
if [[ $confirm != "y" ]]; then exit 1; fi

read -p "Введите имя пользователя: " MY_USER

echo "=== [0/6] Авто-разметка $TARGET_DISK ==="
umount -R /mnt 2>/dev/null || true

# Определяем, как называть разделы (для NVMe — p1, для SATA — 1)
if [[ "$TARGET_DISK_NAME" == nvme* ]]; then
    PART1="${TARGET_DISK}p1"
    PART2="${TARGET_DISK}p2"
else
    PART1="${TARGET_DISK}1"
    PART2="${TARGET_DISK}2"
fi

parted -s $TARGET_DISK mklabel gpt
parted -s $TARGET_DISK mkpart primary fat32 1MiB 513MiB
parted -s $TARGET_DISK set 1 esp on
parted -s $TARGET_DISK mkpart primary ext4 513MiB 100%

mkfs.fat -F 32 $PART1
mkfs.ext4 -F $PART2

mount $PART2 /mnt
mount --mkdir $PART1 /mnt/boot

echo "=== [1/6] Авто-создание зеркал ==="
mkdir -p /mnt/etc/pacman.d

cat <<EOF > /mnt/etc/pacman.d/artix-mirrorlist
## --- Artix Linux Repositories ---
## Russia
Server = https://mirrors.yuruyuri.fun/artix-linux/repos/\$repo/os/\$arch
## Japan
Server = https://www.miraa.jp/artix-linux/\$repo/os/\$arch
## Germany
Server = https://mirror.netcologne.de/artix-linux/\$repo/os/\$arch
EOF

cat <<EOF > /mnt/etc/pacman.d/cachyos-mirrorlist
## --- CachyOS Repositories ---
## Russia
Server = https://mirror.cachy-arch.ru/cachyos/repo/\$arch/\$repo
Server = https://mirror.jura12.ru/repo/\$arch/\$repo
Server = https://wan.metrosg.ru/cachyos/repo/\$arch/\$repo
Server = https://archlinux.gay/cachy/repo/\$arch/\$repo
## China
Server = https://mirror.nju.edu.cn/cachyos/repo/\$arch/\$repo
Server = https://mirrors.ustc.edu.cn/cachyos/repo/\$arch/\$repo
## South Korea
Server = https://mirror.krfoss.org/cachyos/repo/\$arch/\$repo
EOF

cat <<EOF > /tmp/artix.conf
[options]
Architecture = auto
SigLevel = TrustAll
[system]
Include = /mnt/etc/pacman.d/artix-mirrorlist
[world]
Include = /mnt/etc/pacman.d/artix-mirrorlist
[galaxy]
Include = /mnt/etc/pacman.d/artix-mirrorlist
EOF

echo "=== [2/6] Установка базы ==="
pacstrap -C /tmp/artix.conf /mnt base base-devel runit elogind-runit dbus-runit linux linux-firmware neovim networkmanager-runit artix-archlinux-support
genfstab -U /mnt >> /mnt/etc/fstab

echo "=== [3/6] Настройка Chroot ==="
cat << 'CHROOT_EOF' > /mnt/tmp/chroot_setup.sh
#!/bin/bash
set -e
ln -sf /usr/share/zoneinfo/Asia/Tomsk /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "artix-pc" > /etc/hostname

pacman-key --init
pacman-key --populate artix
pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
pacman-key --lsign-key F3B607488DB35A47
pacman -Sy cachyos-keyring --noconfirm

cat <<EOF >> /etc/pacman.conf
[lib32]
Include = /etc/pacman.d/artix-mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist-arch
[multilib]
Include = /etc/pacman.d/mirrorlist-arch
[cachyos-v3]
Include = /etc/pacman.d/cachyos-mirrorlist
[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-mirrorlist
[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-mirrorlist
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF

pacman -Sy --noconfirm
pacman -S cachyos/linux-cachyos-eevdf cachyos/linux-cachyos-eevdf-headers cachyos/nvidia-utils cachyos/lib32-nvidia-utils cachyos/linux-cachyos-eevdf-nvidia-open --noconfirm
pacman -Rns linux --noconfirm
sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P

pacman -S grub efibootmgr --noconfirm
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

pacman -S niri kitty xdg-desktop-portal-wlr pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol bluez bluez-utils bluez-runit polkit-gnome wl-clipboard cliphist flatpak xdg-desktop-portal xdg-desktop-portal-gtk --noconfirm
ln -s /etc/runit/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/runit/sv/elogind /etc/runit/runsvdir/default/
ln -s /etc/runit/sv/NetworkManager /etc/runit/runsvdir/default/
ln -s /etc/runit/sv/bluetoothd /etc/runit/runsvdir/default/

useradd -m -G wheel,video,audio,input -s /bin/bash "$1"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
CHROOT_EOF

chmod +x /mnt/tmp/chroot_setup.sh
arch-chroot /mnt /bin/bash /tmp/chroot_setup.sh "$MY_USER"

echo "=== [4/6] Пароли ==="
arch-chroot /mnt passwd root
arch-chroot /mnt passwd "$MY_USER"

echo "=== [5/6] Очистка ==="
rm -f /mnt/tmp/chroot_setup.sh
echo "ГОТОВО! Перезагружайся."