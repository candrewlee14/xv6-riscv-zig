#include "kernel/types.h"
#include "user/user.h"

int main(char *argv, int argc) {
    void *addr;
    // Start of tests for SPSC ringbuf ownership
    if (ringbuf("double_own", 1, &addr) < 0) { // Opening ringbuf
        printf("System call failed when it shouldn't have\n");
        return -1;
    }
    if (ringbuf("double_own", 1, &addr) >= 0) { // Opening ringbuf twice in same proc
        printf("System call didn't fail when it should have\n");
        printf("Should not be ownable by the same proc twice\n");
        return -1;
    }
    int pid = fork();
	if (pid > 0) {
        // parent
        int exit_status;
        wait(&exit_status);
        if (exit_status < 0) {
            return -1;
        }
    } else {
        void *addr2;
        if (ringbuf("double_own", 1, &addr2) < 0) { // Ownable by a different proc (2 owners)
            printf("System call failed when it shouldn't have\n");
            printf("Should be ownable by a different proc\n");
            return -1;
        }
        int pid = fork();
        if (pid > 0) {
            int exit_status;
            wait(&exit_status);
            if (exit_status < 0) {
                return -1;
            }
        } else {
            void *addr3;
            if (ringbuf("double_own", 1, &addr3) >= 0) { // Cannot be owned by 3 procs simultaneously
                printf("System call didn't fail when it should have\n");
                printf("Should not be ownable by a different proc (3 owners)\n");
                return -1;
            }
            return 0;
        }
        return 0;
    }    
    int pid2 = fork();
    if (pid2 > 0) {
        // parent
        int exit_status;
        wait(&exit_status);
        if (exit_status < 0) {
            return -1;
        }
    } else {
        void *addr4;
        if (ringbuf("double_own", 1, &addr4) < 0) { // Re-ownable by a different proc (2 owners)
            printf("System call failed when it shouldn't have\n");
            printf("Should be re-ownable by a different proc (2 owners)\n");
            return -1;
        }
        return 0;
    }

    // Orphaned by original parent, should be ownable by new parents
    void* addr5;
    if (ringbuf("second", 1, &addr5) < 0) {
        printf("System call failed when it shouldn't have\n");
        return -1;
    }
    int pid3 = fork();
    if (pid3 > 0) {
        sleep(5); // allow handoff
        ringbuf("second", 0, &addr5);
    } else {
        void* addr6;
        if (ringbuf("second", 1, &addr6) < 0) {
            printf("System call failed when it shouldn't have\n");
            return -1;
        }
        return 0;
    }
    int pid4 = fork();
    if (pid4 > 0) {
        int exit_status;
        wait(&exit_status);
        if (exit_status < 0) {
            return -1;
        }
    } else {
        void* addr7;
        if (ringbuf("second", 1, &addr7) < 0) { // Handoff
            printf("System call failed when it shouldn't have\n");
            printf("Should be ownable by a different proc\n");
            return -1;
        }
        return 0;
    }

    return 0;
}