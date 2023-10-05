#include "kernel/types.h"
#include "user/user.h"

#define MAX_BUFS 16

void error(const char *msg) {
    printf(msg);
    exit(-1);
}

int main(char *argv, int argc) {
    
    char *names[] = {
        "buf1",
        "buf2",
        "buf3",
        "buf4",
        "buf5",
        "buf6",
        "buf7",
        "buf8",
        "buf9",
        "buf10",
        "buf11",
        "buf12",
        "buf13",
        "buf14",
        "buf15",
        "buf16",
    };

    void *addrs[MAX_BUFS];

    // Open and close the same ringbuf multiple times
    for (int i = 0; i < 10000; i++)
    {
        void *addr;
        if (ringbuf("reopen", 1, &addr) < 0) // open
            error("System call failed when it shouldn't have\n");
        if (ringbuf("reopen", 0, &addr) < 0) //close
            error("System call failed when it shouldn't have\n");
    }
    printf("Passed test rapid open/close test\n");

    // Open and close all available ringbufs
    for (int i = 0; i < 1000; i++)
    {
        int buf_count = 0;
        for (int i = 0; i < MAX_BUFS; i++)
        {
            int res = ringbuf(names[i], 1, &(addrs[i]));
            if (res < 0)
                break;
            else
                buf_count++;
        }
        if (buf_count == 0)
            error("Unable to allocate any ringbufs\n");
        for (int i = 0; i < buf_count; i++)
        {
            int res = ringbuf(names[i], 0, &(addrs[i]));
            if (res < 0)
                error("Unable to close allocated ringbuf\n");
        }
    }
    printf("Passed full open/close test\n");

    // Fork, have child open all ringbufs it can without closing, then try to allocate a ringbuf
    int pid = fork();
    if (pid < 0)
        error("Fork error");
    if (pid == 0)
    {
        for (int i = 0; i < MAX_BUFS; i++)
        {
            names[i][0] = 'x'; // Change names to avoid accessing same ringbufs as above
            int res = ringbuf(names[i], 1, &(addrs[i]));
            if (res < 0)
            {
                break;
            }
        }
        exit(0); // exit without closing ringbufs
    }
    else
    {
        wait((int *)0); // wait until child exits
        void *addr;
        int res = ringbuf("parent_ringbuf", 1, &addr);
        if (res < 0)
            error("Parent unable to allocate new ringbuf\n");
    }
    printf("Passed fork and exit without closing test\n");

    return 0;
}