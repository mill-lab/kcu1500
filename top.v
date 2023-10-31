`default_nettype none
module top
  (input wire        pcie_perstn, 
   input wire	     pcie_refclk_clk_n,
   input wire	     pcie_refclk_clk_p,
   input wire [7:0]  pci_express_x8_rxn,
   input wire [7:0]  pci_express_x8_rxp,
   output wire [7:0] pci_express_x8_txn,
   output wire [7:0] pci_express_x8_txp);

  wire [511:0] M_AXIS_0_tdata;
   wire [63:0] M_AXIS_0_tkeep;
   wire	       M_AXIS_0_tlast;
   wire	       M_AXIS_0_tready;
   wire	       M_AXIS_0_tvalid;
   wire [511:0]	S_AXIS_0_tdata;
   wire [63:0]	S_AXIS_0_tkeep;
   wire		S_AXIS_0_tlast;
   wire		S_AXIS_0_tready;
   wire		S_AXIS_0_tvalid;
   wire		axi_aclk;
   wire		axi_aresetn;

   design_1 design_1_i
     (.M_AXIS_0_tdata(M_AXIS_0_tdata),
      .M_AXIS_0_tkeep(M_AXIS_0_tkeep),
      .M_AXIS_0_tlast(M_AXIS_0_tlast),
      .M_AXIS_0_tready(M_AXIS_0_tready),
      .M_AXIS_0_tvalid(M_AXIS_0_tvalid),
      .S_AXIS_0_tdata(S_AXIS_0_tdata),
      .S_AXIS_0_tkeep(S_AXIS_0_tkeep),
      .S_AXIS_0_tlast(S_AXIS_0_tlast),
      .S_AXIS_0_tready(S_AXIS_0_tready),
      .S_AXIS_0_tvalid(S_AXIS_0_tvalid),
      .axi_aclk(axi_aclk),
      .axi_aresetn(axi_aresetn),
      .pci_express_x8_rxn(pci_express_x8_rxn),
      .pci_express_x8_rxp(pci_express_x8_rxp),
      .pci_express_x8_txn(pci_express_x8_txn),
      .pci_express_x8_txp(pci_express_x8_txp),
      .pcie_perstn(pcie_perstn),
      .pcie_refclk_clk_n(pcie_refclk_clk_n),
      .pcie_refclk_clk_p(pcie_refclk_clk_p));

   
   axis_data_fifo_0 fifo (.s_axis_aresetn(axi_aresetn),  
			  .s_axis_aclk(axi_aclk),        
			  .s_axis_tvalid(M_AXIS_0_tvalid),    
			  .s_axis_tready(M_AXIS_0_tready),    
			  .s_axis_tdata(M_AXIS_0_tdata),      
			  .s_axis_tkeep(M_AXIS_0_tkeep), 
			  .s_axis_tlast(M_AXIS_0_tlast),
			  .m_axis_tvalid(S_AXIS_0_tvalid),    
			  .m_axis_tready(S_AXIS_0_tready),    
			  .m_axis_tdata(S_AXIS_0_tdata),      
			  .m_axis_tkeep(S_AXIS_0_tkeep), 
			  .m_axis_tlast(S_AXIS_0_tlast)
			  );

   // ila_0 ila (.clk(axi_aclk),
   // 	      .probe0({M_AXIS_0_tdata, M_AXIS_0_tready, M_AXIS_0_tvalid}));
   
   reg [511:0] TDATA_R;
   reg [63:0]  TKEEP_R;
   reg	       TREADY_R, TVALID_R, TLAST_R;

   ila_0 ila (.clk(axi_aclk),
	      .probe0({TREADY_R, TVALID_R, TLAST_R}),
	      .probe1({TDATA_R,   TKEEP_R}) );
   
   always @ (posedge axi_aclk) begin
    //  if (axi_aresetn) begin
	// TDATA_R <= 0;
	// TREADY_R <= 0;
	// TVALID_R <= 0;
    //  end else begin
	 { TDATA_R, TKEEP_R, TREADY_R, TVALID_R, TLAST_R } <= 
	 { M_AXIS_0_tdata, M_AXIS_0_tkeep, M_AXIS_0_tready, M_AXIS_0_tvalid, M_AXIS_0_tlast };
    //  end
   end
endmodule

`default_nettype wire
