# MMIO Engine (BASE v2.0 – Future)

This directory is reserved for a memory-mapped I/O engine component.

Integration notes (from BASE v2.0 spec):
- Wishbone base address: assign after accelerator, or use crossbar
- IRQ assignment: user_irq[2] is available
- la_data_out[127:0] is fully available for debug visibility

No RTL exists here yet. Populate when scope is confirmed.
