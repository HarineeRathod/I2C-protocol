module i2c_controller(clk,rst,new_data,addr,sda_in,scl_in,rw,data_in,data_out, bus_busy, ack_error,done);
input clk, rst;
input new_data; //flag for new data
input [6:0] addr; //7 bit address
input rw; //operation read & write
input [7:0] data_in; //8 bit data in
 
inout sda_in; //serial data bidirectional port
inout scl_in; // searial clock line
 
output [7:0] data_out;
output reg bus_busy,ack_error,done; //flags for operations indication
 
//temporary value storage
reg scl_temp=0; 
reg sda_temp=0; 
reg [7:0] rx_data=0;
reg [7:0] tx_data=0;
//timing parameters
parameter system_freq=40000000;//40 MHz
parameter i2c_freq=100000;//standard mode frequency = 100 KHz
parameter clk_count_4bit=(system_freq/i2c_freq); //clock count 400 cycle
parameter clk_count_1bit=(clk_count_4bit/4);//clk count 100 cycles
 
 
// parameters to represent the states
localparam Idle=0;
localparam Start=1;
localparam Write_addr=2;//write address
localparam Ack_1=3;//from target for address
localparam Write_data=4;
localparam Read_data=5;
localparam Stop=6;
localparam Ack_2=7;//from target for data write
localparam Controller_ack=8;//from controller for data read
 
 
reg [3:0] state=Idle;
 
 
//reg i2c_clk=0;
 
//////pulse counting//////
 
reg [1:0]pulse;
integer counter=0;
 
always@(posedge clk) begin
	if(rst)                         //reset condition
	begin
		pulse<=0;
		counter<=0;
	end 
	else if(~bus_busy)        //bus not busy, pulse starts , 00 to 99 period= pulse 0
	begin
		pulse<=0;
		counter<=0;
	end
	else if(counter == (clk_count_1bit-1))        //100 to 199 period= pulse 1
	begin
		pulse<=1;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*2 - 1)        //200 to 299 period=pulse 2
	begin
		pulse<=2;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*3 - 1)        //300 to 399 period=pulse 3
	begin
		pulse<=3;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*4 - 1)        //at 400 , reset, period=pulse 0
	begin
		pulse<=0;
		counter<=0;
	end
	else
	begin
		counter<=counter + 1;
	end
end
 
 
/////////temporary registers used for FSM///////////	
reg [3:0] bitcounter=0; //for 8 bit serial data counting
reg [7:0] data_addr; // address data 
reg sda_enable=0;// enable serial data from target 
reg r_ack=0;//read acknowledgement
	always@(posedge clk)
	begin
      if(rst)   //reset all signal
		begin
			bitcounter<=0;
			data_addr<=0;
			scl_temp<=1;
			sda_temp<=1;
			state<=Idle;
			ack_error<=0;
			bus_busy<=0;
		    done<=0;
		end
	else 
		begin
			case(state)
		Idle:  //idle state 0
			begin
				//done<=0;
				if(new_data==1)
				begin
					data_addr <= {addr,rw};
					tx_data<=data_in;
					bus_busy<=1;
					state<=Start;
					ack_error<=0;
				end
				else
				begin
					data_addr <= 0;
					bus_busy<=0;
					tx_data<=0;
					state<=Idle;
					ack_error<=0;
				end
			end

		Start:  //start state 1
			begin
				done<=0;
				sda_enable<=1;
				case(pulse)            //FSM for high to low pulse generation
				0: begin 
					scl_temp<=1;
					sda_temp<=1;
					end
				1: begin 
					scl_temp<=1;
					sda_temp<=1;
					end
				2: begin 
					scl_temp<=1;
					sda_temp<=0;
					end
				3: begin 
					scl_temp<=1;
					sda_temp<=0;
					end
				endcase
				if(counter==clk_count_1bit*4 - 1)
					begin 
					state<= Write_addr;
					scl_temp<=0;
					end
				else state<= Start;
			end
		Write_addr:   //address writing state
			begin
				sda_enable<=1;
				if(bitcounter<=7) begin
						case(pulse)            //FSM for high to low pulse generation
						0: begin 
							scl_temp<=0;
							sda_temp<=0;
							end
						1: begin 
							scl_temp<=0;
							sda_temp<=data_addr[7-bitcounter];  //send msb to lsb bit by bit
                        end
						2: begin 
							scl_temp<=1;
							end
						3: begin 
							scl_temp<=1;
							end
						endcase
						if(counter==clk_count_1bit*4 - 1)
						begin 
							state<= Write_addr;
							scl_temp<=0;
							bitcounter<=bitcounter+1'b1;
						end
						else
							begin 
								state<= Write_addr;
							end
                  end
				else 
					begin
                      $display("add is sent addr=%b",data_addr[7:1]);
					state<=Ack_1;
					sda_enable<=0;
					bitcounter<=0;
					end
			end
		Ack_1: begin
				 sda_enable<=0;
			    case(pulse)
					0:begin
						scl_temp<=0;
						sda_temp<=0;
					end
					1: begin
						scl_temp<=0;
						sda_temp<=0;
					end
					2:begin
						scl_temp<=1;
						sda_temp<=0;
						r_ack<=sda_in;
                     // $strobe("ack recieved =%b",r_ack);
					end
					3:begin
						scl_temp<=1;
					end
					endcase
				if(counter==clk_count_1bit*4 - 1)
				begin 
						if(r_ack==1'b0 && data_addr[0]==0)
							begin
								state<= Write_data;
								sda_temp<=0;
								sda_enable<=1;
								bitcounter<=0;
							end
						else if(r_ack==1'b0 && data_addr[0]==1)
							begin
								state<= Read_data;
								sda_temp<=1;
								sda_enable<=0;
								bitcounter<=0;
							end
						else 
							begin 
								state<= Stop;
								sda_enable<=1;
								ack_error<=1;
							end
				end
				else 
				begin
					state<=Ack_1;
				end
			end
		Write_data: begin
					if(bitcounter<=7) begin
						case(pulse)            //FSM for high to low pulse generation
						0: begin 
							scl_temp<=0;
							sda_enable<=1;
							end
						1: begin 
							scl_temp<=0;
							 sda_temp<=tx_data[7-bitcounter]; 
							 //send msb to lsb bit by bit
                        end
						2: begin 
							scl_temp<=1;
							end
						3: begin 
							scl_temp<=1;
							end
						endcase
						if(counter==clk_count_1bit*4 - 1)
						begin 
							state<= Write_data;
							scl_temp<=0;
                            sda_temp<=0;
							bitcounter<=bitcounter+1'b1;
						end
						else
							begin 
								state<= Write_data;
							end
                  end
				else 
					begin
                  //    $display("add is sent addr=%b",data_addr[7:1]);
					state<=Ack_2;
					sda_enable<=0;
					bitcounter<=0;
					end
			end
		Read_data: begin
				sda_enable=0;
					if(bitcounter<=7) begin
						case(pulse)            //FSM for high to low pulse generation
						0: begin 
							scl_temp<=0;
							sda_temp<=0;
							end
						1: begin 
							scl_temp<=0;
							sda_temp<=0; 
							//send msb to lsb bit by bit
                        end
						2: begin 
							scl_temp<=1;
                          rx_data[7:0]<=(counter==200)?{rx_data[6:0],sda_in} :rx_data;
							end
						3: begin 
							scl_temp<=1;
							end
						endcase
						if(counter==clk_count_1bit*4 - 1)
						begin 
							state<= Read_data;
							scl_temp<=0;
							bitcounter<=bitcounter+1'b1;
						end
						else
							begin 
								state<= Read_data;
							end
                  end
				else 
					begin
                  //    $display("add is sent addr=%b",data_addr[7:1]);
					state<=Controller_ack;
					sda_enable<=1; //master sends acknowledgement to slave
					bitcounter<=0;
					end
			end
		Controller_ack: begin
			 sda_enable<=1;
			    case(pulse)
					0:begin
						scl_temp<=0;
						sda_temp<=1;
					end
					1: begin
						scl_temp<=0;
						sda_temp<=1;
					end
					2:begin
						scl_temp<=1;
						sda_temp<=1;
					end
					3:begin
						scl_temp<=1;
						sda_temp<=1;
					end
					endcase
				if(counter==clk_count_1bit*4 - 1)
				begin 
				state<= Stop;
				sda_temp<=0;
				sda_enable<=1;
				end
				else 
				begin
					state<=Controller_ack;
				end
		end
		Ack_2: begin
          $display("in ack2");
				 sda_enable<=0;
        //  sda_enable<=0;
			    case(pulse)
					0:begin
						scl_temp<=0;
                      $strobe("time %0t scl_t %b",$time,scl_temp);
						sda_temp<=0;
					end
					1: begin
						scl_temp<=0;
						sda_temp<=0;
                      $strobe("time %0t scl_t %b",$time,scl_temp);
					end
					2:begin
						scl_temp<=1;
						sda_temp<=0;
						r_ack<=sda_in;
                      $strobe("time %0t scl_t %b",$time,scl_temp);
                    //  $strobe("ack recieved =%b",r_ack);
					end
					3:begin
						scl_temp<=1;
                     $strobe("time %0t scl_t %b",$time,scl_temp);
					end
					endcase
				if(counter==clk_count_1bit*4 - 1)
				begin 
				//scl_temp<=0;
				sda_enable<=1;
						if(r_ack==1'b0)
							begin
								state<= Stop;
								ack_error<=0;
							end
						else 
							begin 
								state<= Stop;
								ack_error<=1;
							end
				end
				else 
				begin
					state<=Ack_2;
				end
			end
		Stop: begin
			sda_enable<=1;
			    case(pulse)
					0:begin
						scl_temp<=1;
						sda_temp<=0;
					end
					1: begin
						scl_temp<=1;
						sda_temp<=0;
					end
					2:begin
						scl_temp<=1;
						sda_temp<=1;
					end
					3:begin
						scl_temp<=1;
						sda_temp<=1;
					end
					endcase
				if(counter==clk_count_1bit*4 - 1)
				begin 
				//scl_temp<=0;
                  //sda_temp<=0;
                 // new_data<=0;
				sda_enable<=1;
				state<=Idle;
				bus_busy<=0;
				done<=1;
				end
				else 
				begin
					state<=Stop;
				end
		end
		default: begin
				state<=Idle;
			end
		endcase
	end
    end
assign sda_in=(sda_enable==1)?((sda_temp==0)?1'b0:1'b1):1'bz;   //serial data output-bidirectional 
                                                                //here we have to use return value from slave
assign scl_in=scl_temp;
assign data_out=rx_data;
endmodule



module i2c_target(sda,scl,clk,rst,ack_error,done);
// defining the ports
 
input scl;
input clk,rst;
inout sda;
output reg ack_error;
output reg done;
 
 
// defining the parameters
 
localparam Idle=0;
localparam Wait_pulse=1;
localparam Read_addr=2;
localparam Ack1_send=3;
localparam Read_data=4;
localparam Ack2_send=5;
localparam Send_data=6;
localparam Controller_ack=7;
localparam Detect_stop=8;
reg [3:0] state=Idle;
 
//reg [7:0] mem [128];
reg [7:0] r_addr;
reg [6:0] addr;
//reg rd_mem=0;
//reg wr_mem=0;
reg [7:0] data_in;
reg [7:0] data_out=8'b10001100; //data for tx to controller
reg sda_temp;
reg sda_enable;
reg [3:0] bitcnt=0;
 
// defining the parameter related to frequency
 
parameter ADDRS=7'b1101101;
initial
  begin
    $display("slave address is =%b",ADDRS);
  end
parameter system_freq=40000000;                                     //40 MHz
parameter i2c_freq=100000;                                               //standard mode frequency = 100 KHz
parameter clk_count_4bit=(system_freq/i2c_freq);             //clock count 400 cycle
parameter clk_count_1bit=(clk_count_4bit/4);                    //clk count 100 cycles
integer counter=0;

 
//4 pulses
reg [1:0] pulse=0;
reg bus_busy;
 
always@(posedge clk)
begin
	if(rst)                                 //reset condition
	begin
		pulse<=0;
		counter<=0;
	end 
	else if(~bus_busy)           //bus not busy, pulse starts , 00 to 99 period= pulse 0
	begin
		pulse<=2;
		counter<=202;   //synchronization
	end
	else if(counter == (clk_count_1bit-1))        //100 to 199 period= pulse 1
	begin
		pulse<=1;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*2 - 1)        //200 to 299 period=pulse 2
	begin
		pulse<=2;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*3 - 1)        //300 to 399 period=pulse 3
	begin
		pulse<=3;
		counter<=counter+1;
	end
	else if(counter == clk_count_1bit*4 - 1)        //at 400 , reset, period=pulse 0
	begin
		pulse<=0;
		counter<=0;
	end
	else
	begin
		counter<=counter + 1;
	end
end
 
reg scl_temp;
reg [2:0] NS=0;
reg match;
 
 
always@(posedge clk) begin
scl_temp<=scl;
end
reg r_ack;
 
  always@(posedge clk)
  begin 
  if(rst)
	begin
	 bitcnt<=0;
	 state<=Idle;
	 r_addr<=0;
	 sda_enable<=0;
	 sda_temp<=0;
	 addr<=0;
	 data_in<=0;
	 ack_error<=0;
	 done<=0;
	 bus_busy<=0;
	end
	else 
	begin
	case(state)
		Idle: begin
				if(scl==1 && sda==0)
					begin
					bus_busy<=1;
					state<=Wait_pulse;
					end
				else begin
					state<=Idle;
				end
			end
		Wait_pulse: begin 
				if(pulse==3 && counter==399) begin
					state<=Read_addr;
				end
				else state<=Wait_pulse;
			end
		Read_addr:begin
			sda_enable<=0;
			if(bitcnt<=7)  begin
					case(pulse)               //FSM for high to low pulse generation
						0: begin 
							end
						1: begin 
							end
						2: begin 
								 if(counter==200) begin
										 r_addr={r_addr[6:0],sda};
								 end
								 else begin
										 r_addr=r_addr;
								 end
							end
						3: begin 
							end
					endcase
						if(counter==clk_count_1bit*4 - 1)
								begin 
									state<= Read_addr;
									scl_temp<=0;
									bitcnt<=bitcnt+1;
								end
						else begin 
										state<= Read_addr;
						end	
				end
				else begin
					addr<=r_addr[7:1];
					// $strobe("add is recived addr=%b",addr);
					state<=Ack1_send;
					bitcnt<=0;
					sda_enable<=1;
            end
		end//end of read add
		Ack1_send: begin
					if(addr==ADDRS)
                      begin
						match=1'b1;
          //$display("ack is =%b",~match);
                      end
					else
                      begin
						match=1'b0;
                        //$display("ack is =%b",match);
                      end
				case(pulse)  //FSM for high to low pulse generation
					0: begin 
						scl_temp<=0;
						sda_enable<=0;
						end
					1: begin 
					  sda_temp=~match;
					  sda_enable<=1;
					  //$monitor("ack is =%b",~match);
						end
					2: begin
						end
					3: begin 
						end
				endcase
				if(counter==clk_count_1bit*4 - 1)
						begin 
                          if(r_addr[0]==1) begin
                            state<=Send_data;
                          end
                          else begin
                          state<=Read_data;
                          end
						end
						else
							begin 
								state<= Ack1_send;
							end	
				end
		Read_data:begin
			sda_enable<=0;
			if(bitcnt<=7)
			begin
				case(pulse)
				0:begin end
				1:begin end
                  2:begin data_in[7:0]<=(counter==200) ?{data_in[6:0],sda}: data_in ; end
				3:begin end
				endcase
				if(counter==clk_count_1bit*4 - 1)
						begin 
							state<=Read_data;
							bitcnt<=bitcnt+1;
						end
						else
							begin 
								state<= Read_data;
							end	
				end
			else 
			begin
				state<=Ack2_send;
				bitcnt<=0;
				sda_enable<=0;
				//wr_mem<=1'b1;
			end
		end
		Ack2_send:begin
			case(pulse)
				0:begin 
                  scl_temp<=0;
                end
				1:begin 
                  sda_temp<=0; sda_enable<=1; end
				2:begin end
				3:begin end
			endcase
			if(counter==clk_count_1bit*4 - 1)
						begin 
							state<=Detect_stop;
							sda_enable<=0;
						end
			else
				begin 
					state<= Ack2_send;
				end	
		end
		Send_data:begin
			sda_enable<=1;
			if(bitcnt<=7)
			begin
				case(pulse)
				0:begin end
				1:begin sda_temp<= (counter==100) ? data_out[7-bitcnt] :sda_temp ;  end
				2:begin end
				3:begin end
				endcase
				if(counter==clk_count_1bit*4 - 1)
						begin 
							state<=Send_data;
							bitcnt<=bitcnt+1;
						end
						else
							begin 
								state<= Send_data;
							end	
				end
			else 
			begin
				state<=Controller_ack;
				bitcnt<=0;
				sda_enable<=0;
			end
		end
	Controller_ack:begin
			case(pulse)
				0:begin end
				1:begin end
				2:begin r_ack<=(counter==200) ? sda : r_ack;  end
				3:begin end
			endcase
			if(counter==clk_count_1bit*4 - 1)
				begin
						if(r_ack==1)
						begin
							state<=Detect_stop;
							sda_enable<=0;
							ack_error=0;
						end
						else 
						begin
							ack_error<=1;
							state<=Detect_stop;
							sda_enable<=0;
						end
                end
			else
				begin 
					state<=Controller_ack;
				end	
		end
		Detect_stop: begin
          if(pulse==2'b11 && counter==399)
			begin
				state<=Idle;
				bus_busy<=0;
				done<=1;
			end
			else 
              begin
				state<=Detect_stop;
			end
		end
	default:state<=Idle;
	endcase
        end
    end
  assign sda=(sda_enable==1)?((sda_temp==0) ? 1'b0:1'b1):1'bz; 
endmodule

