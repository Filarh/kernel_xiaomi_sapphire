/* kmicheck: ¿cargan estos .ko con este kernel?
 * Misma regla que el kernel con CONFIG_MODVERSIONS (kernel/module.c: check_version,
 * same_magic): por cada símbolo de __versions, su CRC debe ser el de vmlinux.symvers;
 * los símbolos que vmlinux no exporta deben exportarlos otros módulos del conjunto.
 * Uso: kmicheck vmlinux.symvers DIR... ; sale 0 si todos son compatibles, 1 si no, 2 si error.
 *      kmicheck -r DIR...  ; imprime la versión (primer campo de vermagic) de los módulos;
 *                            sale 1 si hay más de una distinta. */
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct { char *name; uint32_t crc; } Sym;
static Sym *vm; static size_t nvm;
static char **exp_; static size_t nexp, cexp;
static char **kos; static size_t nkos, ckos;

static int cmpsym(const void *a, const void *b) { return strcmp(((const Sym *)a)->name, ((const Sym *)b)->name); }
static int cmpstr(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

static unsigned char *slurp(const char *p, size_t *n) {
  FILE *f = fopen(p, "rb"); if (!f) return NULL;
  fseek(f, 0, SEEK_END); long l = ftell(f); fseek(f, 0, SEEK_SET);
  unsigned char *b = malloc(l + 1); if (!b || fread(b, 1, l, f) != (size_t)l) { fclose(f); free(b); return NULL; }
  fclose(f); b[l] = 0; *n = l; return b;
}

/* Devuelve inicio y tamaño de una sección por nombre, o NULL. */
static const unsigned char *sec(const unsigned char *d, size_t n, const char *want, uint64_t *sz) {
  if (n < 64 || memcmp(d, "\x7f" "ELF\x02\x01", 6)) return NULL;
  uint64_t shoff; uint16_t shentsize, shnum, shstrndx;
  memcpy(&shoff, d + 0x28, 8); memcpy(&shentsize, d + 0x3a, 2); memcpy(&shnum, d + 0x3c, 2); memcpy(&shstrndx, d + 0x3e, 2);
  if (shoff + (uint64_t)shnum * shentsize > n || shstrndx >= shnum) return NULL;
  uint64_t stroff; memcpy(&stroff, d + shoff + shstrndx * shentsize + 0x18, 8);
  for (unsigned i = 0; i < shnum; i++) {
    const unsigned char *h = d + shoff + i * shentsize;
    uint32_t nm; uint64_t off, size; memcpy(&nm, h, 4); memcpy(&off, h + 0x18, 8); memcpy(&size, h + 0x20, 8);
    if (stroff + nm >= n || off + size > n) continue;
    if (!strcmp((const char *)d + stroff + nm, want)) { *sz = size; return d + off; }
  }
  return NULL;
}

static void walk(const char *dir) {
  DIR *dp = opendir(dir); if (!dp) return;
  struct dirent *e;
  while ((e = readdir(dp))) {
    if (e->d_name[0] == '.') continue;
    size_t l = strlen(dir) + strlen(e->d_name) + 2; char *p = malloc(l);
    snprintf(p, l, "%s/%s", dir, e->d_name);
    struct stat st; if (stat(p, &st)) { free(p); continue; }
    if (S_ISDIR(st.st_mode)) { walk(p); free(p); }
    else if (l > 4 && !strcmp(p + strlen(p) - 3, ".ko")) {
      if (nkos == ckos) kos = realloc(kos, (ckos = ckos ? ckos * 2 : 256) * sizeof *kos);
      kos[nkos++] = p;
    } else free(p);
  }
  closedir(dp);
}

static int release_mode(int argc, char **argv) {
  for (int i = 2; i < argc; i++) walk(argv[i]);
  char *rel = NULL; int varias = 0;
  for (size_t k = 0; k < nkos; k++) {
    size_t n; unsigned char *d = slurp(kos[k], &n); uint64_t sz;
    const unsigned char *m = d ? sec(d, n, ".modinfo", &sz) : NULL;
    for (uint64_t o = 0; m && o < sz; o += strlen((const char *)m + o) + 1) {
      if (strncmp((const char *)m + o, "vermagic=", 9)) continue;
      const char *v = (const char *)m + o + 9; size_t l = strcspn(v, " ");
      if (!rel) { rel = strndup(v, l); }
      else if (strlen(rel) != l || strncmp(rel, v, l)) varias = 1;
    }
    free(d);
  }
  if (!rel) { fprintf(stderr, "sin vermagic en los módulos\n"); return 2; }
  printf("%s\n", rel);
  return varias;
}

int main(int argc, char **argv) {
  if (argc >= 3 && !strcmp(argv[1], "-r")) return release_mode(argc, argv);
  if (argc < 3) { fprintf(stderr, "uso: %s vmlinux.symvers DIR...\n", argv[0]); return 2; }
  size_t n; char *sv = (char *)slurp(argv[1], &n);
  if (!sv) { fprintf(stderr, "no se puede leer %s\n", argv[1]); return 2; }
  for (char *line = strtok(sv, "\n"); line; line = strtok(NULL, "\n")) {
    char *t1 = strchr(line, '\t'); if (!t1) continue; *t1 = 0;
    char *t2 = strchr(t1 + 1, '\t'); if (t2) *t2 = 0;
    vm = realloc(vm, (nvm + 1) * sizeof *vm);
    vm[nvm].name = t1 + 1; vm[nvm].crc = (uint32_t)strtoul(line, NULL, 16); nvm++;
  }
  qsort(vm, nvm, sizeof *vm, cmpsym);
  for (int i = 2; i < argc; i++) walk(argv[i]);
  if (!nkos) { fprintf(stderr, "no hay .ko en los directorios dados\n"); return 2; }
  unsigned char **data = calloc(nkos, sizeof *data); size_t *len = calloc(nkos, sizeof *len);
  for (size_t k = 0; k < nkos; k++) {
    data[k] = slurp(kos[k], &len[k]);
    uint64_t sz; const unsigned char *s = data[k] ? sec(data[k], len[k], "__ksymtab_strings", &sz) : NULL;
    for (uint64_t o = 0; s && o < sz; o += strlen((const char *)s + o) + 1)
      if (s[o]) { if (nexp == cexp) exp_ = realloc(exp_, (cexp = cexp ? cexp * 2 : 1024) * sizeof *exp_); exp_[nexp++] = (char *)s + o; }
  }
  qsort(exp_, nexp, sizeof *exp_, cmpstr);
  size_t malos = 0, entradas = 0;
  for (size_t k = 0; k < nkos; k++) {
    uint64_t sz; const unsigned char *v = data[k] ? sec(data[k], len[k], "__versions", &sz) : NULL;
    if (!v) { printf("INCOMPATIBLE %s: sin sección __versions o ELF ilegible\n", kos[k]); malos++; continue; }
    int mal = 0;
    for (uint64_t o = 0; o + 64 <= sz; o += 64) {
      uint64_t crc; memcpy(&crc, v + o, 8); char name[57]; memcpy(name, v + o + 8, 56); name[56] = 0; entradas++;
      Sym key = { name, 0 }; Sym *s = bsearch(&key, vm, nvm, sizeof *vm, cmpsym);
      char *kp = name;
      if (s) { if (s->crc != (uint32_t)crc) { if (!mal++) printf("INCOMPATIBLE %s:", kos[k]); printf(" %s(crc)", name); } }
      else if (!bsearch(&kp, exp_, nexp, sizeof *exp_, cmpstr)) { if (!mal++) printf("INCOMPATIBLE %s:", kos[k]); printf(" %s(sin exportar)", name); }
    }
    if (mal) { printf("\n"); malos++; }
  }
  printf("kmicheck: %zu módulos, %zu símbolos comprobados, %zu incompatibles\n", nkos, entradas, malos);
  return malos ? 1 : 0;
}
