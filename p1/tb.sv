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
  
    ck = 0;
    rst_l <= 1;
    #1  rst_l <= 0;
    #1  rst_l <= 1;

    // test addition
    #4 data <= {`com_start, 16'h5};
    #4 data <= {`com_enter, 16'h6};
    #4 data <= {`com_arithOp, `op_add};
    #4 data <= {`com_done, 16'hx};

    // test subtraction
    #4 data <= {`com_start, 16'h8};
    #4 data <= {`com_enter, 16'h6};
    #4 data <= {`com_arithOp, `op_sub};
    #4 data <= {`com_done, 16'hx};

    // test op_and
    #4 data <= {`com_start, 16'h5};
    #4 data <= {`com_enter, 16'hf};
    #4 data <= {`com_arithOp, `op_and};
    #4 data <= {`com_done, 16'hx};

    // test swapping
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_arithOp, `op_swap};
    #4 data <= {`com_arithOp, `op_pop};
    #4 data <= {`com_done, 16'hx};

    // test negation
    #4 data <= {`com_start, 16'h5};
    #4 data <= {`com_arithOp, `op_neg};
    #4 data <= {`com_done, 16'hx};

    // test popping
    #4 data <= {`com_start, 16'h5};
    #4 data <= {`com_enter, 16'h4};
    #4 data <= {`com_arithOp, `op_pop};
    #4 data <= {`com_done, 16'hx};

    // test a combination of things
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_enter, 16'h3};
    #4 data <= {`com_arithOp, `op_pop};
    #4 data <= {`com_arithOp, `op_add};
    #4 data <= {`com_done, 16'hx};

    // protocolError from double start
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_start, 16'h3}; // should cause a protocolError
    #4 data <= {`com_done, 16'hx}; // should send us back to waitingForStart

    // protocolError from too few stack items for operand
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_arithOp, `op_add}; // should cause protocolError
    #4 data <= {`com_enter, 16'h2}; // this shouldn't be processed
    #4 data <= {`com_done, 16'hx};

    // unexpectedDone
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_done, 16'hx}; // should return to waitingForStart

     // dataOverflow (add two large negatives)
    #4 data <= {`com_start, 16'h8000};
    #4 data <= {`com_enter, 16'h8000};
    #4 data <= {`com_arithOp, `op_add};
    #4 data <= {`com_done, 16'hx};

     // dataOverflow (add two large positives)
    #4 data <= {`com_start, 16'h7fff};
    #4 data <= {`com_enter, 16'h7fff};
    #4 data <= {`com_arithOp, `op_add};
    #4 data <= {`com_done, 16'hx};

    // dataOverflow (large negative subtract large positive)
    #4 data <= {`com_start, 16'h8000};
    #4 data <= {`com_enter, 16'h7fff};
    #4 data <= {`com_arithOp, `op_sub};
    #4 data <= {`com_done, 16'hx};

    // dataOverflow (large positive subtract large negative)
    #4 data <= {`com_start, 16'h7fff};
    #4 data <= {`com_enter, 16'h8000};
    #4 data <= {`com_arithOp, `op_sub};
    #4 data <= {`com_done, 16'hx};

    // stackOverflow error
    #4 data <= {`com_start, 16'h1};
    #4 data <= {`com_enter, 16'h2};
    #4 data <= {`com_enter, 16'h3};
    #4 data <= {`com_enter, 16'h4};
    #4 data <= {`com_enter, 16'h5};
    #4 data <= {`com_enter, 16'h6};
    #4 data <= {`com_enter, 16'h7};
    #4 data <= {`com_enter, 16'h8};
    #4 data <= {`com_enter, 16'h9}; // should cause overflow
    #4 data <= {`com_enter, 16'ha};
    #4 data <= {`com_done, 16'hx}; // should send us back to waitingForStart

    // testing what happens with garbage value
    #4 data <= {`com_start, 16'h1};
    #4 data <= {4'b0, 16'h0}; // should assert protocolError

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

initial
    $monitor($time,, "Data: %h, result: %h, stackOverflow: %d, !Done: %d, dataOverflow: %d, Protocol: %d, Correct: %d, finished: %d\n", data, result, stackOverflow, unexpectedDone, dataOverflow, protocolError, correct, finished);

tb tb_inst(.ck(ck), .rst_l(rst_l), .data(data), .result(result), .stackOverflow(stackOverflow), 
	.unexpectedDone(unexpectedDone), .dataOverflow(dataOverflow), .protocolError(protocolError), 
		.correct(correct), .finished(finished));

calculator calc_inst(.ck(ck), .rst_l(rst_l), .data(data), .result(result), .stackOverflow(stackOverflow), 
	.unexpectedDone(unexpectedDone), .dataOverflow(dataOverflow), .protocolError(protocolError), 
		.correct(correct), .finished(finished));
endmodule
