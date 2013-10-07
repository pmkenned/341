// tests out some reads and writes
module testbench
  (output reg b_Clock, b_Reset_L);

  reg [7:0] data_val_1,data_val_2;

  always #2 b_Clock = ~b_Clock;

  initial begin
	  b_Clock = 1'b0;
	  b_Reset_L = 1'b0;
	  data_val_1= 8'hFF;
	
	  repeat (2) @(posedge b_Clock);
	  b_Reset_L <= 1'b1;

	  repeat (4) @(posedge b_Clock);
	  p.writeMem(16'h7F11,data_val_1);
	  p.writeMem(16'h7F12,data_val_1);
	  repeat (4) @(posedge b_Clock);
	  p.readMem(16'h7F11,data_val_2);
	  if(data_val_1 !== data_val_2)
	    begin
	      $display("--Read failed to return the same value as was written in--");
	      $display("--Returned %h instead of %h--\n",data_val_2,data_val_1);
	    end
	  else
		  $display("--Passed Case--");
	    repeat (4) @(posedge b_Clock);
	    p.readMem(16'h7F12, data_val_2);
	    if(data_val_1 !== data_val_2)
	    begin
	      $display("--Read failed to return the same value as was written in--");
	      $display("--Returned %h instead of %h--\n",data_val_2,data_val_1);
	    end
	  else
		  $display("--Passed Case--");
	  $finish;

end // initial begin
endmodule // testbench

	
