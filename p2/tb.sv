/**************************\
* Paul Kennedy <pmkenned>  *
* 18-341                   *
* Project 2 testbench      *
* 28 February, 2011        *
\**************************/

module testbench
  (output logic b_Clock, b_Reset_L);

	reg [7:0] data_val_1, data_val_2, data_val_3; // hold various data to be written
	reg [7:0] data_val_4, data_val_5, data_val_6; // spots for reading back contents of memory
	reg [15:0] addr_val_1, addr_val_2, addr_val_3;

	// used for determining if test cases passed. See more later.
	integer page01Match;
	integer page10Match;
	integer persist1, persist2, persist3;

	always #2 b_Clock = ~b_Clock;
  
	initial begin
		b_Clock = 1'b0;
		b_Reset_L = 1'b0;

		// these integers being 0 indicates failure
		// (I'm assuming their tests fail until proven otherwise)
		page01Match = 0;
		page10Match = 0;

		repeat (2) @(posedge b_Clock);
		b_Reset_L <= 1'b1;
		repeat (4) @(posedge b_Clock);

		/****************************************************************************\
		// PERSISTENCE TESTS
		// The code segment below attempts to show that the memories are persistent
		// That is, when you write to the memory, that the value stays there.
		// I test this by writing to several memory locations and then reading back
		// from them. If the values written in match the values read back out, the
		// test cases pass.
		// persist1, persist2, and persist3 are the boolean variables which indicate
		// success or failure for the three tests cases.
		\****************************************************************************/

		$display("=====================================================================");
		$display("|          Attempting to show that memories are persistent          |");
		$display("=====================================================================");

		// assume failure until proven otherwise
		persist1 = 0;
		persist2 = 0;
		persist3 = 0;

		// set some sample test data and addresses
		addr_val_1 = 16'h7F11;
		addr_val_2 = 16'h7F22; // different column, same row
		addr_val_3 = 16'h7E11; // different row, same column
		data_val_1= 8'hAB;
		data_val_2 = 8'hCD;
		data_val_3 = 8'hEF;

		// first, write to several memory locations
		p.writeMem(addr_val_1,data_val_1);
		p.writeMem(addr_val_2,data_val_2);
		p.writeMem(addr_val_3,data_val_3);

		// then, read back from those locations to make sure they are persistent
		p.readMem(addr_val_1,data_val_4);
		p.readMem(addr_val_2,data_val_5);
		p.readMem(addr_val_3,data_val_6);

		// print results of each test case
		if(data_val_1 === data_val_4) begin
			$display("Success! Value written to address %x persisted",addr_val_1);
			persist1 = 1'b1;
		end else
			$display("Failure: Value written to address %x did not persist",addr_val_1);

		if(data_val_2 === data_val_5) begin
			$display("Success! Value written to address %x persisted",addr_val_2);
			persist2 = 1'b1;
		end else
			$display("Failure: Value written to address %x did not persist",addr_val_2);

		if(data_val_3 === data_val_6) begin
			$display("Value written to address %x persisted",addr_val_3);
			persist3 = 1'b1;
		end else
			$display("Failure: Value written to address %x did not persist",addr_val_3);

		// print final result
		$display("=====================================================================");
		if(persist1 && persist2 && persist3)
			$display("|                     Memories are persistent!                      |");
		else
			$display("|                   Memories are not persistent!                    |");
		$display("=====================================================================\n");
	  
		/****************************************************************************\
		// DISTINCTNESS TESTS
		// The following code segment attempts to show that memories are distinct
		// That is, when you write to one memory page, it writes to it only and not
		// any other. I test this by writing to page 01, then writing to page 10 in
		// the same row and column.
		// I then read back out the data written to them. If the memories were not 
		// distinct, then one of the values would be overwritten. If they are unique,
		// this proves the memories are distinct.
		// The variables here are page01Match and page10Match.
		\****************************************************************************/

		$display("=====================================================================");
		$display("|           Attempting to show that memories are distinct           |");
		$display("=====================================================================");

		addr_val_1 = 16'h7F11;	// page 01
		addr_val_2 = 16'hBF11;	// page 10

		// write the data to the two memories
		p.writeMem(addr_val_1,data_val_1); // write to page 01
		p.writeMem(addr_val_2,data_val_2); // write to page 10
		// read back the data from the two memories
		p.readMem(addr_val_1,data_val_4); // read back from page 01
		p.readMem(addr_val_2,data_val_5); // read back from page 10

		// print the test case results
		if(data_val_1 === data_val_4) begin
			$display("Value written (%d) to page 01 matches value read from page 01",data_val_1);
			page01Match = 1'b1;
		end else
			$display("Value written (%d) to page 01 doesn't match value read from page 01 (%d)",data_val_1,data_val_4);
			
		if(data_val_2 === data_val_5) begin
			$display("Value written (%d) to page 10 matches value read from page 10",data_val_2);
			page10Match = 1'b1;
		end else
			$display("Value written (%d) to page 10 doesn't match value read from page 10 (%d)",data_val_2,data_val_5);

		// print the final results
		$display("=====================================================================");
		if(page01Match==1 && page10Match==1)
			$display("|                      Memories are distinct!                       |");
		else
			$display("|                    Memories are not distinct!                     |");
		$display("=====================================================================\n");

		/****************************************************************************\
		// UNBOUNDED WAIT TEST
		// The following code tests that the memory handles delays between the upper
		// and lower addresses of up to 20.
		// I do this by forcing the delay variable (local to the processor module) to
		// be 20. If the memory still handles our request (that is, writes to memory 
		// and reads that value back), then it passes the test.
		\****************************************************************************/

		$display("=====================================================================");
		$display("|                Testing response to unbounded waits                |");
		$display("=====================================================================");

		force p.delay = 20;

		p.writeMem(addr_val_1,data_val_1);
		p.readMem(addr_val_1,data_val_4);

		release p.delay;

		$display("=====================================================================");
		if(data_val_1 === data_val_4)
			$display("|                      Memory returned data!!                       |");
		else
			$display("|                   Memory did not return data!                     |");
		$display("=====================================================================\n");

		/****************************************************************************\
		// ZERO TIME DELAY TEST
		// The following code tests that the memory can write properly when there is
		// no delay between the upper and lower address (there is never a delay between
		// the lower address bits and the data, thus the three things are back to back)
		// I do this by forcing delay to be 0.
		\****************************************************************************/

		$display("=====================================================================");
		$display("|                Testing response to zero-time delay                |");
		$display("=====================================================================");

		force p.delay = 0;

		addr_val_1 = 16'h7F11;
		addr_val_2 = 16'h7E11;
		data_val_1 = 8'h43; 
		data_val_2 = 8'h78; 
		p.writeMem(addr_val_1,data_val_1);
		p.writeMem(addr_val_2,data_val_2);
		p.readMem(addr_val_1,data_val_4);

		release p.delay;

		$display("=====================================================================");
		if(data_val_1 === data_val_4)
			$display("|                      Memory returned data!!                       |");
		else
			$display("|                   Memory did not return data!                     |");
		$display("=====================================================================\n");

		/****************************************************************************\
		// NON-EXISTENT MEMORY TEST
		// The following code tests that the readMem task times out after 20 clock
		// cycles if there was no response from memory (that is, b_dValid_L is never
		// asserted because there is no memory with a corresponding page address).
		// I test this by trying to write to and then read from an invalid page address.
		// If the readMem task returns instead of waiting infinitely, then we pass this
		// case.
		// PLEASE NOTE: I have left asserting reset up to the testbench. This is because
		// the reset signal is an output of the testbench (I could have had the processor
		// module force reset but this wouldn't be synthesizable and it seemed like the
		// wrong thing to do -- especially since the lab handout says "the testbench
		// should automatically reset the whole system", not "the processor module" or
		// any such thing.
		// After calling readMem, one should check p.timed_out. If this is asserted, this
		// is how the processor lets the testbench know that the task timed out.
		\****************************************************************************/

		$display("=====================================================================");
		$display("|                   Testing for non-existent memory                 |");
		$display("=====================================================================");

		addr_val_1 = 16'h3F11; // 00 is a non-existing page
		data_val_1 = 8'h27;

		p.writeMem(addr_val_1,data_val_1);
		p.readMem(addr_val_1,data_val_4);

		if(p.timed_out) begin
			$display("The readMem task timed out while waiting for a response from memory!");
			$display("Resetting system!");
			b_Reset_L = 1'b0;
			@(posedge b_Clock);
			b_Reset_L = 1'b1;
			repeat(2) @(posedge b_Clock);
		end

		$display("=====================================================================");
		$display("|             We're still here... hooray!!!!!!!!!             |");
		$display("=====================================================================");

		$finish;

	end // initial begin

endmodule
