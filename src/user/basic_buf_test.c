#include "kernel/types.h"
#include "user/user.h"

void parent() {
	void *addr;
	int ret = ringbuf("basic_test", 1, &addr);
	if (ret < 0) printf("ERORR OPENING IN PARENT\n");
	// printf("Addr: %p", addr);
	uint32 *location = (uint32*)((char*)addr + 4096);
	for (uint32 i = 0; i < 4096 * 16 / sizeof(uint32); ++i) {
		location[i] = i;
		// printf(" %d", i);
	}

	// printf("Done Writing\n");
}

void child() {
	sleep(10); //Really poor synchronization 
	// printf("Starting Reading\n");
	void *addr;
	int ret = ringbuf("basic_test", 1, &addr);
	if (ret < 0) printf("ERORR OPENING IN CHILD\n");
	// printf("Addr: %p", addr);
	uint32 *location = (uint32*)((char*)addr + 4096);
	for (int is_magic_buf = 0; is_magic_buf <= 1; ++is_magic_buf)
	for (uint32 i = 0; i < 4096 * 16 / sizeof(uint32); ++i) { //Test magic too :)
		// printf(" %d", location[is_magic_buf*4096*16/sizeof(uint32) + i]);]
		if(location[(((uint64)is_magic_buf)*4096*16/sizeof(uint32)) + i] != i) {
			printf("F");
		}
		// else {
		// 	printf("S");
		// }
	}
	// printf("Done Reading\n");
}

int main(int *argv, int argc) {
	int pid = fork();
	if (pid > 0) parent();
	else child();
	sleep(10);
	return 0;
}
