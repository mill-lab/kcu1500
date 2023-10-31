`timescale 1ns/1ps
`default_nettype none

module port2axis
  ( input wire CLK, RST,
    input wire [7:0][63:0]  D,
    input wire         D_VALID,
    output wire        D_BP,

    output wire [7:0][63:0] M_AXIS_TDATA,
    output wire        M_AXIS_TVALID, M_AXIS_TLAST,
    input wire         M_AXIS_TREADY );

   parameter TLAST_Enable = 0;
   
   // ------------------------------
   // Register input signals
   
   reg           DV_R;
   reg [7:0][63:0]          D_R;

   always @ (posedge CLK) begin
      DV_R <= D_VALID;
      D_R  <= D;
   end

   wire FULL, AFULL;
   assign D_BP = AFULL | FULL;

   // need to change fifo to xpm

   fwft_64x512_afull fifo
     ( .clk      (CLK),        // I
       .srst     (RST),        // I
       
       .din      (D_R),        // I [63:0]
       .wr_en    (DV_R),       // I
       .full     (FULL),       // O
       .prog_full(AFULL),      // O

       .rd_en    (M_AXIS_TREADY),    // I
       .dout     (M_AXIS_TDATA),     // O [63:0]
       .empty    (),                 // O
       .valid    (M_AXIS_TVALID)     // O
       );

   generate
      if (TLAST_Enable == 1) begin : tlast_gen
         reg [31:0] PAYLOAD_TOGO;
         reg [1:0]  STAT;

         always @ (posedge CLK) begin
            if (RST) begin
               STAT <= 'b01;
            end else begin
               if (M_AXIS_TREADY & M_AXIS_TVALID) begin
                  case (STAT)
                    'b01: begin
                       if (M_AXIS_TDATA[63:56] != 8'h01) begin
                          PAYLOAD_TOGO <= M_AXIS_TDATA[31:0];
                          STAT <= 'b10;
                       end
                    end

                    'b10: begin
                       PAYLOAD_TOGO <= PAYLOAD_TOGO - 1;
                       if (PAYLOAD_TOGO==1) STAT <= 'b01;
                    end
                    default: STAT <= 'b01;
                         
                  endcase // case (STAT)
               end // TREADY & TVALID
            end
         end

         assign M_AXIS_TLAST = (PAYLOAD_TOGO==1) & M_AXIS_TVALID & STAT[1];
         
      end else begin : no_tlast_gen
         assign M_AXIS_TLAST = 1 ;
      end
   endgenerate
   
endmodule // port2axis

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

module axis2port
  ( input wire CLK, RST,
    input wire         S_AXIS_TVALID, S_AXIS_TLAST,
    input wire [7:0][63:0]  S_AXIS_TDATA,
    output wire        S_AXIS_TREADY,

    output wire [7:0][63:0] Q,
    output wire        Q_VALID,
    input wire         Q_BP
    );

   wire                FULL, AFULL, VALID;
   assign S_AXIS_TREADY = ~(FULL | AFULL);
   wire                WE = S_AXIS_TVALID & S_AXIS_TREADY;
   
   fwft_64x512_afull fifo
     ( .clk      (CLK),        // I
       .srst     (RST),    // I
       .din      (S_AXIS_TDATA),       // I [63:0]
       .wr_en    (WE), // I
       .full     (FULL   ),  // O
       .prog_full(AFULL  ),   // O

       .rd_en    (~Q_BP  ),    // I
       .dout     (Q      ),    // O [63:0]
       .empty    (),  // O
       .valid    (VALID  )  // O
       );

   assign Q_VALID = VALID & ~Q_BP;
endmodule // axis2port

// ----------------------------------------------------------------------

`ifdef PORT2AXIS_TB_EN
module tb();
   parameter real Step = 10.0;

   reg            CLK = 1;
   always # (Step/2) CLK <= ~CLK;

   reg            RST;
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
   reg P2A_DVALID, P2A_TREADY;
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
                         

   wire        A2P_TREADY;
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
