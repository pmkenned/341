/**************************\
* Paul Kennedy <pmkenned>  *
* 18-341                   *
* Project 2 memory.sv      *
* 28 February, 2011        *
\**************************/

// This module contains the memory's interface part (slave FSM) and functional part (memory FSM) 
// The interface part is responsible for reading the address of the bus into a local register
// and for controlling the enables for the tri-state buffers for b_Data and b_dValid_L.
// Also, the interface decides whether to load the row_buffer_reg with the data directly
// from the bus or whether to latch it into the DataReg register based on the signal coming 
// from the memory model FSM.
// The memory model FSM is responsible for making sure that the row buffer register is valid.
// That is, that it is ready to written to or read from (in other words, when there is a row
// change, the memory model FSM needs to grab that row from memory after writing back. I call
// this a "write-back and read cycle")
module memory
	#(parameter [1:0] baseAddr = 2'b00)
	(input logic		b_Clock, b_Reset_L, b_Start_L, b_re_L,
	 inout			b_dValid_L,
	 input logic [7:0]	b_Addr,
	 inout [7:0]		b_Data);

	logic pageMatchesBaseAddr;	// if this is false, it will prevent the memory from responding
	logic rowHasChanged;	// if this is true, then it will initiate a write-back and read cycle
				// in the memory model FSM (see more later)

	logic [2047:0] mem [64]; // the memory

	logic [5:0]	row_addr_reg;	// contains the row address
	logic [2047:0]	row_buffer_reg;	// contains the row data being read from or written to memory
	logic [15:0]	AddrReg;	// a temporary place to stash the address in case of a row change
	logic [7:0]	DataReg;	// a temporary place to stash the data in case of a row change

	// outputs of slave FSM
	logic ld_AddrUp;	// latch b_Addr into the upper bits of the address when asserted
	logic ld_AddrLo;	// likewise for lower bits
	logic ld_DataReg;	// latch the data (we do this when the memory FSM isn't read for the data yet)
	logic ld_rowBufFromBus;	// when we are ready to load the data, we either do it from the bus
	logic ld_rowBufFromReg; // or from the DataReg if it was latched (that is, we weren't ready when it was)
	logic en_Data;		// enable line to tri-state driver for b_Data
	logic en_dValid;	// enable line to tri-state driver for b_dValid_L (this one is asserted high)
	logic b_dValid_L_int;	// input to tri-state buffer for b_dValid_L
	logic compare_row_addr;	// signal to the memory model FSM to check if the row has changed

	// outputs of memory model FSM
	logic ld_mem;		// signal for writing row buffer back to memory
	logic ld_rowBufFromMem;	// signal for retrieving data from the memory (after a row change or from reset)
	logic ld_rowAddr;	// take the address from the temporary address variable where it was stashed
	logic rowBufValid;	// output back to the slave FSM indicating that the row buffer can be written to
				// or read from. This is the key to the interaction between the slave and memory model.

	assign b_Data = (en_Data) ? row_buffer_reg[AddrReg[7:0]*8 -:8] : 'bz; // tri-state driver for b_Data
	assign b_dValid_L = (en_dValid) ? b_dValid_L_int : 1'bz;	// tri-state driver for b_dValid_L


	assign pageMatchesBaseAddr = (b_Addr[7:6] === baseAddr); // if this is true, this memory module should handle the request
	assign rowHasChanged = (AddrReg[13:8] !== row_addr_reg); // row has changed so we initiate a write-back and read cycle

	// always ff block for slave and memory model outputs
	always_ff @(posedge b_Clock) begin
		if(ld_AddrUp)		AddrReg[15:8] <= b_Addr;
		else if(ld_AddrLo)	AddrReg[7:0] <= b_Addr;

		if(ld_DataReg)	DataReg <= b_Data; // latch data from bus (done whenever the memory is busy doing a write-back and read)
		if(ld_mem)	mem[row_addr_reg] <= row_buffer_reg; // store row buffer to memory (done only on a write-back)
		if(ld_rowAddr) 	row_addr_reg <= AddrReg[13:8]; // load row address register (done after the write-back is complete)

		if(ld_rowBufFromMem)		row_buffer_reg <= mem[row_addr_reg]; // read from mem. done after a write-back
		else if(ld_rowBufFromBus)	row_buffer_reg[AddrReg[7:0]*8 -:8] <= b_Data; // take directly from bus
		else if(ld_rowBufFromReg)	row_buffer_reg[AddrReg[7:0]*8 -:8] <= DataReg; // take from latched data
	end

	slave_FSM slave_inst(.*);
	memory_FSM memory_inst(.*);

endmodule

module slave_FSM(
	// outputs of slave FSM (see above for explanations)
	output logic ld_AddrUp,
	output logic ld_AddrLo,
	output logic ld_DataReg,
	output logic ld_rowBufFromBus,
	output logic ld_rowBufFromReg,
	output logic en_Data,
	output logic en_dValid,
	output logic b_dValid_L_int,
	output logic compare_row_addr,	// output to memory FSM
	// inputs of slave FSM (see above for explanations)
	input logic b_Clock,
	input logic b_Reset_L,
	input logic b_Start_L,
	input logic b_dValid_L,
	input logic b_re_L,
	input logic pageMatchesBaseAddr,
	input logic rowBufValid);	// input from memory FSM

	// states for the slave FSM, i.e., the interface part
	// SA: the slave's wait state. we go to either SR1 (on read) or SW1 (on write) when b_Start_L is asserted
	// SR1: first read state. we wait for b_Start_L to go low again then go to SR2
	// SW1: likewise except first write state
	// SR2: second read state. Wait for memory FSM to say that the row buffer is valid so we can read a byte and put it on the bus
	// SW2: second write state. loop here until the data comes across the bus (go to either SA or SW3 depending on rowBufValid)
	// SW3: we go here if the data came before the row buffer was ready for it (the data is latched so we write it in and go to SA)
	enum {SA, SR1, SW1, SR2, SW2, SW3} slaveCurrState, slaveNextState;

	// always ff block for updating slave FSM state
	always_ff @(posedge b_Clock, negedge b_Reset_L) begin
		if(~b_Reset_L)	slaveCurrState <= SA;
		else		slaveCurrState <= slaveNextState;
	end


	always_comb begin // next state and output logic for slave

		// default outputs
		ld_AddrUp = 1'b0;	// don't load the address register...
		ld_AddrLo = 1'b0;
		ld_DataReg = 1'b0;	// data register...
		ld_rowBufFromBus = 1'b0; // or row buffer register by default
		ld_rowBufFromReg = 1'b0;

		en_Data = 1'b0;		// by default, don't try to drive data line on bus
		en_dValid = 1'b0;	// 	or the data valid signal
		b_dValid_L_int = 1'b1;	// not asserted by default

		compare_row_addr = 1'b0; // don't tell the memory FSM to compare row address by default

		case(slaveCurrState)
			SA: begin
				if(~b_Start_L && pageMatchesBaseAddr) begin // wait for start (and make sure we're the right memory)
					slaveNextState = ~b_re_L ? SR1 : SW1; // determine if we're doing a read or write
					ld_AddrUp = 1'b1; // latch the upper address (should be on the bus)
				end
				else begin // otherwise, loop...
					slaveNextState = SA;
				end
			    end
			SR1: begin // wait for start to go low again, indicating lower address is on bus
				slaveNextState = b_Start_L ? SR2 : SR1;
				ld_AddrLo = b_Start_L ? 1'b1 : 1'b0;
				compare_row_addr = 1'b1; // now that upper address is latched, we can tell the memory FSM to start comparing
				en_dValid = 1'b1;	// drive b_dValid_L as unasserted
				b_dValid_L_int = 1'b1;
			     end
			SW1: begin // likewise
				slaveNextState = b_Start_L ? SW2 : SW1;
				ld_AddrLo = b_Start_L ? 1'b1 : 1'b0; // low address is here when start goes low
				compare_row_addr = 1'b1; // see comment in SR1
			     end
			SR2: begin // wait for the memory FSM to tell us that the row buffer contains the right data
				slaveNextState = rowBufValid ? SA : SR2;
				en_Data = rowBufValid ? 1'b1 : 1'b0;	// drive the data line on the bus
				en_dValid = 1'b1;	// drive b_dValid_L
				b_dValid_L_int = rowBufValid ? 1'b0 : 1'b1; // at this point, the data is valid if rowBuf is
			     end
			SW2: begin
				// data is on the bus and we're ready to write to the row buffer
				if(~b_dValid_L && rowBufValid) begin
					slaveNextState = SA;	// head back to start
					ld_rowBufFromBus = 1'b1;// write data directly from bus
				end
				// data is on the bus, but we're no ready to write to the row buffer
				else if(~b_dValid_L && ~rowBufValid) begin
					slaveNextState = SW3;
					ld_DataReg = 1'b1;	// latch the data so we have it when we are ready
				end
				// data isn't on the bus yet; wait for it here
				else
					slaveNextState = SW2;
			     end
			SW3: begin // data arrived when the row buffer wasn't ready! D: OH NOES! but don't worry!! we LATCHED it! :D
				slaveNextState = (rowBufValid) ? SA : SW3;
				ld_rowBufFromReg = (rowBufValid) ? 1'b1 : 1'b0; // take the stashed data value
			     end
		endcase
	end // end of next state and output logic for slave FSM

endmodule // end of slave_FSM module

module memory_FSM(
	// outputs of memory model FSM (see above for explanations)
	output logic ld_mem,
	output logic ld_rowBufFromMem,
	output logic ld_rowAddr,
	output logic rowBufValid,	// output to slave FSM
	// inputs of memory model FSM (see above for explanations)
	input logic b_Clock,
	input logic b_Reset_L,
	input logic compare_row_addr,	// coming from slave FSM
	input logic rowHasChanged);

	// states for the memory model FSM i.e., the functional part
	// memA: wait state for memory. initiate write-back and read cycle when the incoming row address doesn't match the current one
	// memB: we're beginning a write-back and read cycle. here we write back.
	// memRst: we go here upon reset and wait for the compare_row_addr from the slave (which it sends when it receives the upAddr)
	// memC: here we update the row_addr_reg
	// memD: and here we load the row_buffer with the memory data
	enum {memA,  memB, memRst, memC, memD} memCurrState, memNextState ; // current state and next state for memory FSM

	// always ff block for updating memory model FSM state
	always_ff @(posedge b_Clock, negedge b_Reset_L) begin
		if(~b_Reset_L)	memCurrState <= memRst;
		else		memCurrState <= memNextState;
	end

	always_comb begin // next state and output logic for memory FSM

		// default outputs
		ld_mem = 1'b0;			// don't write back to memory (this is only done when the row changes)
		ld_rowAddr = 1'b0;		// don't load the row address by default
		ld_rowBufFromMem = 1'b0;	// don't take data from memory by default (only happens after a row change)
		rowBufValid = 1'b0;		// definitely don't signal to the slave FSM that the row buffer is ready

		case(memCurrState)
			memA: begin
				// if the slave is telling us to compare the row address register
				// with the new row address on the bus, and it has changed,
				// then initiate a write-back and read cycle
				if(compare_row_addr && rowHasChanged) begin
					memNextState = memB;
					rowBufValid = 1'b0;	// let the slave know the row buffer reg isn't ready
								// to read from or written to
				end else begin	// if the row hasn't changed (or we haven't been told to check)
						// then simply loop here
					memNextState = memA;
					rowBufValid = 1'b1;
				end
			      end
			memB: begin
				memNextState = memC;
				ld_mem = 1'b1;	// we don't write back until this transition because it takes
						// two cycles to write to memory
			      end
			memRst: begin // start midstream upon reset; we need to read out, but not write back
				memNextState = (compare_row_addr) ? memC : memRst;
			        end
			memC: begin
				memNextState = memD;
				ld_rowAddr = 1'b1; // load the new row address from the upper bits of AddrReg
			      end
			memD: begin
				memNextState = memA;
				ld_rowBufFromMem = 1'b1; // this happens two clock cycles after the upper address is taken off the bus
							 // (because before being loaded into row_addr_reg its loaded into AddrReg)
			      end
		endcase
	end // end of next state and output logic for memory model FSM

endmodule // end of memory_FSM module
