
localparam CORE_CLK_SYS  = 48;

localparam CORE_CLK_16   = (CORE_CLK_SYS/16)-1;
localparam CORE_CLK_8    = (CORE_CLK_SYS/8)-1;
localparam CORE_CLK_4    = (CORE_CLK_SYS/4)-1;
localparam CORE_CLK_2    = (CORE_CLK_SYS/2)-1;

localparam CORE_CLK_4_9  = 9;   // 48/4.8-1
// FM77AV main CPU with MMR enabled: 2 MHz drops to 1.6 MHz (FM-Techknow p.334).
// 6.4 MHz is not an integer divide of 48; 48/7 = 6.857 MHz gives E = 1.714 MHz.
localparam CORE_CLK_6_8  = 6;
localparam CORE_CLK_1_2  = 39;  // 48/1.2-1;
// 9.000 us per T77 duration unit, which is what 77AVEMU uses:
// NANOSEC_PER_T77_ONE = 9000 (fm77avtape.h:32). 2*(215+1)/48MHz = 9.000 us
// exactly. This was 218, i.e. 9.125 us -- 1.4% slow, and tape bit framing is
// timing-critical. (A derivation from the manual's 1600 baud average gives
// 8.458 us and is WRONG: the t77 unit is a fixed 9 us, and the baud rate that
// falls out of it is whatever the image's bit mix makes it.)
localparam DIV_9us       = 215;
localparam PCM_CLK       = 59;  // 48/0.8-1
