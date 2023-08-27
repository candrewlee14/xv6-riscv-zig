
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"

#define CHUNK_LEN 512
#define WRITE_AMT (10 * 1024 * 1024)

int
main(int argc, char *argv[])
{
  char chunk[CHUNK_LEN];
  int i;
  for (i = 0; i < CHUNK_LEN; i++) {
    chunk[i] = 'a' + (i % 26);
  }
  printf("Running benchmark...\n");

  int fds[2];
  if (pipe(fds) != 0) {
    printf("failed pipe call\n");
    exit(1);
  }
  int pid = fork();
  if (pid != 0) {
    // parent
    close(fds[1]); // close writer
    int read_buf[CHUNK_LEN];
    int n_read = 0;
    int t_before = uptime();
    while (n_read < WRITE_AMT) {
      int read_amt = read(fds[0], &read_buf, CHUNK_LEN);
      if (read_amt < 0) {
        printf("read failed\n");
        exit(1);
      }
      n_read += read_amt;
      if (memcmp(read_buf, chunk, CHUNK_LEN) != 0) {
        printf("The byte stream read did not match written stream!\n");
        exit(1);
      }
    }
    int t_after = uptime();
    printf("Elapsed ticks: %d\n", t_after - t_before);
    int exit_status;
    if (pid != wait(&exit_status)) {
      printf("Unexpected child PID for wait\n");
      exit(1);
    }
    if (exit_status != 0) {
      printf("Child returned bad exit status: %d\n", exit_status);
      exit(1);
    }
    close(fds[0]);
  } else {
    // child
    close(fds[0]); // close reader
    int n_written = 0;
    while (n_written < WRITE_AMT) {
      int write_amt = write(fds[1], &chunk, CHUNK_LEN);
      if (write_amt < 0) {
        printf("write failed\n");
        exit(1);
      }
      n_written += write_amt;
    }
    close(fds[1]);
  }
  exit(0);
}
