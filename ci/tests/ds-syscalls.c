// Exercises the kernel features Droidspaces needs. ENOSYS = missing in the kernel;
// EACCES/EPERM = present but blocked by policy (SELinux, permissions) for the current user.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <mqueue.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/msg.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static void r(const char *what, long rc) {
  printf("%-34s %s\n", what, rc >= 0 ? "OK" : strerror(errno));
}

int main(void) {
  setvbuf(stdout, NULL, _IONBF, 0);
  int id;
  id = shmget(IPC_PRIVATE, 1 << 20, IPC_CREAT | 0600); r("SysV shmget 1MiB", id);
  if (id >= 0) { void *p = shmat(id, 0, 0); r("SysV shmat", p == (void *)-1 ? -1 : 0);
    if (p != (void *)-1) { memset(p, 0x5a, 1 << 20); shmdt(p); } shmctl(id, IPC_RMID, 0); }
  id = semget(IPC_PRIVATE, 4, IPC_CREAT | 0600); r("SysV semget", id);
  if (id >= 0) { struct sembuf op = {0, 1, 0}; r("SysV semop", semop(id, &op, 1)); semctl(id, 0, IPC_RMID); }
  id = msgget(IPC_PRIVATE, IPC_CREAT | 0600); r("SysV msgget", id);
  if (id >= 0) { struct { long t; char m[8]; } m = {1, "hola"}; r("SysV msgsnd", msgsnd(id, &m, 5, 0));
    r("SysV msgrcv", msgrcv(id, &m, 8, 1, 0)); msgctl(id, IPC_RMID, 0); }
  struct mq_attr a = {0, 4, 64, 0};
  mqd_t q = mq_open("/dsprueba", O_CREAT | O_RDWR, 0600, &a); r("POSIX mq_open", q);
  if (q != (mqd_t)-1) { r("POSIX mq_send", mq_send(q, "hola", 5, 0)); mq_close(q); mq_unlink("/dsprueba"); }
  pid_t pid = fork();
  if (pid == 0) {
    if (unshare(CLONE_NEWUSER) < 0) { r("unshare USER_NS", -1); _exit(1); }
    r("unshare USER_NS", 0);
    r("unshare IPC_NS (inside user ns)", unshare(CLONE_NEWIPC));
    r("unshare PID_NS (inside user ns)", unshare(CLONE_NEWPID));
    r("unshare UTS+NET+MNT (inside user ns)", unshare(CLONE_NEWUTS | CLONE_NEWNET | CLONE_NEWNS));
    pid_t c = fork();
    if (c == 0) { printf("%-34s %d\n", "PID inside the new PID ns", getpid()); _exit(0); }
    waitpid(c, 0, 0); _exit(0);
  }
  waitpid(pid, 0, 0);
  return 0;
}
