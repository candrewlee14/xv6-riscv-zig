// uringbuf.zig
struct user_ring_buf;
int ringbuf_init(const char*, struct user_ring_buf*);
int ringbuf_deinit(int);
void ringbuf_start_read(int ring_desc, char **addr, int *bytes);
void ringbuf_finish_read(int ring_desc, int bytes);
void ringbuf_start_write(int ring_desc, char **addr, int *bytes);
void ringbuf_finish_write(int ring_desc, int bytes);

