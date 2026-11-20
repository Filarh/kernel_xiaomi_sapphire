#!/usr/bin/env python3
"""Aplica a mano los dos hunks de includes del parche susfs gki-android13-5.15
que no casan en el árbol CLO de sapphire: el contexto original trae
<trace/hooks/blk.h> y <trace/hooks/mm.h>, que este árbol no incluye ahí."""
import sys

def insert_after(path, anchor, text):
    src = open(path).read()
    if text in src:
        return
    if src.count(anchor) != 1:
        sys.exit(f"{path}: el ancla aparece {src.count(anchor)} veces")
    open(path, "w").write(src.replace(anchor, anchor + text, 1))

insert_after("fs/namespace.c", "#include <linux/mnt_idmapping.h>\n",
"""#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#endif // #ifdef CONFIG_KSU_SUSFS
""")
insert_after("fs/namespace.c", '#include "internal.h"\n',
"""
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern bool susfs_is_current_ksu_domain(void);
extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;

#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
""")
insert_after("fs/proc/task_mmu.c", "#include <linux/pkeys.h>\n",
"""#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)
#include <linux/susfs_def.h>
#endif // #if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)
""")
print("susfs-fixup: includes de fs/namespace.c y fs/proc/task_mmu.c aplicados")
