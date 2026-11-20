### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties (kernel.string lo rellena ci/build.sh)
properties() { '
kernel.string=@KERNEL_STRING@
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=sapphire
device.name2=sapphiren
device.name3=
supported.versions=@KERNEL_MAJMIN@
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Compatibilidad real con la ROM instalada: cada módulo de vendor_dlkm/system_dlkm
# debe cargar con este kernel según la regla de CONFIG_MODVERSIONS (kernel/module.c:
# check_version/same_magic): mismo CRC por símbolo contra vmlinux.symvers de este Image.
# La versión de kernel (uname) no interviene: el kernel la ignora cuando hay CRC.
kmi_mnt=$AKHOME/kmi-mnt;
kmi_dirs="";
kmi_montados="";
for p in vendor_dlkm system_dlkm; do
  if [ -d /$p/lib/modules ]; then
    kmi_dirs="$kmi_dirs /$p/lib/modules";
    continue;
  fi;
  for dev in /dev/block/mapper/$p$SLOT /dev/block/mapper/$p; do
    [ -e "$dev" ] || continue;
    mkdir -p $kmi_mnt/$p;
    if mount -o ro -t auto "$dev" $kmi_mnt/$p 2>/dev/null; then
      kmi_montados="$kmi_montados $kmi_mnt/$p";
      kmi_dirs="$kmi_dirs $kmi_mnt/$p/lib/modules";
      break;
    fi;
  done;
done;
case "$kmi_dirs" in
  *vendor_dlkm*) ;;
  *) for m in $kmi_montados; do umount $m; done;
     abort "No se encuentra vendor_dlkm para comprobar la compatibilidad de módulos. Abortado.";;
esac;
chmod 755 $AKHOME/tools/kmicheck;
ui_print " " "Comprobando módulos de la ROM contra este kernel...";
$AKHOME/tools/kmicheck $AKHOME/vmlinux.symvers $kmi_dirs > $AKHOME/kmicheck.log 2>&1;
kmi_rc=$?;
while read -r l; do ui_print "$l"; done < $AKHOME/kmicheck.log;
for m in $kmi_montados; do umount $m; done;
[ $kmi_rc -eq 0 ] || abort "Los módulos de esta ROM no son compatibles con este kernel. Abortado.";

# boot install: solo se reemplaza el kernel (boot v4 sin ramdisk; el ramdisk va en init_boot)
split_boot;
flash_boot;
## end boot install
