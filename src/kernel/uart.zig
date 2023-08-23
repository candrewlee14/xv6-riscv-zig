const memlayout = @import("memlayout.zig");
const SpinLock = @import("spinlock.zig");
const console = @import("console.zig");
const log_root = @import("log.zig");
const Proc = @import("Proc.zig");

/// the UART control registers.
/// some have different meanings for
/// read vs write.
/// see http://byterunner.com/16550.html
pub const RHR = 0; // receive holding register (for input bytes)
pub const THR = 0; // transmit holding register (for output bytes)
pub const IER = 1; // interrupt enable register
pub const IER_RX_ENABLE = 1 << 0;
pub const IER_TX_ENABLE = 1 << 1;
pub const FCR = 2; // FIFO control register
pub const FCR_FIFO_ENABLE = 1 << 0;
pub const FCR_FIFO_CLEAR = 3 << 1; // clear the content of the two FIFOs
pub const ISR = 2; // interrupt status register
pub const LCR = 3; // line control register
pub const LCR_EIGHT_BITS = 3 << 0;
pub const LCR_BAUD_LATCH = 1 << 7; // special mode to set baud rate
pub const LSR = 5; // line status register
pub const LSR_RX_READY = 1 << 0; // input is waiting to be read from RHR
pub const LSR_TX_IDLE = 1 << 5; // THR can accept another character to send

pub const TX_BUF_SIZE = 32;

var tx_lock: SpinLock = SpinLock{};
var tx_buf: [TX_BUF_SIZE]u8 = [_]u8{0} ** TX_BUF_SIZE;
var tx_w: u64 = 0; // write next to uart_tx_buf[uart_tx_w % UART_TX_BUF_SIZE]
var tx_r: u64 = 0; // read next from uart_tx_buf[uart_tx_r % UART_TX_BUF_SIZE]

pub const Error = error{NotReady};

pub fn init() void {
    // disable interrupts.
    writeReg(IER, 0x00);

    // special mode to set baud rate.
    writeReg(LCR, LCR_BAUD_LATCH);

    // LSB for baud rate of 38.4K.
    writeReg(0, 0x03);

    // MSB for baud rate of 38.4K.
    writeReg(1, 0x00);

    // leave set-baud mode,
    // and set word length to 8 bits, no parity.
    writeReg(LCR, LCR_EIGHT_BITS);

    // reset and enable FIFOs.
    writeReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);

    // enable transmit and receive interrupts.
    writeReg(IER, IER_TX_ENABLE | IER_RX_ENABLE);
}

// add a character to the output buffer and tell the
// UART to start sending if it isn't already.
// blocks if the output buffer is full.
// because it may block, it can't be called
// from interrupts; it's only suitable for use
// by write().
pub fn putc(c: u8) void {
    tx_lock.acquire();
    defer tx_lock.release();

    if (log_root.panicked) while (true) {};

    while (tx_w == tx_r + TX_BUF_SIZE) {
        // buffer is full.
        // wait for uartstart() to open up space in the buffer.
        Proc.sleep(&tx_r, &tx_lock);
    }
    tx_buf[tx_w % TX_BUF_SIZE] = c;
    tx_w += 1;
    start();
}

// alternate version of putc() that doesn't
// use interrupts, for use by kernel printf() and
// to echo characters. it spins waiting for the uart's
// output register to be empty.
pub fn putcSync(c: u8) void {
    SpinLock.pushOff();

    if (log_root.panicked) while (true) {};

    // wait for Transmit Holding Empty to be set in LSR.
    while ((readReg(LSR) & LSR_TX_IDLE) == 0) {}
    writeReg(THR, c);

    SpinLock.popOff();
}

/// if the UART is idle, and a character is waiting
/// in the transmit buffer, send it.
/// caller must hold uart_tx_lock.
/// called from both the top- and bottom-half.
pub fn start() void {
    while (true) {
        if (tx_w == tx_r) {
            // transmit buffer is empty.
            return;
        }

        if ((readReg(LSR) & LSR_TX_IDLE) == 0) {
            // the UART transmit holding register is full,
            // so we cannot give it another byte.
            // it will interrupt when it's ready for a new byte.
            return;
        }

        var c = tx_buf[tx_r % TX_BUF_SIZE];
        tx_r += 1;

        // maybe uartputc() is waiting for space in the buffer.
        Proc.wakeup(&tx_r);

        writeReg(THR, c);
    }
}

/// read one input character from the UART.
/// return NotReady if none is waiting.
pub fn getc() !usize {
    if (readReg(LSR) & 0x01) {
        // input data is ready.
        return readReg(RHR);
    } else {
        return error.NotReady;
    }
}

/// handle a uart interrupt, raised because input has
/// arrived, or the uart is ready for more output, or
/// both. called from devintr().
pub fn uartIntr() !void {
    // read and process incoming characters.
    while (true) {
        var c = getc() catch break;
        console.intr(c);
    }

    // send buffered characters.
    tx_lock.acquire();
    start();
    tx_lock.release();
}

pub fn getRegPtr(reg: usize) *volatile u8 {
    return @ptrFromInt(memlayout.UART0 + reg);
}

pub fn readReg(reg: usize) u8 {
    return getRegPtr(reg).*;
}

pub fn writeReg(reg: usize, value: u8) void {
    getRegPtr(reg).* = value;
}
