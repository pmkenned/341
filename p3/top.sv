// DO NOT MODIFY THIS FILE

interface usbWires;
	tri0 DP;
	tri0 DM;

endinterface


module top;
  logic clk, rst_L;
    
	usbWires wires();	
  usbDevice dev(.*);
  usbHost host(.*);
  test tb(.*);

endmodule

