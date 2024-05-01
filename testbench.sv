`timescale 1ns/1ps
module tb();
reg  clk,rst;
reg new_data,rw;
reg [7:0] data_in;
reg [6:0] addr;
  //reg dummy;
  reg [20*8:1] testname;
wire [7:0] data_out;
wire scl,ack_error,bus_busy;
wire done; 
wire sda;
 
   // instantiating the i2c_controller module
   i2c_controller dut(.clk(clk),.rst(rst),.new_data(new_data),.addr(addr),.sda_in(sda),.scl_in( scl),.rw( rw),.data_in(data_in),.data_out(data_out),.bus_busy( bus_busy),.ack_error( ack_error),.done( done));
   // instaintiating the i2c_target module
   i2c_target uut (.sda(sda),.scl(scl),.clk(clk),.rst(rst),.ack_error(ack_error),.done(done));
 
initial
begin
  clk=1'b0;
 
  forever #12.5 clk=~clk;
end
 
  initial
    begin
      if($value$plusargs("testname=%s",testname))    //taking 2 testcase- datasanity and reset bit
        begin
          $display("fetched");
        end
      else
        begin
          $display("not fetched");
        end
    end
initial 
  begin
    case(testname)
      "reset":
        begin
              rst = 1;
              #75 rst=0;
              @(posedge clk);
              new_data = 1;
              rw = 0;
              addr = 7'b1101101;
              data_in  =$urandom;
             #25000 rst=1;
        end
      "data_sanity":
        begin
        rst = 1;
              #75 rst=0;
              @(posedge clk);
              new_data = 1;
              rw = 0;
              addr = 7'b1101101;
              data_in=$urandom; ///use for write
          #400 new_data=0;
        end
            endcase
end
 
initial
  begin
    $dumpfile("dump.vcd"); 
    $dumpvars;
    #500000 $finish;
     end
endmodule