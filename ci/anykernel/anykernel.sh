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

# Elección del kernel: kernels/lista trae los Image del zip, del más nuevo al más viejo.
# 1) el compilado del mismo código que la ROM (su versión = la del vermagic de los módulos);
# 2) si no está, el primero compatible por CRC; 3) si ninguno, abortar.
rom_rel=$($AKHOME/tools/kmicheck -r $kmi_dirs 2>/dev/null);
ui_print " " "Módulos de la ROM: ${rom_rel:-desconocido}";
elegido="";
for k in $rom_rel $(cat $AKHOME/kernels/lista); do
  [ -f "$AKHOME/kernels/$k/Image" ] || continue;
  ui_print "Probando kernel $k...";
  if $AKHOME/tools/kmicheck $AKHOME/kernels/$k/vmlinux.symvers $kmi_dirs > $AKHOME/kmicheck.log 2>&1; then
    elegido=$k;
  fi;
  while read -r l; do ui_print "  $l"; done < $AKHOME/kmicheck.log;
  [ "$elegido" ] && break;
done;
for m in $kmi_montados; do umount $m; done;
[ "$elegido" ] || abort "Ningún kernel del zip es compatible con los módulos de esta ROM. Abortado.";
ui_print " " "Instalando kernel $elegido";
cp -f $AKHOME/kernels/$elegido/Image $AKHOME/Image;

# boot install: solo se reemplaza el kernel (boot v4 sin ramdisk; el ramdisk va en init_boot)
split_boot;
flash_boot;
## end boot install
