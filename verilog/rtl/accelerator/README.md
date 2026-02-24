# Accelerator Module (BASE v2.0 – Future)

This directory is reserved for a hardware accelerator component.

Integration notes (from BASE v2.0 spec):
- Wishbone base address: start at offset 0x10 or use a separate base address
- IRQ assignment: user_irq[1] is available
- GPIO: io_in[0:6] and io_out[29:37] are available
- user_clock2 is available as a secondary clock domain

No RTL exists here yet. Populate when scope is confirmed.
