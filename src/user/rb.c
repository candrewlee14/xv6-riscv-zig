#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fs.h"

#define CHUNK_LEN 510
#define WRITE_AMT (10 * 1024 * 1024)
#define SEED 42

// Define the state for the XOR-shift random number generator
typedef struct {
    uint32 state;
} XorshiftRandomCharGenerator;

// Function to initialize the random number generator with a seed
void xorshift_init(XorshiftRandomCharGenerator* generator, uint32 seed) {
    generator->state = seed;
}

// Function to generate a random character
char xorshift_generate_char(XorshiftRandomCharGenerator* generator) {
    generator->state ^= (generator->state << 13);
    generator->state ^= (generator->state >> 17);
    generator->state ^= (generator->state << 5);
    return (char)(generator->state & 0xFF);
}

typedef struct {
    uint64 state;
} XorshiftRandomUInt64Generator;

// Function to initialize the random number generator with a seed
void xorshift_uint64_init(XorshiftRandomUInt64Generator* generator, uint64 seed) {
    generator->state = seed;
}

// Function to generate a random 64-bit unsigned integer
uint64 xorshift_generate_uint64(XorshiftRandomUInt64Generator* generator) {
    generator->state ^= (generator->state << 13);
    generator->state ^= (generator->state >> 7);
    generator->state ^= (generator->state << 17);
    return generator->state;
}

int main(int argc, char *argv[])
{
    char ringbuf_name[] = "Ringbuf1";
    int pid = fork();
    if (pid != 0)
    {
        int rb_desc = ringbuf_init(ringbuf_name);

        XorshiftRandomCharGenerator generator;
        xorshift_init(&generator, SEED);

        int n_read = 0;
        int t_before = uptime();
        while (n_read < WRITE_AMT)
        {
            char* buf;
            int bytes;
            ringbuf_start_read(rb_desc, &buf, &bytes);
            for (int i = 0; i < bytes; i++)
            {
                if (buf[i] == xorshift_generate_char(&generator)) {
                    printf("The byte stream read did not match written stream!\n");
                    exit(1);
                }
            }
            n_read += bytes;
            ringbuf_finish_read(rb_desc, bytes);
        }
        int exit_status;
        if (pid != wait(&exit_status))
        {
            printf("Unexpected child PID for wait\n");
            exit(1);
        }
        int t_after = uptime();
        printf("Elapsed ticks: %d\n", t_after - t_before);
        if (exit_status != 0)
        {
            printf("Child returned bad exit status: %d\n", exit_status);
            exit(1);
        }
        ringbuf_deinit(rb_desc);
    } else {
        // child
        int rb_desc = ringbuf_init(ringbuf_name);

        XorshiftRandomCharGenerator generator;
        xorshift_init(&generator, SEED);
        
        XorshiftRandomUInt64Generator size_generator;
        xorshift_uint64_init(&size_generator, SEED + 1);

        int n_written = 0;
        while (n_written < WRITE_AMT)
        {
            char* buf;
            int bytes;
            ringbuf_start_write(rb_desc, &buf, &bytes);
            uint64 write_amt = xorshift_generate_uint64(&size_generator) % bytes;
            for (int i = 0; i < write_amt; i++)
            {
                buf[i] = xorshift_generate_char(&generator);
            }
            n_written += write_amt;
            ringbuf_finish_write(rb_desc, write_amt);
        }
        ringbuf_deinit(rb_desc);
    }
    exit(0);
}