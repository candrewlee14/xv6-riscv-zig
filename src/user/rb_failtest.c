// David Dursteler's failtest example

#include "kernel/types.h"
#include "user/user.h"

int main(char *argv, int argc) {
    void *addr;
    if (ringbuf("", 1, &addr) >= 0 // Too small name
        || ringbuf("0123456789ABCDEF", 1, &addr) >= 0 //Too large name
        || ringbuf("test", 0, &addr) >= 0 //Closing unopened ringbuf
    ) {
        printf("System call didn't fail when it should have\n");
        return -1;
    }
    return 0;
}