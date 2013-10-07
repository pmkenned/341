/* Paul Kennedy <pmkenned>
 * 25 January, 2011
 * 18-341 Project 0 */

`default_nettype none

`define com_start   4'h1
`define com_enter   4'h2
`define com_arithOp 4'h4
`define com_done    4'h8

`define op_add    16'h1
`define op_sub    16'h2
`define op_and    16'h4
`define op_swap   16'h8
`define op_neg    16'h10
`define op_pop    16'h20

`define er_protocolError	4'd1
`define er_stackOverflow	4'd2
`define er_dataOverflow		4'd4
`define er_unexpectedDone	4'd8

// inputs to the mux which controls to the input to stack register 0
`define from_ALU  2'b00
`define from_data 2'b01
`define from_reg1 2'b10

// inputs to the muxes over the rest of the stack registers
`define push 1'b0
`define pop  1'b1

module calculator
(input bit          ck, rst_l,	// posedge ck
 input bit   [19:0] data,
 output bit  [15:0] result,
 output bit         stackOverflow, unexpectedDone,
 dataOverflow, protocolError, correct, finished);

logic reg0_en, reg1_en, reg2to7_en;	// the enable lines for the 0, 1, and 2 through 7 stack registers
logic [1:0] reg0_mux_sel;		// reg0 can take input from three places: the ALU, the incoming data line, and reg1 (in case of a swap or pop)
logic reg1_mux_sel, reg2to6_mux_sel;	// the rest of the registers can take data from either the next register (in a pop) or the previous register (in a push)
logic stackCounter_inc, stackCounter_dec, stackCounter_init; // control lines for the stackCounter
logic firstStart; // an output from the FSM to the combinational-logic error-detector (letting it know that start has already been seen)

logic error; // input bit to the FSM; if there is an error, output and nextState logic will be different

logic [3:0] stackCounter_out; // the actual value stored in the stack counter register ; feeds into the error detector (most errors require knowing the stack counter value)

logic [15:0] r0_in, r1_in, r2_in, r3_in, r4_in, r5_in, r6_in; // input lines to each stack register; each of these are ouputs from muxes which select the input
// (notice there is no r7_in. That's because r6_out flows directly to the input of r7)
logic [15:0] r0_out, r1_out, r2_out, r3_out, r4_out, r5_out, r6_out, r7_out; // the outputs of the stack registers

logic [15:0] ALU_out; // output of the ALU; goes into the reg0 mux; it goes into reg0 if reg0_mux = from_ALU
logic ALU_dataOverflow; // the overflow bit running out of the ALU into the error detection module

logic [3:0] errorDetector_out; // 1-hot encoded output of the combinational-logic error detector
logic [3:0] errReg_out; // register which stores the errors (they need to be held until posedge clock where 'done' is asserted)

// the glorious stack registers
register16 r0(.clk(ck), .rst_l(rst_l), .en(reg0_en), .in(r0_in), .out(r0_out) );
register16 r1(.clk(ck), .rst_l(rst_l), .en(reg1_en), .in(r1_in), .out(r1_out) );
register16 r2(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r2_in), .out(r2_out) );
register16 r3(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r3_in), .out(r3_out) );
register16 r4(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r4_in), .out(r4_out) );
register16 r5(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r5_in), .out(r5_out) );
register16 r6(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r6_in), .out(r6_out) );
register16 r7(.clk(ck), .rst_l(rst_l), .en(reg2to7_en), .in(r6_out), .out(r7_out) ); // again, notice r6_out goes directly to the input of r7

// the muxes above the stack registers. they select whether input comes from the next or prior register
mux4to1_16 r0_mux(.select(reg0_mux_sel), .a(ALU_out), .b(data[15:0]), .c(r1_out), .d(16'b0), .e(r0_in) ); // special case for r0: can come from ALU, incoming data, or r1
mux2to1_16 r1_mux(.select(reg1_mux_sel), .a(r0_out), .b(r2_out), .c(r1_in) );
mux2to1_16 r2_mux(.select(reg2to6_mux_sel), .a(r1_out), .b(r3_out), .c(r2_in) );
mux2to1_16 r3_mux(.select(reg2to6_mux_sel), .a(r2_out), .b(r4_out), .c(r3_in) );
mux2to1_16 r4_mux(.select(reg2to6_mux_sel), .a(r3_out), .b(r5_out), .c(r4_in) );
mux2to1_16 r5_mux(.select(reg2to6_mux_sel), .a(r4_out), .b(r6_out), .c(r5_in) );
mux2to1_16 r6_mux(.select(reg2to6_mux_sel), .a(r5_out), .b(r7_out), .c(r6_in) );

FSM myFSM(.clk(ck), .rst_l(rst_l), .command(data[19:16]), .opCode(data[15:0]), .*);

assign finished = data[19];	// finished is asserted if an only if done is asserted (done is data[19])
assign result = r0_out;		// r0 always will be the result if correct (and if not correct, then result is irrelevant)
assign correct = (errorDetector_out == 0);	// if no errors were detected, then the result is correct
assign error = ~correct; // error is the bit flowing into the FSM to let it know if there were any errors (so it can decide what to do)

assign protocolError = errorDetector_out[0];
assign stackOverflow = errorDetector_out[1];
assign dataOverflow = errorDetector_out[2];
assign unexpectedDone = errorDetector_out[3];

// r0 and r1 are hardwired into the ALU; the overflow bit runs into the combinational-logic error detector
// the ALU takes the arithOp bit as an input so that is can make sure to not assert overflow when we're not doing arithmetic operations
// otherwise, since the ALU is combinational, it might assert dataOverflow is r0 and r1 had large values left over and the data happened to encode an add instruction
ALU myALU(.in1(r0_out), .in2(r1_out), .opCode(data[15:0]), .arithOp(data[18]), .out(ALU_out), .overflow(ALU_dataOverflow));

// counter which keeps track of how many items are on the stack.
// when init is asserted, the counter is initialized to 1.
counter stackCounter( .clk(ck), .rst_l(rst_l), .inc(stackCounter_inc), .dec(stackCounter_dec), .init(stackCounter_init), .in(4'b0001), .out(stackCounter_out) );

// combinational logic error detector. takes as input the error register output, the stack counter value, the ALU overflow bit, the opcode, and the command
// it outputs a 4-bit, 1-hot encoded data line which is split up into the 4 error lines which the calculator module outputs
// remember: this is combinational so the errors show up instantly. the register instantiated below is what is responsible for holding the errors until they should be cleared
errorDetector myErrorDetector(.firstStart(firstStart), .errorReg(errReg_out), .stackCounter_out(stackCounter_out), .dataOverflow(ALU_dataOverflow), .opCode(data[15:0]), .command(data[19:16]), .errors(errorDetector_out) );

// this is the register for holding the errors until they are cleared (data[19] aka 'done'. when the first posedge clk happens with done asserted, the errors go away)
// the output of this register flows into the combinational logic module so that it can continue to assert errors even after its own logic doesn't see any
register4 errorRegister(.clk(ck), .rst(data[19]), .en(1'b1), .in(errorDetector_out), .out(errReg_out) ); // always enabled?

endmodule: calculator

// beginning of FSM
module FSM
(input clk, rst_l,
 input [3:0] command,
 input [15:0] opCode,
 input error,
 output bit [1:0] reg0_mux_sel, 
 output bit reg1_mux_sel, reg2to6_mux_sel,
 output bit reg0_en, reg1_en, reg2to7_en,
 output bit stackCounter_inc, stackCounter_dec, stackCounter_init,
 output bit firstStart);
 

enum logic [1:0] {waitingForStart = 1'd0, waitingForDone = 1'd1} currState, nextState;

// output logic
always_comb begin

	// default outputs (to guarantee combinational and so that I don't have to specify them all in every case)
	reg0_mux_sel = `from_data;
	reg1_mux_sel = `push;
	reg2to6_mux_sel = `push;
	reg0_en = 0;
	reg1_en = 0;
	reg2to7_en = 0;
	stackCounter_inc = 0;
	stackCounter_dec = 0;
	stackCounter_init = 0;
	firstStart = 0;

	case(currState)

		waitingForStart: begin // we want to loop in this state until we see start
			if(command == `com_start) begin
				stackCounter_init = 1; // initialize stack counter 
				firstStart = 0; // lets the errorDetector know that the first start has come
				reg0_en = 1; // register 0 will be written to
				reg0_mux_sel = `from_data; // it will be filled with the incoming data
			end
		end

		waitingForDone: begin // we want to loop in this state until we see done
			firstStart = 1; // we can only be here if there was a start
			if(~error) begin // if there are no errors, then we can do our normal routine
				case(command)
					`com_start: begin end // the errorDetector will detect this as an error

					`com_enter: begin
						reg0_en = 1; // value is written into reg0 from incoming data
						reg1_en = 1; // reg1 receives value held in reg0
						reg2to7_en = 1; // likewise for the rest of the regs
						reg0_mux_sel = `from_data; // reg0 receives from incoming data
						reg1_mux_sel = `push; // reg1 receives data from reg0
						reg2to6_mux_sel = `push; // likewise for the rest of the regs
						stackCounter_inc = 1; // increment stack counter
					end

					`com_arithOp: begin
						case(opCode)
							`op_add, `op_sub, `op_and: begin // each of these has certain things in common
								reg0_en = 1; // receives data from ALU
								reg1_en = 1; // popped from reg2
								reg2to7_en = 1; // popped from next reg
								reg0_mux_sel = `from_ALU;
								reg1_mux_sel = `pop;
								reg2to6_mux_sel = `pop;
								stackCounter_dec = 1; // one fewer value on stack now
							end
							`op_swap: begin
								reg0_en = 1; // will be written to
								reg1_en = 1; // will be written to
								reg2to7_en = 0; // the rest of the regs don't change
								reg0_mux_sel = `from_reg1;
								reg1_mux_sel = `push; // value from reg0 is pushed into reg1
							end
							`op_neg: begin
								reg0_en = 1; // only this register is being altered
								reg1_en = 0;
								reg2to7_en = 0;
								reg0_mux_sel = `from_ALU; // ALU outputs -reg0
							end
							`op_pop: begin 
								reg0_en = 1; // all regs are written to in a pop
								reg1_en = 1;
								reg2to7_en = 1;
								reg0_mux_sel = `from_reg1;
								reg1_mux_sel = `pop;
								reg2to6_mux_sel = `pop;
								stackCounter_dec = 1; // one fewer item on stack
							end
						endcase

					end

					`com_done:
						firstStart = 0; // seeing a start should no longer cause an error
				endcase
			end
			else begin // there was an error
				reg0_en = 0; // we don't want to write to any of the regs
				reg1_en = 0;
				reg2to7_en = 0;
			end
		end
	endcase
end

// next state logic
always_comb begin
	case(currState) // fortunately this is really simple for a two state FSM
		waitingForStart: nextState = (command == `com_start) ? waitingForDone : waitingForStart;
		waitingForDone: nextState = (command == `com_done) ? waitingForStart : waitingForDone;
	endcase
end

always_ff @(posedge clk) begin
 	if(~rst_l)	currState <= waitingForStart;	// upon reset, go to 'waitingForStart'
 	else		currState <= nextState;	// otherwise, proceed to nextState
end

endmodule: FSM
// end of FSM

module ALU(input bit [15:0] in1, in2,
           input bit [15:0] opCode,
           input bit arithOp, // 1 if the command is arithOp (this is data[18])
           output bit [15:0] out,
           output bit overflow);

always_comb begin
	case(opCode)
		`op_add: begin
			out = in1 + in2;
                        overflow = ((in1[15] && in2[15] && ~out[15]) || (~in1[15] && ~in2[15] && out[15])) && arithOp ? 1 : 0;
		end
		`op_sub: begin
			out = in2 - in1;
			overflow = ((~in2[15] && in1[15] && out[15]) || (in2[15] && ~in1[15] && ~out[15])) && arithOp ? 1 : 0;
		end
		`op_and: begin
			out = in1 & in2;
			overflow = 0;
		end
		`op_swap: begin
			out = 0; // don't need ALU to perform swap (achieved by muxes)
			overflow = 0;
		end
		`op_neg: begin
			out = -in1;
			overflow = 0;
		end
		`op_pop: begin
			out = 0; // this doesn't matter
			overflow = 0;
		end
	endcase
end

endmodule: ALU

module register16(input bit clk, rst_l, en,
                  input bit [15:0] in,
                  output bit [15:0] out);

	  always_ff @(posedge clk) begin
	  	  if(~rst_l) // all regs are initialized to 0, though this isn't critical
	  	  	  out <= 0;
	  	  else if(en)
	  	  	  out <= in;
	  	  else
	  	  	  out <= out;
	  end

endmodule: register16

// this module is only used for storing the errors
module register4(input bit clk, rst, en,
                 input bit [3:0] in,
                 output bit [3:0] out);

	 always_ff @(posedge clk) begin
	 	 if(rst) // reset isn't asserted low because it will be the 'done' signal
	 	 	 out <= 0;
	 	 else if(en)
	 	 	 out <= in;
	 	 else
	 	 	 out <= out;
	 end

endmodule: register4

// this module is used for input selection for reg 1 through 7
module mux2to1_16(input bit select,
                  input bit [15:0] a, b,
                  output bit [15:0] c);

          always_comb
	          c = (select) ? b : a;

endmodule: mux2to1_16

// this is used only for reg0 input selection (from ALU, incoming data, or reg1)
module mux4to1_16(input bit [1:0] select,
                  input bit [15:0] a, b, c, d,
                  output bit [15:0] e);

          always_comb begin
		  case(select)
			2'b00: e = a;
			2'b01: e = b;
			2'b10: e = c;
			2'b11: e = d;
		  endcase
	  end

endmodule: mux4to1_16

// this is used for the stack counter. it can increment, decrement, and intiailize to a specified value
module counter(input bit clk, rst_l,
	       input bit inc, dec, init,
               input bit [3:0] in,
               output bit [3:0] out);

	always_ff @(posedge clk) begin
		if(~rst_l || init)
			out <= in;
		else if(inc)
			out <= out + 1;
		else if(dec)
			out <= out - 1;
		else
			out <= out;
	end

endmodule: counter

// combinational logic! the output of this module flows directly to the output of the calculator module
// the output ALSO goes into an error register which feeds its output into this module
// thus, there is a loop between this module and the error register
// that way, this module can be aware of errors that were asserted earlier even though the comb. logic might not be asserting them now
// we need this because the errors need to be asserted until 'done' (after much discussion with TAs, we decided that errors should be
// deasserted NOT on the falling edge of done, but upon the first posedge clk where done is asserted)
module errorDetector(input bit firstStart,
                     input bit [3:0] errorReg,
                     input bit [3:0] stackCounter_out,
                     input bit dataOverflow,
                     input bit [15:0] opCode,
                     input bit [3:0] command,
                     output bit [3:0] errors);

	always_comb begin
		if(errorReg != 4'b0) // if the error register has recorded any errors, just echo those
        		errors = errors;
		else if(firstStart && command == `com_start) // saw second start before done
			errors = `er_protocolError;
		else if(command == `com_arithOp && (opCode == `op_add || opCode == `op_sub || opCode == `op_and || opCode == `op_swap || opCode == `op_pop) && stackCounter_out == 1)
			errors = `er_protocolError;
		else if(command != `com_arithOp && command != `com_done && command != `com_start && command != `com_enter) // garbage input
			errors = `er_protocolError;
		else if(command == `com_done && stackCounter_out != 1) // unexpected done
			errors = `er_unexpectedDone;
		else if(dataOverflow) // overflow from addition or subtraction
			errors = `er_dataOverflow;
		else if(stackCounter_out > 8) // stack overflow
			errors = `er_stackOverflow;
		else // didn't see any errors
			errors = 0;
	end

endmodule: errorDetector
