
module SUBCRTADDR(
  input SDRAMV1n,
  input SDRAMV2n,
  input SDRAMV3n,
  input SBLANKn,
  input SCASSEL,
  input SRWB,
  output SVCASBn,
  output SVCASRn,
  output SVCASGn,
  output SVWEn,
  output SADRSEL
);

assign SVCASBn = SBLANKn & SDRAMV1n & SCASSEL;
assign SVCASRn = SBLANKn & SDRAMV2n & SCASSEL;
assign SVCASGn = SBLANKn & SDRAMV3n & SCASSEL;

// The sub may drive the VRAM write strobe exactly when it owns the VRAM address
// bus. This was `~SBLANKn ? SRWB : 1'b1`, which was the SAME expression while
// MB60H010 built SBLANKn as ~SCASSEL -- it no longer does, because SCASSEL now
// hands the sub every cycle the raster is not fetching (cycle steal) while
// SBLANKn stays a display-blanking output. Keyed on the wrong one of the two,
// the sub's clock would restart mid-cell with its write strobe still held off
// and the store would silently vanish.
assign SVWEn = SCASSEL ? SRWB : 1'b1;

assign SADRSEL = SDRAMV1n & SDRAMV2n & SDRAMV3n;

// M59 is supposed to disable SCPU writes (SCPUWEn=1) when SBLANK=1
// and mux SCPU/SVD RAS/CAS signals based on SBLANK

endmodule
