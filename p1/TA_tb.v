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

module tb
(
  output bit         ck, rst_l,
  output bit  [19:0] data,
  input bit [15:0] result,
  input bit        stackOverflow, unexpectedDone, dataOverflow, 
                    protocolError, correct, finished
);

  integer i;

  initial
  begin
		$display("\n");
		$display("********************************************************************************");
		$display("********************************TESTS  PERFORMED********************************");
		$display("********************************************************************************");
  
 	  $display("-INFO-: 1. Basic insertion and removal from stack");
 	  $display("\t-INFO-: 1.1 Push Value 1 with Start");
 	  $display("\t-INFO-: 1.2 Push Value 2 with Enter");
 	  $display("\t-INFO-: 1.2 Push Value 3 with Enter");
 	  $display("\t-INFO-: 1.3 Pop Value 3 with ArithOp POP");
		$display("-INFO-: 2. ArithOp ADD");
		$display("-INFO-: 3. Finish");
  
		$display("\n");
		$display("********************************************************************************");
		$display("*************************************RESULTS************************************");
		$display("********************************************************************************");
  
    ck = 0;
    rst_l <= 1;
    #1  rst_l <= 0;
    #1  rst_l <= 1;
       data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_enter, 16'h3};
    #4 data <= {`com_arithOp, `op_pop};

    #4 data <= {`com_arithOp, `op_add};
		
    #4 data <= {`com_done, 16'hx};
    #4 data <= {20'hx};
    #4 $finish; 

  end

  always #2 ck = ~ck;
endmodule


module top();

bit         ck, rst_l;
bit  [19:0] data;
bit [15:0] result;
bit        stackOverflow, unexpectedDone, dataOverflow, 
                    protocolError, correct, finished;

//initial
//    $monitor($time,, "Data: %h, result: %h, stackOverflow: %d, !Done: %d, dataOverflow: %d, Protocol: %d, Correct: %d, finished: %d\n", data, result, stackOverflow, unexpectedDone, dataOverflow, protocolError, correct, finished);

//tb tb_inst(clock, rst_l, data, result, stackOverflow, unexpectedDone, dataOverflow, protocolError, correct, finished);
tb tb_inst(.ck(ck), .rst_l(rst_l), .data(data), .result(result), .stackOverflow(stackOverflow), 
	.unexpectedDone(unexpectedDone), .dataOverflow(dataOverflow), .protocolError(protocolError), 
		.correct(correct), .finished(finished));


//calculator calc(clock, rst_l, data, result, stackOverflow, unexpectedDone, dataOverflow, protocolError, correct, finished);
calculator calc_inst(.ck(ck), .rst_l(rst_l), .data(data), .result(result), .stackOverflow(stackOverflow), 
	.unexpectedDone(unexpectedDone), .dataOverflow(dataOverflow), .protocolError(protocolError), 
		.correct(correct), .finished(finished));

property pushStart;
	logic [15:0] value;
	@(posedge ck) disable iff (~rst_l)
		(data[19:16]==`com_start, value = data[15:0]) |=> (value==result);
endproperty

TestPushStart: assert property(pushStart)
	$display("\t-INFO-: 1.1 Top of stack value equals value pushed using START\n");
	else $error("\t-ERROR-: 1.1 Start value was not pushed onto the stack\n");

property pushEnter;
	logic [15:0] value;
	@(posedge ck) disable iff (~rst_l)
		(data[19:16]==`com_enter, value = data[15:0]) |=> (value==result);
endproperty

TestPushEnter: assert property(pushEnter)
	$display("\t-INFO-: 1.2 Top of stack value equals value pushed using ENTER\n");
	else $error("\t-ERROR-: 1.2 Enter value was not pushed onto the stack\n");

property arithOpPOP;
	@(posedge ck) disable iff (~rst_l)
		(data[19:16]==`com_arithOp)&&(data[15:0]==`op_pop) |=> (result==16'h2);
endproperty

TestArithOpPOP: assert property(arithOpPOP)
	$display("\t-INFO-: 1.3 Top of stack value matches expected value after POP\n");
	else $error("\t-ERROR-: 1.3 Top of stack value does NOT match expected value after POP\n");

property arithOpADD;
	@(posedge ck) disable iff (~rst_l)
		(data[19:16]==`com_arithOp)&&(data[15:0]==`op_add) |=> (result==16'h3);
endproperty

TestArithOpADD: assert property(arithOpADD)
	$display("\t-INFO-: 2. Top of stack value matches expected value after ADD\n");
	else $error("\t-ERROR-: 2. Top of stack value does NOT match expected value after ADD\n");

property finish;
	@(posedge ck) disable iff (~rst_l)
		(data[19:16]==`com_done) |-> (result==16'h3);
endproperty

TestFinish: assert property(finish)
	$display("\t-INFO-: 3. Top of stack value matches expected value for DONE\n");
	else $error("\t-ERROR-: 3. Top of stack value does NOT match expected value for DONE\n");

endmodule
