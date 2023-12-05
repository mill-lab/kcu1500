`timescale 1ns/1ps
`default_nettype none

module port2axis
  ( input wire CLK, RST,
    input wire [7:0][63:0]  D,
    input wire		    D_VALID,
    output wire		    D_BP,
    input wire		    D_EOF, 

    output wire [7:0][63:0] M_AXIS_TDATA,
    output wire		    M_AXIS_TVALID, M_AXIS_TLAST,
    input wire		    M_AXIS_TREADY );

   parameter		    TLAST_Enable = 0;
   
   // ------------------------------
   // Register input signals
   
   reg			    DV_R, D_EOF_R;
   reg [7:0][63:0]	    D_R;

   always @ (posedge CLK) begin
      DV_R <= D_VALID;
      D_R  <= D;
      D_EOF_R <= D_EOF;
   end

   wire FULL, AFULL;
   assign D_BP = AFULL |  FULL;

   wire	[512:0] dout;
   assign M_AXIS_TLAST = M_AXIS_TVALID ? dout[512] : 0;
   assign M_AXIS_TDATA[0] = dout[63:0];
   assign M_AXIS_TDATA[1] = dout[127:64];
   assign M_AXIS_TDATA[2] = dout[191:128];
   assign M_AXIS_TDATA[3] = dout[255:192];
   assign M_AXIS_TDATA[4] = dout[319:256];
   assign M_AXIS_TDATA[5] = dout[383:320];
   assign M_AXIS_TDATA[6] = dout[447:384];
   assign M_AXIS_TDATA[7] = dout[511:448];

   fifo_513 fifo
     (.clk(CLK),
      .srst(RST),
      
      .din({D_EOF_R, D_R}),
      .wr_en(DV_R),
      .full(FULL),
      .prog_full(AFULL),
      
      .rd_en(M_AXIS_TREADY),
      .dout(dout),
      .empty(),
      .valid(M_AXIS_TVALID),
      
      .wr_rst_busy(),
      .rd_rst_busy()
      );
   
endmodule // port2axis

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

module axis2port
  ( input wire CLK, RST,
    input wire		    S_AXIS_TVALID, S_AXIS_TLAST,
    input wire [7:0][63:0]  S_AXIS_TDATA,
    output wire		    S_AXIS_TREADY,

    output wire [7:0][63:0] Q,
    output wire		    Q_VALID,
    input wire		    Q_BP
    );

   wire			    FULL, AFULL, VALID;
   assign S_AXIS_TREADY = ~(FULL | AFULL);
   wire			    WE = S_AXIS_TVALID & S_AXIS_TREADY;

   // wire [511:0]		    S_AXIS_TDATAi;
   // assign S_AXIS_TDATAi = S_AXIS_TDATA;
   wire [512:0]		    dout;
   assign Q[0] = dout[63:0];
   assign Q[1] = dout[127:64];
   assign Q[2] = dout[191:128];
   assign Q[3] = dout[255:192];
   assign Q[4] = dout[319:256];
   assign Q[5] = dout[383:320];
   assign Q[6] = dout[447:384];
   assign Q[7] = dout[511:448];

   fifo_513 fifo
     (.clk(CLK),
      .srst(RST),
      
      .din({S_AXIS_TLAST, S_AXIS_TDATA}),
      .wr_en(WE),
      .full(FULL),
      .prog_full(AFULL),
      
      .rd_en(~Q_BP),
      .dout(dout),
      .empty(),
      .valid(VALID),
      
      .wr_rst_busy(),
      .rd_rst_busy()
      );

   assign Q_VALID = VALID & ~Q_BP;
endmodule // axis2port

// ----------------------------------------------------------------------

`ifdef PORT2AXIS_TB_EN
module tb();
   parameter real Step = 10.0;

   reg		  CLK = 1;
   always # (Step/2) CLK <= ~CLK;

   reg		  RST;
   initial begin
      $shm_open();
      $shm_probe("SA");
      RST <= 1;

      #(15.1*Step) RST <= 0;
      #(1000*Step) $finish;
   end

   reg [31:0] CNT;
   always @ (posedge CLK) CNT <= RST ? 0 : CNT+1;
   

   reg [7:0]  P2A_CNT;
   reg	      P2A_DVALID, P2A_TREADY;
   always @ (posedge CLK) begin
      P2A_CNT <= RST ? 0 : P2A_DVALID ? P2A_CNT+1 : P2A_CNT;
      P2A_DVALID <= (($random() & 8'hff) > 200) & (P2A_CNT <= 7) & (CNT > 10) ;
      P2A_TREADY <= (($random() & 8'hff) > 200);
   end

   wire [63:0] P2A_D = ( (P2A_CNT== 0) ? { 8'h01, 56'h00} :
                         (P2A_CNT== 1) ? { 8'h01, 56'h01} :
                         (P2A_CNT== 2) ? { 8'h01, 56'h02} :
                         (P2A_CNT== 3) ? { 64'h04 } :
                         (P2A_CNT== 4) ? { 16'h1234, 48'h01 } :
                         (P2A_CNT== 5) ? { 16'h1234, 48'h02 } :
                         (P2A_CNT== 6) ? { 16'h1234, 48'h03 } :
                         (P2A_CNT== 7) ? { 16'h1234, 48'h04 } : 64'hx );
   

   wire	       A2P_TREADY;
   port2axis # (.TLAST_Enable(1)) uut_p2a
     ( .CLK(CLK), .RST(RST),
       
       .D      (P2A_D),
       .D_VALID(P2A_DVALID),
       .D_BP   (),

       .M_AXIS_TDATA (),
       .M_AXIS_TVALID(), 
       .M_AXIS_TLAST (),
       .M_AXIS_TREADY(/*P2A_TREADY */ A2P_TREADY) );

   axis2port uut_a2p
     ( .CLK(CLK), .RST(RST),
       .S_AXIS_TDATA (uut_p2a.M_AXIS_TDATA),
       .S_AXIS_TVALID(uut_p2a.M_AXIS_TVALID),
       .S_AXIS_TREADY(A2P_TREADY),

       .Q(),
       .Q_BP(0),
       .Q_VALID() );

   
endmodule

`endif

`default_nettype wire
