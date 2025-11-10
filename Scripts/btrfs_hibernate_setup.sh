#!/usr/bin/env bash
set -euo pipefail

# ---- CONFIG ----
SWAP_SIZE="8G" # You can adjust or auto-detect (see notes below)
SWAP_SUBVOL="/swap"
SWAP_FILE="${SWAP_SUBVOL}/swapfile"

# ---- PRECHECKS ----
[[ $EUID -eq 0 ]] || {
    echo "❌ Must be run as root."
    exit 1
}

for cmd in btrfs blkid swapon grep sed awk; do
    command -v "$cmd" >/dev/null || {
        echo "❌ Missing dependency: $cmd"
        exit 1
    }
done

ROOT_DEV=$(findmnt -no SOURCE /)
ROOT_FS=$(findmnt -no FSTYPE /)
[[ "$ROOT_FS" == "btrfs" ]] || {
    echo "❌ Root filesystem is not Btrfs."
    exit 1
}

echo "🧠 Root device: $ROOT_DEV"
echo "🧠 Swap subvolume: $SWAP_SUBVOL"
echo "🧠 Swap size: $SWAP_SIZE"

# ---- CREATE SUBVOLUME ----
if [[ ! -d "$SWAP_SUBVOL" ]]; then
    echo "📦 Creating Btrfs subvolume at $SWAP_SUBVOL..."
    btrfs subvolume create "$SWAP_SUBVOL"
else
    echo "ℹ️ Subvolume $SWAP_SUBVOL already exists."
fi

# ---- CREATE SWAPFILE ----
if [[ ! -f "$SWAP_FILE" ]]; then
    echo "💾 Creating swapfile using btrfs-progs..."
    btrfs filesystem mkswapfile --size "$SWAP_SIZE" "$SWAP_FILE"
else
    echo "ℹ️ Swapfile already exists."
fi

# ---- ENABLE SWAP ----
if ! swapon --show=NAME | grep -q "$SWAP_FILE"; then
    echo "⚙️ Enabling swap..."
    swapon "$SWAP_FILE"
else
    echo "ℹ️ Swap already active."
fi

# ---- ADD TO FSTAB ----
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "🧾 Adding swapfile to /etc/fstab..."
    echo "$SWAP_FILE none swap defaults 0 0" >>/etc/fstab
else
    echo "ℹ️ Swapfile already listed in /etc/fstab."
fi

# ---- GET UUID + OFFSET ----
UUID=$(blkid -s UUID -o value "$ROOT_DEV")
OFFSET=$(btrfs inspect-internal map-swapfile -r "$SWAP_FILE")

echo "🔍 Resume UUID: $UUID"
echo "🔍 Resume offset: $OFFSET"

# ---- UPDATE MKINITCPIO ----
if grep -q HOOKS /etc/mkinitcpio.conf && ! grep -q "resume" /etc/mkinitcpio.conf; then
    echo "🧩 Adding 'resume' hook to mkinitcpio.conf..."
    sed -i 's/\(filesystems\)/resume \1/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# ---- ADD KERNEL PARAMETERS ----
if [[ -f /etc/default/grub ]]; then
    echo "🧠 Updating GRUB kernel parameters..."
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
        line=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub)

        # Add resume UUID if missing
        if ! echo "$line" | grep -q "resume=UUID"; then
            sed -i "s|^\(GRUB_CMDLINE_LINUX=\"[^\"]*\)|\1 resume=UUID=$UUID|" /etc/default/grub
        fi

        # Add resume_offset if missing
        if ! echo "$line" | grep -q "resume_offset="; then
            sed -i "s|^\(GRUB_CMDLINE_LINUX=\"[^\"]*\)|\1 resume_offset=$OFFSET|" /etc/default/grub
        fi
    fi
    grub-mkconfig -o /boot/grub/grub.cfg

elif [[ -d /boot/loader/entries ]]; then
    echo "🧠 Updating systemd-boot entries..."
    for entry in /boot/loader/entries/*.conf; do
        if ! grep -q "resume=UUID" "$entry"; then
            echo "options resume=UUID=$UUID" >>"$entry"
        fi
        if ! grep -q "resume_offset=" "$entry"; then
            echo "options resume_offset=$OFFSET" >>"$entry"
        fi
    done
    bootctl update
fi

echo
echo "✅ Hibernate setup complete!"
echo "→ Test with: systemctl hibernate"
echo "→ If resume fails, verify kernel params: cat /proc/cmdline"
