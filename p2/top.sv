module top;
	wire        b_Clock, b_Reset_L, b_Start_L, b_re_L, b_dValid_L;
	wire [7:0]  b_Addr, b_Data;
	
	memory #(2'b01) m1(.*);
	memory #(2'b10) m2(.*);
	processor p(.*);
	testbench test(.*);

endmodule
