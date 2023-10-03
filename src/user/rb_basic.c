// David Dursteler's basic example
#include "kernel/types.h"
#include "user/user.h"

void parent() {
	void *addr;
	int ret = ringbuf("basic_test", 1, &addr);
	if (ret < 0) printf("ERORR OPENING IN PARENT\n");
	// printf("Addr: %p", addr);
	uint32 *location = (uint32*)addr;
	for (uint32 i = 0; i < 4096 * 16 / sizeof(uint32); ++i) {
		location[i] = i;
		// printf(" %d", i);
	}
	// ringbuf("basic_test", 0, &addr);
}

void child() {
	sleep(1); //Really poor synchronization 

	void *addr;
	int ret = ringbuf("basic_test", 1, &addr);
	if (ret < 0) printf("ERROR OPENING IN CHILD\n");
	// printf("Addr: %p", addr);
	uint32 *location = (uint32*)addr;
	for (uint64 is_magic_buf = 0; is_magic_buf <= 1; is_magic_buf++)
	for (uint32 i = 0; i < 4096 * 16 / sizeof(uint32); i++) { //Test magic too :)
		if(location[(is_magic_buf * 4096 * 16 / sizeof(uint32)) + i] != i) {
			printf("F");
		}
	}
	for (uint32 i = 0; i < 4096 * 16 / sizeof(uint32); i++) {
		if (location[i] != i) {
			printf("F");
		}
	}
}

int main(int *argv, int argc) {
	int pid = fork();
	if (pid > 0) parent();
	else child();
	sleep(10);
	return 0;
}
