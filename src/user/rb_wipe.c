#include "kernel/types.h"
#include "user/user.h"

int main(char *argv, int argc) {
    void *addr;

    ringbuf("info_wiped", 1, &addr);
    (*(int *)addr) = 1337;
    ringbuf("info_wiped", 0, &addr);
    ringbuf("info_wiped", 1, &addr);
    if (((int *)addr)[0] == 1337) {
        printf("Failure. Address was not wiped");
        return -1;
    }
    void *addr_copy = addr;
    ringbuf("info_wiped", 0, &addr);

    printf("Now should segfault\n");
    (*(char*)addr_copy)++;
    return -1; //If it didn't segfault, we failed
}