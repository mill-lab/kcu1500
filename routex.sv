`timescale 1ns/1ps
`default_nettype none
module routex # ( parameter NumPorts = 4, PassThrough=4'b0011 )
   ( input wire CLK, RST,

     input wire [NumPorts-1:0][7:0][63:0]  D,
     input wire [NumPorts-1:0]		   D_VALID,
     output wire [NumPorts-1:0]		   D_BP,

     output wire [NumPorts-1:0][7:0][63:0] Q,
     output wire [NumPorts-1:0]		   Q_VALID,
     input wire [NumPorts-1:0]		   Q_BP,
     output wire [NumPorts-1:0]		   Q_SOF   // used to generate PE_RST
     );

   // RX buffer to routex core
   wire [NumPorts-1:0][7:0][63:0]	   Di;
   wire [NumPorts-1:0]			   D_VALIDi, D_BPi, COLi;
   
   // Passthrough signals
   wire [NumPorts-1:0][7:0][63:0]	   PT;
   wire [NumPorts-1:0]			   PT_VALID;
   
   generate
      genvar				   i;
      
      for (i=0; i<NumPorts; i=i+1) begin : rxbuf_gen
         wire [7:0][63:0] BUF_D  = PT_VALID[i] ? PT[i] : D[i];
         wire		  BUF_DV = D_VALID[i] | PT_VALID[i];

         routex_rx_buf rxbuf
             ( .CLK(CLK), .RST(RST),

               .D_VALID(BUF_DV),                     // I
               .D_BP   (D_BP[i]),                    // O
               .D      (BUF_D),                      // I

               .Q_VALID(D_VALIDi[i]),                // O
               .Q_BP   (D_BPi   [i]),                // I
               .Q      (Di      [i]),                // O
               .COLLISION(COLi  [i])                 // I
               );
      end
   endgenerate
   
   routex_core # (.NumPorts(NumPorts), .PassThrough(PassThrough) ) rc
     ( .CLK(CLK), .RST(RST),
      
       .D      (Di),         // I
       .D_VALID(D_VALIDi),   // I
       .D_BP   (D_BPi),      // O
       .COLLISION(COLi),     // O
       
       .PT       (PT),       // O
       .PT_VALID (PT_VALID), // O
       
       .Q      (Q),          // O
       .Q_VALID(Q_VALID),    // O
       .Q_BP   (Q_BP),       // I
       .Q_SOF  (Q_SOF)       // O
      );
   

endmodule // routex

module routex_rx_buf
  ( input wire CLK, RST,
    
    input wire		    D_VALID,
    input wire [7:0][63:0]  D,
    output wire		    D_BP,

    output wire		    Q_VALID,
    output wire [7:0][63:0] Q,
    input wire		    Q_BP,
    input wire		    COLLISION
    );
   
   wire [7:0][63:0]	    FIFO_Q;
   wire			    RD_EN;
   wire			    FIFO_VALID;
   
// xpm_fifo_sync: Synchronous FIFO
// Xilinx Parameterized Macro, version 2022.2

xpm_fifo_sync #(
   .CASCADE_HEIGHT(0),        // DECIMAL
   .DOUT_RESET_VALUE("0"),    // String
   .ECC_MODE("no_ecc"),       // String
   .FIFO_MEMORY_TYPE("auto"), // String
   .FIFO_READ_LATENCY(0),     // DECIMAL
   .FIFO_WRITE_DEPTH(512),    // DECIMAL
   .FULL_RESET_VALUE(0),      // DECIMAL
   .PROG_EMPTY_THRESH(10),    // DECIMAL
   .PROG_FULL_THRESH(400),    // DECIMAL
   .RD_DATA_COUNT_WIDTH(1),   // DECIMAL
   .READ_DATA_WIDTH(512),     // DECIMAL
   .READ_MODE("fwft"),        // String
   .SIM_ASSERT_CHK(0),        // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .USE_ADV_FEATURES("1002"), // String
   .WAKEUP_TIME(0),           // DECIMAL
   .WRITE_DATA_WIDTH(512),    // DECIMAL
   .WR_DATA_COUNT_WIDTH(1)    // DECIMAL
  )
   xpm_fifo_sync_inst (.data_valid(FIFO_VALID), // O
		       .dout(FIFO_Q),           // O
		       .prog_full(D_BP),        // O
		       .full(),                 // for test
		       .din(D),                 // I
		       .rd_en(RD_EN),           // I
		       .rst(RST),               // I
		       .wr_clk(CLK),            // I
		       .wr_en(D_VALID)          // I
		       );	


   // EOF detector
   reg [31:0]		    Q_TOGO, Q_TOGO_R;
   wire	[7:0]		    LEN_FLG;
   wire			    EOF = (Q_VALID & Q_TOGO<=8 & Q_TOGO != 0);
   
   always @ (posedge CLK) begin
      if (RST | COLLISION) begin
         Q_TOGO <= 0;
      end else begin
         if (Q_VALID) begin
            if (Q_TOGO==0) begin
               Q_TOGO   <=  (Q[7][63:56]==8'h00) ? Q[7][31:0] : 0;
            end else begin
               Q_TOGO <= Q_TOGO - 8;
            end
         end
      end
   end

   // Write to Backup
   
   reg                   COLLISION_R;
   reg [15:0][7:0][63:0] BUP;
   reg [3:0]		 BUP_WA, BUP_WA_R; // address for 16 words
   reg			 RE_TX;
   
   always @ (posedge CLK) begin
      COLLISION_R <= COLLISION;
      
      if (RST) begin
         BUP_WA <= 0;
         BUP_WA_R <= 8'hff;
         RE_TX  <= 0;
      end else begin
         if (EOF) begin
            BUP_WA <= 0;
            BUP_WA_R <= 8'hff;
            RE_TX  <= 0;
         end else begin
            if (COLLISION)  RE_TX <= 1;

//          if (~COLLISION & Q_VALID & ~RE_TX) begin
            if (~COLLISION_R & COLLISION) begin
               BUP_WA_R <= BUP_WA;
               BUP_WA <= 0;
            end else if (~COLLISION & Q_VALID & ~&BUP_WA) begin
               BUP_WA <= BUP_WA+1;
               BUP[BUP_WA] <= Q;
            end
         end
      end
   end

   // Read from Backup

   reg [3:0] BUP_RA;
   
   always @ (posedge CLK) begin
      if (RST) begin
         BUP_RA <= 0;
      end else begin
         if (COLLISION | EOF)
           BUP_RA <= 0;
         else begin
            if (RE_TX) begin
               if(~Q_BP & (BUP_RA != BUP_WA_R)) BUP_RA <= BUP_RA+1;
            end
         end
      end
   end

   wire RE_TX_DONE = RE_TX & (BUP_WA_R==BUP_RA);
   
   assign RD_EN = ~Q_BP & ~COLLISION & (RE_TX ? RE_TX_DONE : 1);

   assign Q = (RE_TX & ~RE_TX_DONE) ? BUP[BUP_RA]  : FIFO_Q;
   assign Q_VALID = RD_EN & FIFO_VALID | (RE_TX & ~COLLISION & ~Q_BP & BUP_WA_R!=BUP_RA) ;

endmodule // routex_rx_buf

module routex_core # ( parameter NumPorts = 4, PassThrough=4'b0011 )
   ( input wire CLK, RST,

     input wire [NumPorts-1:0][7:0][63:0]  D,
     input wire [NumPorts-1:0]		   D_VALID,
     output wire [NumPorts-1:0]		   D_BP,
     output wire [NumPorts-1:0]		   COLLISION,

     output wire [NumPorts-1:0][7:0][63:0] PT,
     output wire [NumPorts-1:0]		   PT_VALID,
   
     output wire [NumPorts-1:0][7:0][63:0] Q,
     output wire [NumPorts-1:0]		   Q_VALID,
     input wire [NumPorts-1:0]		   Q_BP,
     output wire [NumPorts-1:0]		   Q_SOF
     );

   // - - - - - - - - - - - - - - - - - - - - 
   // Crossbar outputs
   
   wire [NumPorts-1:0][7:0][63:0]	  CB_Q;
   wire [NumPorts-1:0]			  CB_Q_HDR_VALID, CB_Q_PLD_VALID;
   
   // - - - - - - - - - - - - - - - - - - - - 
   // Routex sink ports x4
   
   wire [NumPorts-1:0][7:0]		  DEST;
   wire [NumPorts-1:0]			  DEST_VALID, SOF, EOF, HDR_VALID, PLD_VALID;
   wire [NumPorts-1:0][7:0][63:0]	  FRAME;

   reg [NumPorts-1:0][7:0][63:0]	  D_R;
   reg [NumPorts-1:0]			  D_VR;

   always @ (posedge CLK) begin
      D_R <= D;
      D_VR <= D_VALID;
   end

   genvar i;
   generate
      for (i=0; i<NumPorts; i=i+1) begin : routex_sink_gen
         wire [7:0][63:0] SINK_D;
         wire		  SINK_D_VALID;

         // per lane connection signals
         wire [7:0][63:0] Dc    = D_R [i];
         wire [7:0][63:0] CB_Qc = CB_Q[i];
         wire [7:0][63:0]	  PTc;
         assign PT[i] = PTc;
         
         // Header pass-through logic
         if (PassThrough[i]) begin
            // pass-through logic before routex_sink for PEs
            assign SINK_D       = Dc;
            assign SINK_D_VALID = D_VR[i];
            assign Q_VALID[i]   = CB_Q_PLD_VALID[i];

            assign PTc          = CB_Q_HDR_VALID[i] ? CB_Qc : 0;
            assign PT_VALID[i]  = CB_Q_HDR_VALID[i];
         end else begin // No pass-through ports (PCIe/Aurora)
            assign SINK_D       = Dc;
            assign SINK_D_VALID = D_VR[i];
            assign Q_VALID[i]   = CB_Q_PLD_VALID[i] | CB_Q_HDR_VALID[i];
            assign PT_VALID[i]  = 0;
         end
         
         routex_sink uut_rs
           ( .CLK(CLK), .RST(RST | COLLISION[i]),
            
             // from source
             .D      (SINK_D), 
             .D_VALID(SINK_D_VALID),
            
             // to matrix 
             .DEST(DEST[i]), 
             .DEST_VALID(DEST_VALID[i]),
            
             .SOF(SOF[i]), .EOF(EOF[i]),
             .FRAME(FRAME[i]),
             .HDR_VALID (HDR_VALID[i]),
             .PLD_VALID(PLD_VALID[i])
             );
      end // block: routex_sink_gen
   endgenerate

   routex_cb # ( .NumPorts(NumPorts) ) cb
     ( .CLK(CLK), .RST(RST),
       .D   ( FRAME ),
       .DEST( DEST ),
       .DEST_VALID(DEST_VALID),
       .D_HDR_VALID(HDR_VALID),
       .D_PLD_VALID(PLD_VALID),
       .D_SOF(SOF),
       .D_EOF(EOF),
       .D_BP (D_BP),
       .COLLISION(COLLISION),
       
       .Q          (CB_Q),
       .Q_HDR_VALID(CB_Q_HDR_VALID),
       .Q_PLD_VALID(CB_Q_PLD_VALID),
       .Q_SOF      (Q_SOF),
       .Q_EOF      (),
       .Q_BP       (Q_BP)
       );

   assign Q = CB_Q;
   // Q_VALID is under control of PassThrough[x]
   
endmodule // routex_core

module routex_cb # ( parameter NumPorts = 4 )
   ( input wire CLK, RST,

     input wire [NumPorts-1:0][7:0][63:0]  D,
     input wire [NumPorts-1:0][7:0]	   DEST,
     input wire [NumPorts-1:0]		   DEST_VALID, D_HDR_VALID, D_PLD_VALID, 
     input wire [NumPorts-1:0]		   D_SOF, D_EOF,
     output wire [NumPorts-1:0]		   D_BP, COLLISION,
   
     output wire [NumPorts-1:0][7:0][63:0] Q,
     output wire [NumPorts-1:0]		   Q_HDR_VALID, Q_PLD_VALID, Q_SOF, Q_EOF,
     input wire [NumPorts-1:0]		   Q_BP
     );

   wire [NumPorts-1:0][NumPorts-1:0]	  D_BPi, COLi;
   
   genvar				  i;
   generate
      for (i=0; i<NumPorts; i=i+1) begin : mux_gen

         routex_mux # ( .NumPorts(NumPorts), .PortNo(i+1) ) rm
             ( .CLK(CLK), .RST(RST),
               .D(D), 
               .DEST       (DEST),        .DEST_VALID (DEST_VALID),
               .D_HDR_VALID(D_HDR_VALID), .D_PLD_VALID(D_PLD_VALID),
               .D_SOF      (D_SOF),       .D_EOF      (D_EOF),
               .D_BP       (D_BPi[i]),
               .COLLISION  (COLi [i]),

               .Q          (Q          [i]),
               .Q_HDR_VALID(Q_HDR_VALID[i]),
               .Q_PLD_VALID(Q_PLD_VALID[i]),
               .Q_SOF      (Q_SOF      [i]),
               .Q_EOF      (Q_EOF      [i]),
               .Q_BP       (Q_BP       [i])
               );

      end
   endgenerate

   // OR'ing all D_BPi[] 
   //    assign D_BP = D_BPi[0] | D_BPi[1] | D_BPi[2] | D_BPi[3]; 

   channel_or # ( .Width(NumPorts), .NumCh(NumPorts) ) d_bp_or
     ( .D(D_BPi), .Q(D_BP) );


   channel_or # ( .Width(NumPorts), .NumCh(NumPorts) ) col_or
     ( .D(COLi), .Q(COLLISION) );
   
endmodule // routex_cb


module channel_or # ( parameter Width=64, NumCh=4 )
   ( input wire [Width-1:0][NumCh-1:0] D,
     output wire [Width-1:0] Q );

   wire [Width-1:0][NumCh-1:0] TEMP;

   assign TEMP[0] = D[0];

   generate
      genvar		       i;
      for (i=1; i<NumCh; i=i+1) begin : or_gen
         assign TEMP[i] = D[i] | TEMP[i-1];
      end
   endgenerate

   assign Q = TEMP[NumCh-1];
   
endmodule // channel_or

module routex_mux # (parameter NumPorts = 4, PortNo = 1) // n to 1 switch
   ( input wire CLK, RST,

     input wire [NumPorts-1:0][7:0][63:0] D,
     input wire [NumPorts-1:0][7:0]	  DEST,
     input wire [NumPorts-1:0]		  DEST_VALID, D_HDR_VALID, D_PLD_VALID,
     input wire [NumPorts-1:0]		  D_SOF, D_EOF,
     output wire [NumPorts-1:0]		  D_BP, COLLISION,

     output wire [7:0][63:0]		  Q,
     output wire			  Q_HDR_VALID, Q_PLD_VALID, Q_SOF, Q_EOF,
     input wire				  Q_BP
     );

   genvar				  i;
   
   // - - - - - - - - - - - - - - - - - - - -
   // SOF detection

   /*
   wire [NumPorts-1:0]		     SOF_DETECT;
   reg [NumPorts-1:0]		     SOF_DETECTr;
   
   assign SOF_DETECT[3] = D_SOF[3] & (DEST[3] == PortNo);
   assign SOF_DETECT[2] = D_SOF[2] & (DEST[2] == PortNo);
   assign SOF_DETECT[1] = D_SOF[1] & (DEST[1] == PortNo);
   assign SOF_DETECT[0] = D_SOF[0] & (DEST[0] == PortNo);
   */

   wire [NumPorts-1:0]           SOF_DETECT;

   generate
      for (i=0; i<NumPorts; i=i+1) begin : sof_detect_gen
         assign SOF_DETECT[i] = D_SOF[i] & (DEST[i] == PortNo);
      end
   endgenerate

   // - - - - - - - - - - - - - - - - - - - -
   // Source switching on SOF_DETECT and corresponding EOF

   /*
   reg [NumPorts-1:0]		     SRC_PORT;
   always @ (posedge CLK) begin
      if (RST) begin
         SRC_PORT <= 0;
	 SOF_DETECTr <= 0;
      end else begin
	 SOF_DETECTr <= SOF_DETECT;
         if (SRC_PORT==0) begin
            casex (SOF_DETECT)
              4'bxxx1: SRC_PORT <= 4'b0001;
              4'bxx10: SRC_PORT <= 4'b0010;
              4'bx100: SRC_PORT <= 4'b0100;
              4'b1000: SRC_PORT <= 4'b1000;
              default: SRC_PORT <= 0;
            endcase // casex (SOF_DETECT)
         end else begin
            if (SRC_PORT & D_EOF) SRC_PORT <= 0;
         end
      end
   end // always @ (posedge CLK)
   */

   wire [NumPorts-1:0] SRC_PORTi;
   
   router_ch_sel # ( .NumCh(NumPorts) ) cs 
     ( .REQ(SOF_DETECT), .SEL(SRC_PORTi) );
   
   reg [NumPorts-1:0]  SRC_PORT;

   always @ (posedge CLK) begin
      if (RST) begin
         SRC_PORT <= 0;
      end else begin
         if (SRC_PORT==0) begin
            SRC_PORT <= SRC_PORTi;
         end else begin
            if (SRC_PORT & D_EOF) SRC_PORT <= 0;
         end
      end
   end
   
   // - - - - - - - - - - - - - - - - - - - -
   // Collision detection

   reg [NumPorts-1:0] CD;
   wire		      EOF_DETECT = |(SRC_PORT & D_EOF);

   /*
    always @ (posedge CLK) begin
    if (RST) begin
    CD <= 0;
      end else begin
    CD <= (SRC_PORT==0) ? (SOF_DETECT & ~SRC_PORTi) :  // may be slow...
    (EOF_DETECT ? 0 :  // end of session
    CD | SOF_DETECT); // secondary collision 
      end
   end
    */

   reg [2:0]	      EOF_CNT;
   wire		      EOF_CNT_FULL = &EOF_CNT;
   
   always @ (posedge CLK) begin
      if (RST) begin
         CD <= 0;
         EOF_CNT <= 0;
      end else begin
         if (EOF_DETECT) EOF_CNT <= 1;
         else EOF_CNT <= (EOF_CNT != 0) ? EOF_CNT+1 : 0;

	 /*
         if (CD==0) begin
            CD <= (SOF_DETECTr & ~SRC_PORT);
         end else begin
            CD <= EOF_CNT_FULL ? 0 : // end of session
                  CD | SOF_DETECT; // secondary collision
	 end
	 */

	 if (CD==0) begin
            CD <= (SRC_PORT==0) ? (SOF_DETECT & ~SRC_PORTi) : 
                  (SOF_DETECT & ~SRC_PORT);

	    /* 
	    CD <= SOF_DETECT & (SRC_PORT | SRC_PORTi); // may be better than above
	    */
	    
         end else begin
            CD <= EOF_CNT_FULL ? 0 : // end of session
                  CD | SOF_DETECT; // secondary collision
         end
      end
   end
   
   assign COLLISION = CD;

   // - - - - - - - - - - - - - - - - - - - - 
   // registered output

   /*
   reg [7:0][63:0] Qi;
   reg		   Q_HDR_VALIDi, Q_PLD_VALIDi, Q_SOFi, Q_EOFi;
   reg [3:0]	   D_BPi;

   always @ (posedge CLK) begin
      Q_SOFi <= (SRC_PORT==0) & (|SOF_DETECT);
      Q_EOFi <= |(D_EOF & SRC_PORT);
      Q_HDR_VALIDi <= |(D_HDR_VALID & SRC_PORT);
      Q_PLD_VALIDi <= |(D_PLD_VALID & SRC_PORT);

      Qi <= SRC_PORT[3] ? D[3] :
            SRC_PORT[2] ? D[2] :
            SRC_PORT[1] ? D[1] :
            SRC_PORT[0] ? D[0] : 64'h0;

      D_BPi <= Q_BP ? SRC_PORT : 0;
   end
   
   assign Q     = Qi;
   assign Q_HDR_VALID = Q_HDR_VALIDi;
   assign Q_PLD_VALID = Q_PLD_VALIDi;
   assign Q_SOF = Q_SOFi;
   assign Q_EOF = Q_EOFi;
   assign D_BP  = D_BPi;
   */

   wire [7:0][63:0]     Qi_TMP;
   reg [7:0][63:0]	Qi;
   reg			Q_HDR_VALIDi, Q_PLD_VALIDi, Q_SOFi, Q_EOFi;
   reg [NumPorts-1:0]	D_BPi;

   channel_mux # (.Width(512), .NumCh(NumPorts) ) dmux 
     ( .D(D), .SEL(SRC_PORT), .Q(Qi_TMP) );
   
   always @ (posedge CLK) begin
      Q_SOFi <= (SRC_PORT==0) & (|SOF_DETECT);
      Q_EOFi <= |(D_EOF & SRC_PORT);
      Q_HDR_VALIDi <= |(D_HDR_VALID & SRC_PORT);
      Q_PLD_VALIDi <= |(D_PLD_VALID & SRC_PORT);

      Qi <= Qi_TMP;
      D_BPi <= Q_BP ? SRC_PORT : 0;
   end
   
   assign Q     = Qi;
   assign Q_HDR_VALID = Q_HDR_VALIDi;
   assign Q_PLD_VALID = Q_PLD_VALIDi;
   assign Q_SOF = Q_SOFi;
   assign Q_EOF = Q_EOFi;
   assign D_BP  = D_BPi;
   
endmodule // routex_mux

// - - - - - - - - - - - - - - - - - - - - 
// priprity circuit

module router_ch_sel # (parameter NumCh=8 )
   ( input wire [NumCh-1:0] REQ,
     output wire [NumCh-1:0] SEL );

   wire [NumCh-1:0][NumCh-1:0] TEMP;
   assign TEMP[0] = REQ[0] ? 1 : 0;
   
   generate
      genvar		       i;
      for (i=1; i<NumCh; i=i+1) begin : casex_gen
         assign TEMP[i] = (TEMP[i-1]!=0) ? TEMP[i-1] : (REQ[i] ? 1 << i : 0);
      end
   endgenerate

   assign SEL = TEMP[NumCh-1];
endmodule // channel_sel

// - - - - - - - - - - - - - - - - - - - - 
// Channel MUX with one-hot select signal

module channel_mux # ( parameter Width=512, NumCh=4 )
   ( input wire [NumCh-1:0][Width-1:0] D,
     input wire [NumCh-1:0]  SEL,
     output wire [Width-1:0] Q );
   
   wire [NumCh-1:0][Width-1:0] TEMP;
   
   assign TEMP[0] = SEL[0] ? D[0] : 0;

   generate
      genvar                   i;
      for (i=1; i<NumCh; i=i+1) begin : or_gen
         assign TEMP[i] = ( SEL[i] ? D[i] : 0) | TEMP[i-1];
      end
   endgenerate

   assign Q = TEMP[NumCh-1];
   
endmodule // channel_mux

module routex_sink
  ( input wire CLK, RST,

    // Routex ports
    input wire [7:0][63:0] D,
    input wire		   D_VALID,

    output reg [7:0]	   DEST,
    output wire		   DEST_VALID,
  
    output reg		   SOF, EOF,
    output reg [7:0][63:0] FRAME,
    output reg		   HDR_VALID,
    output reg		   PLD_VALID
    );

   // Receiver state machine
   reg [2:0]		   STAT, STAT_R; // idle (dest), header, payload
   reg [31:0]		   D_TOGO;
   wire [7:0]		   HDR_FLG;
   /*
    D[511:448] D[7][63:0]
    D[447:384] D[6][63:0]
    D[383:320] D[5][63:0]
    D[319:256] D[4][63:0]
    D[255:192] D[3][63:0]
    D[191:128] D[2][63:0]
    D[127: 64] D[1][63:0]
    D[ 63:  0] D[0][63:0]
    */
   assign HDR_FLG[7] = (D[7][63:56] == 8'h1); // D[511:504]
   assign HDR_FLG[6] = (D[6][63:56] == 8'h1); // D[447:440]
   assign HDR_FLG[5] = (D[5][63:56] == 8'h1); // D[383:376]
   assign HDR_FLG[4] = (D[4][63:56] == 8'h1); // D[319:312]
   assign HDR_FLG[3] = (D[3][63:56] == 8'h1); // D[255:248]
   assign HDR_FLG[2] = (D[2][63:56] == 8'h1); // D[191:184]
   assign HDR_FLG[1] = (D[1][63:56] == 8'h1); // D[127:120]
   assign HDR_FLG[0] = (D[0][63:56] == 8'h1); // D[ 63: 56]

   // generate
   //    genvar		   i;
   //    for (i=0; i<8; i=i+1) begin : HDR_FLG_gen
   // 	 assign HDR_FLG[i] = (D[i][63:56] == 1);
   //    end
   // endgenerate

   wire [7:0]		   DEST_FLG;

   router_ch_sel cs
     (.REQ(HDR_FLG), .SEL(DEST_FLG));
   
   reg [7:0][63:0]	   FRAMEr;
   reg			   EOFr, HDR_VALIDr, PLD_VALIDr;
   
   always @ (posedge CLK) begin
      STAT_R <= STAT;
      FRAME <= FRAMEr;
      HDR_VALID <= HDR_VALIDr;
      PLD_VALID <= PLD_VALIDr;
      EOF <= EOFr;
      if (RST) begin
         STAT <= 3'b001;
         SOF <= 0;
         EOFr <= 0;
         D_TOGO <= 0;
	 end else begin
         case (STAT)
           3'b001: begin // waiting destination
              EOFr <= 0;
              PLD_VALIDr <= 0;
	      if (D_VALID & |DEST_FLG) begin // make DEST and change destination flag
                 {DEST, FRAMEr} <= DEST_FLG[7] ? {D[7],         8'h02, D[7][55:0], D[6:0]} :
				   DEST_FLG[6] ? {D[6], D[7  ], 8'h02, D[6][55:0], D[5:0]} :
				   DEST_FLG[5] ? {D[5], D[7:6], 8'h02, D[5][55:0], D[4:0]} :
				   DEST_FLG[4] ? {D[4], D[7:5], 8'h02, D[4][55:0], D[3:0]} :
				   DEST_FLG[3] ? {D[3], D[7:4], 8'h02, D[3][55:0], D[2:0]} :
				   DEST_FLG[2] ? {D[2], D[7:3], 8'h02, D[2][55:0], D[1:0]} :
				   DEST_FLG[1] ? {D[1], D[7:2], 8'h02, D[1][55:0], D[  0]} :
				   DEST_FLG[0] ? {D[0], D[7:1], 8'h02, D[0][55:0]        } : 64'h0;
		 HDR_VALIDr <= D_VALID;
		 SOF <= 1;
		 if (D[7][63:56] != 0) begin
		    STAT <= 3'b010; // waiting length
		 end else begin // already D_TOGO available
		    D_TOGO <= D[7][31:0];
		    STAT <= 3'b100;
		 end
	      end
	   end

           3'b010: begin
	      SOF <= 0;
	      if (D_VALID & D[7][63:56] == 0) begin
                 D_TOGO <= D[7][31:0];
                 STAT <= 3'b100;
              end
	      FRAMEr <= D;
           end

           3'b100: begin
	      SOF <= 0;
	      HDR_VALIDr <= 0;
              if (D_VALID) begin
                 D_TOGO <= D_TOGO -8;
                 if (D_TOGO <= 8) begin
                    STAT <= 3'b001;
                    EOFr <= 1;
                 end
              end 

              PLD_VALIDr <= D_VALID;
              FRAMEr <= D;
           end
           
           default: begin
              STAT <= 3'b001; end
         endcase
      end
   end

   assign DEST_VALID = |STAT[2:1] | STAT_R[2];
   
endmodule // routex_sink

`default_nettype wire
