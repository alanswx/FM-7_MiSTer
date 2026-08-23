
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
localparam DIV_9us       = 218; // 48/0.22
localparam PCM_CLK       = 59;  // 48/0.8-1
