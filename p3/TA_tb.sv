module test
  (output logic clk, rst_L);
  
  logic [63:0]  message;
  logic [63:0]  receivedMsg;
  logic [6:0]   addr;
  logic         timeout;
  
  initial 
  begin
    rst_L = 1'b1;
    clk = 1'b1;
    addr = 7'h0;
    @(posedge clk) rst_L = 1'b0;
    @(posedge clk) rst_L = 1'b1;
  
    
		$display("\n");
    $display("********************************************************************************");
    $display("*****************************SEND AND RECEIVE TEST******************************");
    $display("********************************************************************************");
    
///////////////////////////////////////////////////////////////////////////////
// Host sends data to the device to be printed
///////////////////////////////////////////////////////////////////////////////
    
    message = 64'hcafefadedeadbeef;
     
    @(posedge clk);
    $display("");
    $display($time,, "TestBench:\tSending 0x%x to Device", message);
    host.sendData(addr, message, timeout);
    if(timeout)
      $display($time,, "TestBench:\tSending 0x%x to Device: timed out", message);
    
    @(posedge clk);
    dev.print(receivedMsg);
    if(receivedMsg !== message)
      $display($time,, "TestBench:\tSent 0x%x but received 0x%x", message, receivedMsg);
    else
      $display($time,, "TestBench:\tDevice printed correctly!");
    $display("");
    
///////////////////////////////////////////////////////////////////////////////
// Host sends different data to the device to be printed
///////////////////////////////////////////////////////////////////////////////
    
    message = 64'hffffabcd1337c0de;
    
    @(posedge clk);
    $display("");
    $display($time,, "TestBench:\tSending 0x%x to Device", message);
    host.sendData(addr, message, timeout);
    if(timeout)
      $display($time,, "TestBench:\tSending 0x%x to Device: timed out", message);
    
    @(posedge clk);
    dev.print(receivedMsg);
    if(receivedMsg !== message)
      $display($time,, "TestBench:\tSent 0x%x but received 0x%x", message, receivedMsg);
    else
      $display($time,, "TestBench:\tDevice printed correctly!");
    $display("");
    
///////////////////////////////////////////////////////////////////////////////
// Device scans in data, host requests it
///////////////////////////////////////////////////////////////////////////////

    message = 64'h1234abcd5678efff;
    dev.scan(message);
    
    @(posedge clk);
    $display("");
    $display($time,, "TestBench:\tRequest data from Device");
    host.receiveData(7'd0, receivedMsg, timeout);
    if(timeout)
      $display($time,, "TestBench:\tReceiving data from Device: timed out");
    else if(receivedMsg !== message)
      $display($time,, "TestBench:\tReceived 0x%x instead of 0x%x", receivedMsg, message);
    else
      $display($time,, "TestBench:\tHost received correct data!");
    
		$display("\n");
    $display("********************************************************************************");
    $display("*****************************END TEST*******************************************");
    $display("********************************************************************************");
    
    $finish; 
  end

  always #1 clk = ~clk;

endmodule
