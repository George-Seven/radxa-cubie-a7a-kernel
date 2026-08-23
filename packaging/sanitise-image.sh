#!/bin/bash
# sanitise-image.sh SRC OUT SECRET
#
# v2 changes over clean_rebuild.sh:
#   - installs /usr/local/bin/a7a-reset-identity into the image
#   - GATE is corrected. v1 grepped the raw image for "BEGIN PRIVATE KEY" and
#     "klipper" and failed on 18/27/1851 hits - but ssh-keygen and libcrypto
#     contain those PEM headers as literal strings because they WRITE them, and
#     klipper is a KDE package the image is supposed to ship. Those patterns
#     cannot distinguish a key file from a program that knows what a key looks
#     like. So: byte-grep only for strings that can never legitimately appear
#     (the SSID, the marker), and check for credentials STRUCTURALLY by looking
#     for actual files.
set -euo pipefail

SRC=${1:?usage: sanitise-image.sh SRC OUT SECRET}
OUT=${2:?usage: sanitise-image.sh SRC OUT SECRET}
SECRET=${3:?usage: sanitise-image.sh SRC OUT SECRET}
# a7a-reset-identity to install into the image; defaults to the copy in this
# repo so the script works from a fresh clone.
TOOL=${TOOL:-"$(cd "$(dirname "$0")/.." && pwd)/tools/a7a-reset-identity"}
M=/tmp/cr_src
msg(){ echo; echo "=== $*"; }

[ -f "$TOOL" ] || { echo "missing $TOOL"; exit 1; }

msg "[1/8] clean the source tree"
LS=$(losetup -f --show -P "$SRC")
trap 'umount "$M" 2>/dev/null||true; umount /tmp/cr_out 2>/dev/null||true; losetup -D 2>/dev/null||true' EXIT
mkdir -p "$M" && mount "${LS}p3" "$M"
H="$M/home/radxa"

rm -f  "$M"/etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true
rm -rf "$M"/var/lib/NetworkManager/* 2>/dev/null || true
rm -f  "$M"/etc/wpa_supplicant/wpa_supplicant*.conf 2>/dev/null || true
rm -rf "$H"/.ssh "$M"/root/.ssh 2>/dev/null || true
rm -f  "$M"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -f  "$M"/etc/ssl/private/ssl-cert-snakeoil.key "$M"/etc/ssl/certs/ssl-cert-snakeoil.pem 2>/dev/null || true
rm -rf "$H"/.config "$H"/.local "$H"/.cache "$H"/.pki "$H"/.gnupg "$H"/.mozilla 2>/dev/null || true
rm -f  "$H"/.bash_history "$H"/.python_history "$H"/.gitconfig "$H"/.git-credentials \
       "$H"/.netrc "$H"/.wget-hsts "$H"/.lesshst "$H"/.viminfo "$H"/.Xauthority 2>/dev/null || true
rm -f  "$M"/root/.bash_history "$M"/root/.viminfo 2>/dev/null || true
rm -rf "$M"/root/.cache "$M"/root/.config "$M"/root/.local 2>/dev/null || true
for d in Downloads Desktop Documents Pictures Videos Music; do
    [ -d "$H/$d" ] && find "$H/$d" -mindepth 1 -delete 2>/dev/null || true
done
for d in debian12-backup debian13-backup pre-upgrade-backup overclocked-backup; do
    rm -rf "$M/root/$d" 2>/dev/null || true
done
for f in donor_fw.img fw_backup_pre2400_20260811.img target_fw_backup_20260810.img \
         pvr-userspace-24.2.6603887.tar.gz official-usr-local-lib.tar.gz \
         bench_results.txt gl2.txt gl3.txt glmark.txt; do
    rm -f "$M/root/$f" 2>/dev/null || true
done
: > "$M/etc/machine-id"; rm -f "$M/var/lib/dbus/machine-id"
rm -rf "$M"/var/log/journal/* 2>/dev/null || true
find "$M/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -rf "$M"/var/tmp/* "$M"/tmp/* 2>/dev/null || true
rm -rf "$M"/var/lib/fwupd/pki 2>/dev/null || true   # per-machine fwupd client key
echo "   profile reset; /root: $(ls -A "$M/root" | tr '\n' ' ')"

msg "[2/8] install a7a-reset-identity + first-boot identity unit"
install -m755 "$TOOL" "$M/usr/local/bin/a7a-reset-identity"
cat > "$M/etc/systemd/system/firstboot-identity.service" <<'SVC'
[Unit]
Description=Generate this board's own host identity on first boot
Before=ssh.service
ConditionPathExistsGlob=!/etc/ssh/ssh_host_ed25519_key
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/ssh-keygen -A
ExecStart=-/usr/sbin/make-ssl-cert generate-default-snakeoil --force-overwrite
[Install]
WantedBy=multi-user.target
SVC
mkdir -p "$M/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/firstboot-identity.service \
       "$M/etc/systemd/system/multi-user.target.wants/firstboot-identity.service"
rm -f "$M/etc/systemd/system/firstboot-sshkeys.service" \
      "$M/etc/systemd/system/multi-user.target.wants/firstboot-sshkeys.service" 2>/dev/null || true
echo "   /usr/local/bin/a7a-reset-identity + firstboot-identity.service installed"
sync; umount "$M"

msg "[3/8] copy image shell (GPT, boot0, p1, p2 verbatim)"
cp --sparse=always "$SRC" "$OUT"

LO=$(losetup -f --show -P "$OUT")
msg "[4/8] virgin ext4 on the output"
UUID=$(blkid -s UUID -o value "${LS}p3")
LABEL=$(blkid -s LABEL -o value "${LS}p3" || echo rootfs)
mkfs.ext4 -q -F -U "$UUID" -L "$LABEL" -b 4096 -m 5 "${LO}p3"
echo "   uuid preserved: $UUID"

msg "[5/8] copy the surviving tree"
mkdir -p /tmp/cr_out
mount -o ro "${LS}p3" "$M"
mount "${LO}p3" /tmp/cr_out
rsync -aHAXx --numeric-ids -q /tmp/cr_src/ /tmp/cr_out/
echo "   entries: $(find /tmp/cr_out -xdev | wc -l)"

msg "[6/8] structural credential check (on the NEW filesystem, before unmount)"
bad=0
keyfiles=0
while IFS= read -r f; do
    head -c 64 "$f" 2>/dev/null | grep -qE -- "-----BEGIN [A-Z ]*PRIVATE KEY-----" || continue
    case "${f#/tmp/cr_out}" in /usr/share/*|/usr/lib/python*) continue ;; esac
    echo "   KEY FILE: ${f#/tmp/cr_out}"; keyfiles=$((keyfiles+1))
done < <(find /tmp/cr_out -xdev -type f -size -20k \
             \( -name '*.pem' -o -name '*.key' -o -name 'id_*' -o -name '*_key' \
                -o -name 'privateKey*' -o -name '*.priv' \) 2>/dev/null)
for p in /etc/ssh/ssh_host_rsa_key /etc/ssl/private/ssl-cert-snakeoil.key \
         /home/radxa/.ssh /home/radxa/.config/kdeconnect /home/radxa/.pki \
         /home/radxa/.gnupg /home/radxa/.local/share/klipper \
         /home/radxa/.local/share/kactivitymanagerd /home/radxa/.local/share/Trash \
         /root/.ssh /root/debian12-backup /root/debian13-backup /root/pre-upgrade-backup \n         /var/lib/fwupd/pki/secret.key; do
    [ -e "/tmp/cr_out$p" ] && { echo "   PRESENT: $p"; bad=1; }
done
nm=$(ls /tmp/cr_out/etc/NetworkManager/system-connections/ 2>/dev/null | wc -l)
dl=$(find /tmp/cr_out/home/radxa/Downloads -type f 2>/dev/null | wc -l)
mid=$(stat -c %s /tmp/cr_out/etc/machine-id 2>/dev/null || echo 0)
echo "   private key files outside /usr/share : $keyfiles"
echo "   nmconnection profiles               : $nm"
echo "   ~/Downloads files                   : $dl"
echo "   machine-id bytes                    : $mid"
echo "   reset tool installed                : $([ -x /tmp/cr_out/usr/local/bin/a7a-reset-identity ] && echo yes || echo NO)"
[ "$keyfiles" = 0 ] || bad=1
[ "$nm" = 0 ] || bad=1
[ "$dl" = 0 ] || bad=1
[ "$mid" = 0 ] || bad=1

chattr +i /tmp/cr_out/boot/extlinux/extlinux.conf 2>/dev/null \
  && echo "   extlinux.conf immutable restored" || echo "   WARNING: immutable not restored"
sync
umount "$M"; umount /tmp/cr_out
e2fsck -f -y "${LO}p3" >/dev/null 2>&1 || true
losetup -D; trap - EXIT

msg "[7/8] residue byte-scan (strings that can NEVER legitimately appear)"
n_ssid=$(grep -a -c -- "$SECRET" "$OUT" 2>/dev/null || true); n_ssid=${n_ssid:-0}
n_lm=$(grep -a -c -- "LM-Studio" "$OUT" 2>/dev/null || true); n_lm=${n_lm:-0}
printf "   %-24s %s\n" "wifi ssid" "$n_ssid"
printf "   %-24s %s\n" "LM-Studio" "$n_lm"
[ "$n_ssid" = "0" ] || bad=1
[ "$n_lm" = "0" ] || bad=1

msg "[8/8] verdict"
if [ "$bad" = 0 ]; then echo "GATE PASSED - $OUT"; else echo "GATE FAILED - do not publish"; exit 1; fi
