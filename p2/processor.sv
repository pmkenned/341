/**************************\
* Paul Kennedy <pmkenned>  *
* 18-341                   *
* Project 2 processor.v    *
* 28 February, 2011        *
\**************************/

module processor
	(input logic		b_Clock, b_Reset_L,
	 output logic		b_Start_L, b_re_L,
	 inout 			b_dValid_L,	
	 output logic [7:0]	b_Addr,
	 inout [7:0]		b_Data);

	logic access;		// signal from the tasks indicating to the interface that we are doing a read or write
	logic read;		// signal from the readMem task indicating that we are doing a read (or write if unasserted)
	logic loAvail;		// signal from tasks indicating the lower address is available to be written to the bus
	logic dataAvail;	// signal from write task indicating data is available to be written to the bus

	logic en_Data;		// enable line for tri-state driver. when asserted, put DataReg on the bus (b_Data)
	logic en_dValid;	// enable line for tri-state driver. when assserted, put b_dValid_L_int on the bus
	logic b_dValid_L_int;	// input  to tri-state driver for b_dValid_L
	logic ld_Data;		// signal from interface FSM telling the DataReg to be loaded with the data from the bus
	logic en_AddrUp;	// puts the upper address bits on the bus at b_Addr
	logic en_AddrLo;	// likewise for lower bits
	logic [7:0] DataReg;	// latches data from bus which is then sent to the testbench in readMem
	logic [15:0] AddrReg;	// holds address from tasks to be but on the bus

	logic [4:0] delay;	// used in the tasks for delays between lower and upper address

	logic timed_out; // indicates to the testbench that we timed out waiting for b_dValid_L

	assign b_Data = (en_Data) ? DataReg : 'bz;	// since this is an inout, it needs a tri-state driver
	assign b_dValid_L = (en_dValid) ? b_dValid_L_int : 1'bz; // likewise

	// output address to bus
	always_comb begin
		if(en_AddrUp)		b_Addr <= AddrReg[15:8]; // put the upper address on the bus
		else if(en_AddrLo)	b_Addr <= AddrReg[7:0]; // put the lower address on the bus
		else			b_Addr <= 'bz;	// don't drive the bus
	end

	// take the data off the bus after a read and latch it
	always @(posedge b_Clock) begin
		if(ld_Data) begin
			DataReg <= b_Data; // takes place on a read
			$display("%d: %h read from slave address %h", $stime, DataReg, AddrReg);
		end
	end

	master_FSM master_inst(.*);

  	task writeMem
		(input	[15:0]	addr,
		 input	[7:0]	data);

		$display("%d: Prepating to write %x to %x i.e. page %b row %x column %x", $stime,data,addr,addr[15:14],addr[13:8],addr[7:0]);
		access	<= 1'b1; // tell master we want to perform a read or write
		read	<= 1'b0; // specifically a read
		loAvail <= 1'b0; // lower address isn't yet available (upper comes first)
		dataAvail <= 1'b0; // neither is data
		AddrReg	<= addr; // latch the address from the testbench
		DataReg	<= data; // and the data

		@(posedge b_Clock) access = 1'b0;
		delay = $random + 2; // we want a random amount of time between upper and lower addresses
		repeat(delay) @(posedge b_Clock); // master FSM will loop in MW1
		loAvail <= 1'b1; // causes master FSM to continue MR2
		@(posedge b_Clock); // continue to MR2
		loAvail <= 1'b0;
		delay = $random + 2;
		repeat(delay) @(posedge b_Clock); // again, random delay. not sure if this is necessary but it can't hurt
		dataAvail <= 1'b1;
		@(posedge b_Clock);
		dataAvail <= 1'b0;
		repeat(3) @(posedge b_Clock);	// loop at MA (may need to increase for worst case in slave)
	endtask

	task readMem
		(input	[15:0]	addr,
		 output	[7:0]	data);
		integer i; // used in for loop below

		$display("%d: Prepating to read from %x i.e. page %b row %x column %x", $stime,addr,addr[15:14],addr[13:8],addr[7:0]);

		timed_out <= 1'b0; // assume we don't time out
		access	<= 1'b1;
		read 	<= 1'b1;
		AddrReg	<= addr;
		loAvail <= 1'b0;

		@(posedge b_Clock) access = 1'b0; read = 1'b0;

		delay = $random + 2;
		repeat(delay) @(posedge b_Clock);
		loAvail <= 1'b1; // causes master FSM to continue to MW2
		@(posedge b_Clock);
		loAvail <= 1'b0;

		// this for loop waits for 20 clock cycles
		// if the data is ever valid, it breaks out and returns the data
		// if the counter gets up to 20, it asserts "timed_out"
		for(i=0; i<20; i=i+1) begin
			if(~b_dValid_L)
				break;
			@(posedge b_Clock);
		end
		if(i==20) begin
			timed_out = 1'b1;
			$display("Timed out waiting for response from memory");
		end

		data <= b_Data; // put the data on the bus regardless of timeout (have to put something!)
		repeat(2) @(posedge b_Clock);
	endtask

endmodule	

module master_FSM(
	// master FSM outputs
	output logic b_Start_L,
	output logic b_re_L,
	output logic en_Data,
	output logic en_dValid,
	output logic b_dValid_L_int,
	output logic ld_Data,
	output logic en_AddrUp,
	output logic en_AddrLo,
	// master FSM inputs
	input logic b_Clock,
	input logic b_Reset_L,
	input logic b_dValid_L,
	input logic access,
	input logic read,
	input logic loAvail,
	input logic dataAvail);

	// states for the interface FSM:
	// MA: wait state. Waits for 'access' signal from the tasks.
	// MR1: first read state. Waits for loAvail signal (lower address available from task). Goes to MR2.
	// MW1: first write state. Waits for loAvail as well. Goes to MW2.
	// MR2: second read state. Waits for b_dValid_L. Returns to MA.
	// MW2: second write state. Returns unconditionally to MA.
	enum {MA,MR1,MW1,MR2,MW2} currState, nextState;

	// updating state for interface FSM
	always @(posedge b_Clock, negedge b_Reset_L) begin
		if(~b_Reset_L)	currState <= MA;
		else		currState <= nextState;
	end

	always_comb begin // next state and output logic for master FSM
	
		// output defaults
		b_Start_L = 1'b1;	// by default, don't assert state to slave
		b_re_L = 1'b1;		// by default, don't assert a read
		b_dValid_L_int = 1'b1;	// by default, don't assert that data is valid
		ld_Data = 1'b0;		// by default, don't load the data from the bus
		en_Data = 1'b0;		// by default, don't drive b_Data
		en_dValid = 1'b0;	// don't driver b_dValid_L
		en_AddrUp = 1'b0;	// or b_Addr
		en_AddrLo = 1'b0;

		case(currState)
			MA: begin
				if(access) begin
					nextState = (read) ? MR1 : MW1; // determine if we're reading or writing
					b_Start_L = 1'b0; // assert start so slave FSM knows to start
					b_re_L = ~read;   // tell it if we are reading or writing
					en_AddrUp = 1'b1; // put the upper address bits on the bus
				end
				else	// loop here until we are told to initiate a read or write
					nextState = MA;
			    end
			MR1: begin // first read state. wait for the lower address
				nextState = (loAvail) ? MR2 : MR1;
				b_Start_L = (loAvail) ? 1'b1 : 1'b0;
				en_AddrLo = (loAvail) ? 1'b1 : 1'b0;
			     end
			MW1: begin // likewise, wait for lower address
				nextState = (loAvail) ? MW2 : MW1;
				b_Start_L = (loAvail) ? 1'b1 : 1'b0;
				en_AddrLo = (loAvail) ? 1'b1 : 1'b0;
				en_dValid = 1'b1;	// but also start saying the data isn't valid
				b_dValid_L_int = 1'b1; // i.e., NOT asserted
			     end
			MR2: begin // second read state
				nextState = ~b_dValid_L ? MA : MR2; // wait for data to be return from memory
				ld_Data = ~b_dValid_L ? 1'b1 : 1'b0; // then latch it from the bus
			     end
			MW2: begin // second write state
				nextState = (dataAvail) ? MA: MW2; // wait for data to be availble for the bus
				en_Data = (dataAvail) ? 1'b1 : 1'b0;	// put the data on the bus if its here
				b_dValid_L_int = (dataAvail) ? 1'b0 : 1'b1;
				en_dValid = 1'b1; // put b_dValid_L_int onto d_bValid_L asserted or not
			     end
		endcase
	end

endmodule
