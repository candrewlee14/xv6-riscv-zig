// Much of this code comes from https://github.com/binarycraft007/xv6-riscv-zig

pub inline fn r_mhartid() usize {
    return asm volatile ("csrr a0, mhartid"
        : [ret] "={a0}" (-> usize),
    );
}

pub const MSTATUS_MPP_MASK = 3 << 11;

pub const MSTATUS = enum(usize) {
    MPP_M = 3 << 11,
    MPP_S = 1 << 11,
    MPP_U = 0 << 11,
    MIE = 1 << 3, // machine-mode interrupt enable.
};

pub inline fn r_mstatus() usize {
    return asm volatile ("csrr a0, mstatus"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_mstatus(status: usize) void {
    asm volatile ("csrw mstatus, a0"
        :
        : [status] "{a0}" (status),
    );
}

pub inline fn w_mepc(counter: usize) void {
    asm volatile ("csrw mepc, a0"
        :
        : [counter] "{a0}" (counter),
    );
}

pub const SSTATUS = enum(usize) {
    SPP = 1 << 8, // Previous mode, 1=Supervisor, 0=User
    SPIE = 1 << 5, // Supervisor Previous Interrupt Enable
    UPIE = 1 << 4, // User Previous Interrupt Enable
    SIE = 1 << 1, // Supervisor Interrupt Enable
    UIE = 1 << 0, // User Interrupt Enable
};

pub inline fn r_sstatus() usize {
    return asm volatile ("csrr a0, sstatus"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_sstatus(sstatus: usize) void {
    asm volatile ("csrw sstatus, a0"
        :
        : [sstatus] "{a0}" (sstatus),
    );
}

// Supervisor Interrupt Pending
pub inline fn r_sip() usize {
    return asm volatile ("csrr a0, sip"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_sip(sip: usize) void {
    asm volatile ("csrw sip, a0"
        :
        : [sip] "{a0}" (sip),
    );
}

// Supervisor Interrupt Enable
pub const SIE = enum(usize) {
    SEIE = 1 << 9, // external
    STIE = 1 << 5, // timer
    SSIE = 1 << 1, // software
};

pub inline fn r_sie() usize {
    return asm volatile ("csrr a0, sie"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_sie(sie: usize) void {
    asm volatile ("csrw sie, a0"
        :
        : [sie] "{a0}" (sie),
    );
}

// Machine-mode Interrupt Enable
pub const MIE = enum(usize) {
    MEIE = 1 << 11, // external
    MTIE = 1 << 7, // timer
    MSIE = 1 << 3, // software
};

pub inline fn r_mie() usize {
    return asm volatile ("csrr a0, mie"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_mie(mie: usize) void {
    asm volatile ("csrw mie, a0"
        :
        : [mie] "{a0}" (mie),
    );
}

// supervisor exception program counter, holds the
// instruction address to which a return from
// exception will go.
pub inline fn w_sepc(sepc: usize) void {
    asm volatile ("csrw sepc, a0"
        :
        : [sepc] "{a0}" (sepc),
    );
}

pub inline fn r_sepc() usize {
    return asm volatile ("csrr a0, sepc"
        : [ret] "={a0}" (-> usize),
    );
}

// Machine Exception Delegation
pub inline fn r_medeleg() usize {
    return asm volatile ("csrr a0, medeleg"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_medeleg(medeleg: usize) void {
    asm volatile ("csrw medeleg, a0"
        :
        : [medeleg] "{a0}" (medeleg),
    );
}

// Machine Interrupt Delegation
pub inline fn r_mideleg() usize {
    return asm volatile ("csrr a0, mideleg"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_mideleg(mideleg: usize) void {
    asm volatile ("csrw mideleg, a0"
        :
        : [mideleg] "{a0}" (mideleg),
    );
}

// Supervisor Trap-Vector Base Address
// low two bits are mode.
pub inline fn w_stvec(stvec: usize) void {
    asm volatile ("csrw stvec, a0"
        :
        : [stvec] "{a0}" (stvec),
    );
}

pub inline fn r_stvec() usize {
    return asm volatile ("csrr a0, stvec"
        : [ret] "={a0}" (-> usize),
    );
}

// Machine-mode interrupt vector
pub inline fn w_mtvec(mtvec: usize) void {
    asm volatile ("csrw mtvec, a0"
        :
        : [mtvec] "{a0}" (mtvec),
    );
}

// Physical Memory Protection
pub inline fn w_pmpcfg0(pmpcfg0: usize) void {
    asm volatile ("csrw pmpcfg0, a0"
        :
        : [pmpcfg0] "{a0}" (pmpcfg0),
    );
}

pub inline fn w_pmpaddr0(pmpaddr0: usize) void {
    asm volatile ("csrw pmpaddr0, a0"
        :
        : [pmpaddr0] "{a0}" (pmpaddr0),
    );
}

// use riscv's sv39 page table scheme.
pub const SATP_SV39 = @as(usize, 8) << 60;

pub fn MAKE_SATP(pagetable: PageTable) usize {
    return SATP_SV39 | (@intFromPtr(pagetable) >> 12);
}

// supervisor address translation and protection;
// holds the address of the page table.
pub inline fn w_satp(satp: usize) void {
    asm volatile ("csrw satp, a0"
        :
        : [satp] "{a0}" (satp),
    );
}

pub inline fn r_satp() usize {
    return asm volatile ("csrr a0, satp"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_mscratch(mscratch: usize) void {
    asm volatile ("csrw mscratch, a0"
        :
        : [mscratch] "{a0}" (mscratch),
    );
}

pub inline fn r_mscratch() usize {
    return asm volatile ("csrw a0, mscratch"
        : [ret] "={a0}" (-> usize),
    );
}

// Supervisor Trap Cause
pub inline fn r_scause() usize {
    return asm volatile ("csrr a0, scause"
        : [ret] "={a0}" (-> usize),
    );
}

// Supervisor Trap Value
pub inline fn r_stval() usize {
    return asm volatile ("csrr a0, stval"
        : [ret] "={a0}" (-> usize),
    );
}

// Machine-mode Counter-Enable
pub inline fn w_mcounteren(mcounteren: usize) void {
    asm volatile ("csrw mcounteren, a0"
        :
        : [mcounteren] "{a0}" (mcounteren),
    );
}

pub inline fn r_mcounteren() usize {
    return asm volatile ("csrr a0, mcounteren"
        : [ret] "={a0}" (-> usize),
    );
}

// machine-mode cycle counter
pub inline fn r_time() usize {
    return asm volatile ("csrr a0, time"
        : [ret] "={a0}" (-> usize),
    );
}

// enable device interrupts
pub inline fn intr_on() void {
    w_sstatus(r_sstatus() | @intFromEnum(SSTATUS.SIE));
}

// disable device interrupts
pub inline fn intr_off() void {
    w_sstatus(r_sstatus() & ~@intFromEnum(SSTATUS.SIE));
}

// are device interrupts enabled?
pub inline fn intr_get() bool {
    return (r_sstatus() & @intFromEnum(SSTATUS.SIE)) != 0;
}

pub inline fn r_sp() usize {
    return asm volatile ("mv a0, sp"
        : [ret] "={a0}" (-> usize),
    );
}

// read and write tp, the thread pointer, which xv6 uses to hold
// this core's hartid (core number), the index into cpus[].
pub inline fn r_tp() usize {
    return asm volatile ("mv a0, tp"
        : [ret] "={a0}" (-> usize),
    );
}

pub inline fn w_tp(tp: usize) void {
    asm volatile ("mv tp, a0"
        :
        : [tp] "{a0}" (tp),
    );
}

pub inline fn r_ra() usize {
    return asm volatile ("mv a0, ra"
        : [ret] "={a0}" (-> usize),
    );
}

// flush the TLB.
pub inline fn sfence_vma() void {
    // the zero, zero means flush all TLB entries.
    asm volatile ("sfence.vma zero, zero");
}

pub const pte_t = usize;
pub const PageTable = [*]usize; // 512 PTEs

pub const PGSIZE = 4096; // bytes per page
pub const PGSHIFT = 12; // bits of offset within a page
pub inline fn PGROUNDUP(sz: usize) usize {
    return ((sz) + PGSIZE - 1) & ~@as(usize, PGSIZE - 1);
}
pub inline fn PGROUNDDOWN(a: usize) usize {
    return ((a)) & ~@as(usize, PGSIZE - 1);
}
pub const PTE_V = @as(u32, 1) << 0; // valid
pub const PTE_R = @as(u32, 1) << 1;
pub const PTE_W = @as(u32, 1) << 2;
pub const PTE_X = @as(u32, 1) << 3;
pub const PTE_U = @as(u32, 1) << 4; // user can access

// shift a physical address to the right place for a PTE.
pub inline fn PA2PTE(pa: usize) usize {
    return @as(usize, pa >> 12) << 10;
}
pub inline fn PTE2PA(pte: usize) usize {
    return @as(usize, pte >> 10) << 12;
}
pub inline fn PTE_FLAGS(pte: usize) usize {
    return @as(usize, pte & 0x3FF);
}

// extract the three 9-bit page table indices from a virtual address.
pub const PXMASK = 0x1FF; // 9 bits
pub inline fn PXSHIFT(level: usize) usize {
    return PGSHIFT + @as(usize, 9 * level);
}
pub inline fn PX(level: usize, va: usize) usize {
    return (va >> @as(u6, @intCast(PXSHIFT(level)))) & PXMASK;
}

// one beyond the highest possible virtual address.
// MAXVA is actually one bit less than the max allowed by
// Sv39, to avoid having to sign-extend virtual addresses
// that have the high bit set.
pub const MAXVA = @as(usize, 1) << (9 + 9 + 9 + 12 - 1);
