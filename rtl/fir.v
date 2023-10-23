`timescale 1ns / 1ps
module fir

#(  parameter pADDR_WIDTH = 12, // 12 bits address for ram
    parameter pDATA_WIDTH = 32, // 32 bits data width
    parameter Tape_Num    = 11  //
)
(
    output  reg                     awready,        // w
    output  reg                     wready,         //w
    input   wire                     awvalid,       //
    input   wire  [(pADDR_WIDTH-1):0] awaddr,       //
    input   wire                     wvalid,        //
    input   wire                     stream_start_send,
    input   wire signed [(pDATA_WIDTH-1):0] wdata,         //  
    output  reg                     arready,        //
    input   wire                     rready,        //
    input   wire                     arvalid,       //  
    input   wire [(pADDR_WIDTH-1):0] araddr,        //
    output  reg			trans_data,
    output  reg                     rvalid,     //  
    output  reg  signed [(pDATA_WIDTH-1):0] rdata,          //
    input   wire                     ss_tvalid,     //
    input   wire  signed [(pDATA_WIDTH-1):0] ss_tdata,      //
    input   wire                     ss_tlast,      //
    output  reg                     ss_tready,  //
    input   wire                     sm_tready,     //
    output  reg                     sm_tvalid,  //w
    output  reg  signed [(pDATA_WIDTH-1):0] sm_tdata,       //
    output  wire                     sm_tlast,      //
   
    // bram for tap RAM
    output  reg [3:0]               tap_WE,     // tap select byte in one word
    output  reg                     tap_EN,     // tap bram enable
    output  reg  signed [(pDATA_WIDTH-1):0] tap_Di,     // tap bram datain
    output  reg [(pADDR_WIDTH-1):0] tap_A,          // tap bram data_address
    input   wire  signed [(pDATA_WIDTH-1):0] tap_Do,        // tap bram dataout

    // bram for data RAM
    output  reg [3:0]               data_WE,        // data select byte in one word
    output  reg                     data_EN,        // data bram enable
    output  reg  signed [(pDATA_WIDTH-1):0] data_Di,        // data bram datain
    output  reg [(pADDR_WIDTH-1):0] data_A,     // data bram data_address
    input   wire signed [(pDATA_WIDTH-1):0] data_Do,       // data bram dataout
    input   wire                     axis_clk,      // universal system clk
    input   wire                     axis_rst_n     // universal rst_n
    );

reg [2:0]   STATE_r;
reg [2:0]   STATE_w;
reg [2:0]   STATE_s;




//write fsm
parameter   wr_addr             = 3'b000;
parameter   wr_addr_shakehand   = 3'b001;
parameter   wr_data             = 3'b010;
parameter   wr_data_shakehand   = 3'b011;
parameter   write               = 3'b100;          
parameter   init_w              = 3'b101;

//read fsm
parameter   rd_addr             = 3'b000;
parameter   rd_addr_shakehand   = 3'b001;
parameter   rd_data             = 3'b010;
parameter   rd_data_shakehand   = 3'b011;
parameter   read                = 3'b100;
parameter   init_r              = 3'b101;


//fir_fsm
parameter   init_s             = 3'b10;
parameter   start_stream       = 3'b00;
parameter   end_stream         = 3'b01;




//初始缓冲init
reg [3:0] init_cnt;
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n) init_cnt <= 0;
    else    init_cnt <= (init_cnt == 4) ? 0 : (init_cnt + 1);
end


//stream fsm
always@(posedge axis_clk)
begin
    if(!axis_rst_n)    STATE_w <= init_w;
    else    
    begin
        case(STATE_s)
            init_s:   
            begin
                if(ss_tvalid && stream_start_send)  
                begin 
                	STATE_s <= start_stream ;
                	ss_tready <= 1;
                end
                else            
                	STATE_s <= init_s;                    
            end
            start_stream:        
            begin
            	if (ss_tlast && !start_stream)
            		STATE_s <= end_stream; 				
            end
            end_stream:          
            if(ss_tlast) 
            	STATE_s <= init_s;
            default:             
            	STATE_s <= init_s;
        endcase
    end    
end



//write fsm
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n)    STATE_w <= init_w;
    else    
    begin
        case(STATE_w)
            init_w:   begin
                if(init_cnt == 4)   STATE_w <= wr_addr;
                    else            STATE_w <= init_w;                    
            end
            wr_addr:            STATE_w <= wr_addr_shakehand;
            wr_addr_shakehand:  begin
                if(awvalid == 1'b1 && awready == 1'b1)  STATE_w <= wr_data;
                    else                                STATE_w <= wr_addr_shakehand;    
            end
            wr_data:            STATE_w <= wr_data_shakehand;
            wr_data_shakehand:  begin
                if(wvalid == 1'b1 && wready == 1'b1)    STATE_w <= write;
                    else                                STATE_w <= wr_data_shakehand;
            end
            write:          if(stream_start_send==0)    STATE_w <= wr_addr;
            default:           STATE_w <= init_w;
        endcase
    end    
end



//read fsm
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n)    STATE_r <= init_r;
    else    
    begin
        case(STATE_r)
            init_r:  
            begin
                if(init_cnt == 4)   STATE_r <= rd_addr;
                    else            STATE_r <= init_r;                    
            end
            rd_addr:            STATE_r <= rd_addr_shakehand;
            rd_addr_shakehand:  
            begin
                if(arvalid == 1'b1 && arready == 1'b1)  STATE_r <= rd_data;
                    else                                STATE_r <= rd_addr_shakehand;
            end
            rd_data:            STATE_r <= rd_data_shakehand;
            rd_data_shakehand:  
            begin
                if(rready == 1'b1 && rvalid == 1'b1)    STATE_r <= read;
                    else                                STATE_r <= rd_data_shakehand;
            end
            read:        if(stream_start_send==0)      STATE_r <= rd_addr;
            default:           STATE_r <= init_r;
        endcase
    end    
end




//address write
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n)
    begin
        //awaddr  <= 32'b0;
        awready <= 1'b0;
    end    
    else if(awvalid)    //STATE_w == wr_addr
    begin
        tap_A <= awaddr;
        awready <= 1'b1;
        tap_EN <= 1'b1;
    end
    else    
    begin
        //awaddr <= awaddr;
        awready <= awready;
    end
end
always@(posedge axis_clk)
begin
    if(STATE_w == wr_addr_shakehand)  
    begin
        if(awvalid == 1'b1 && awready == 1'b1)  
        begin
            awready <= 1'b0;     //成功握手，valid拉低
            //tap_EN <= 0;
            //awaddr <= 32'b0;
        end
    end
end

//data write
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n) begin
        //wdata <= 32'b0;
        wready <= 1'b0;
        tap_EN <= 0;
    end
    else if(STATE_w == wr_data)  
    begin
        tap_Di <= wdata;
        tap_WE <= 4'b1111;
        tap_EN <= 1'b1;
        wready <= 1'b1;
    end    
    else    
    begin
        tap_Di <= tap_Di;
        wready <= wready;
    end
end

always@(posedge axis_clk)
begin
   if(STATE_w == wr_data_shakehand)   begin
        if(wvalid == 1'b1 && wready == 1'b1)    
        begin
            wready <= 1'b0;
            //tap_Di <= 0;
          //  wdata  <= 0;
        end
        else    
        begin
            wready <= wready;
        end
   end
end


// address read
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n)
    begin
        //araddr <= 32'b0;
        arready <= 1'b0;
    end
    else if (STATE_r == rd_addr)  
    begin
        tap_A <= araddr;
        arready <= 1'b1;
        tap_EN <= 1'b1;
    end
    else    
    begin
        //araddr <= araddr;
        arready <= arready;
    end
end
always@(posedge axis_clk)
begin
    if(STATE_r == rd_addr_shakehand)  
    begin
        if(arvalid == 1'b1 && arready == 1'b1)  
        begin
            arready <= 1'b0;
            //tap_EN <= 0;
            rvalid  <= 1'b1;
        end
    end
end



//read data form tap bram
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n) begin
        rvalid <= 1'b0;
    end
    else if(STATE_r == rd_data)    
    begin
	rvalid  <= 1'b1;
        tap_EN  <= 1'b1;
        rdata <= tap_Do;
        tap_WE  <= 4'b0000;
    end
end
always@(posedge axis_clk)
begin
    if(STATE_r == rd_data_shakehand)  
    begin
        if(rready == 1'b1 && rvalid == 1'b1)    
        begin
            rvalid <= 1'b0;
            //tap_EN <= 1'b0;
        end
        else  
        begin  
            rvalid <= rvalid;
            
        end
    end
end



//counter
reg [3:0] cnt_11;
always@(posedge axis_clk or negedge axis_rst_n)
begin
    if(!axis_rst_n)
    begin
        cnt_11 <= 4'b0000;
    end
    else if(stream_start_send==1 || cnt_11 ==10)
    begin
        cnt_11 <= 0;
    end
    else if(ss_tvalid)
    begin
        cnt_11 <= cnt_11 + 1;
    end
end



reg  [11:0] sss; 
reg [31:0] temp_mac;
reg [31:0] temp_data;
reg [31:0] temp_result;
reg [31:0] temp_coef;
reg [11:0] ptr_coef_bram;
reg [11:0] ptr_data_bram;
reg [11:0] ptr_data_replace_bram;


always@(cnt_11)
begin	
	if(cnt_11==0)
		trans_data = 1;
	else
		trans_data = 0;

end



//reset ptr and reg
always@(negedge axis_rst_n)
begin
    if(!axis_rst_n)
    begin
    	ptr_coef_bram <= 0;
    	ptr_data_bram <= 0;
    	ptr_data_replace_bram <= 0;
    	temp_coef <= 0;
    	temp_result <= 0;
    	temp_mac <= 0; 
    	sss <= 0;
    	temp_data <= 0;
    end
end

//ptr_coef_bram
always@(posedge axis_clk or negedge axis_rst_n)
begin
if(STATE_s==start_stream)
begin
    ptr_coef_bram <= ptr_coef_bram + 11'd4;
    if(ptr_coef_bram == 11'd40)
		ptr_coef_bram <= 0;
    tap_EN <= 1'b1;
    tap_WE <= 4'b0000;
    tap_A <= ptr_coef_bram;
    temp_coef <= tap_Do;




    
end
end

//ptr_data_replace_bram
always@(posedge axis_clk or negedge axis_rst_n)
begin 
if (STATE_s==start_stream)
begin
    if(cnt_11 == 4'd0 && ptr_data_replace_bram < 40)
    begin
			
            data_EN               <= 1'b1;
           
            data_WE               <= 4'b1111;
            ptr_data_replace_bram <= ptr_data_replace_bram + 11'd4;
            data_A                <= ptr_data_replace_bram;
            data_Di               <= ss_tdata;
        //end    
    end
    else if(cnt_11 == 4'd0 && ptr_data_replace_bram == 40)
    begin 

        data_EN               <= 1'b1;
        data_WE               <= 4'b1111;
        ptr_data_replace_bram <= 11'd0;
        data_A                <= ptr_data_replace_bram;
        data_Di               <= ss_tdata;
    end
    else
    begin
        ptr_data_replace_bram <= ptr_data_replace_bram;
    end   
 end
end




//ptr_data_bram
always@(ptr_data_replace_bram)
begin
    if ((cnt_11 != 0) && (ptr_data_bram != 0)&& (STATE_s==start_stream))
    begin
    sss <= 0;
        data_WE       <= 4'b0000;
        data_A        <= ptr_data_bram;
    	temp_data     <= data_Do;  
        ptr_data_bram <= ptr_data_bram - 4;
    end     
    else if ((cnt_11 != 0) && (ptr_data_bram == 0)&& (STATE_s==start_stream))
    begin
    	sss <= 1;
        data_EN       <= 1;
        data_WE       <= 4'b0000;
        data_A        <= ptr_data_bram;
        temp_data     <= data_Do;
        ptr_data_bram <= 11'd40;
    end   
    else if((cnt_11 == 0) && (ptr_data_bram != 0)&& (STATE_s==start_stream))
    begin
		sss <= 2;
        ptr_data_bram <= ptr_data_replace_bram;
        data_EN       <= 1;
        data_WE       <= 4'b0000;
        data_A        <= ptr_data_bram;
        temp_data     <= data_Do;
        ptr_data_bram <= ptr_data_bram - 4;
    end 
    else if((cnt_11 == 0) && (ptr_data_bram == 0)&&(STATE_s==start_stream))
    begin
    	sss <= 3;
        ptr_data_bram <= ptr_data_replace_bram;
        data_EN       <= 1111;
        data_WE       <= 4'b0000;
        data_A        <= ptr_data_bram;
        temp_data     <= data_Do;
        ptr_data_bram <= 11'd40;
    end 
    else
    begin
    	ptr_data_bram <= ptr_data_bram;
    end
end

// && (STATE_s==start_stream)

always@(posedge axis_clk)
begin
if(STATE_s==start_stream)
begin
    //temp_result = 0;
    temp_mac <= temp_data*temp_coef;
    temp_result <=  temp_result + temp_mac;
    if(sm_tready)
    begin
        ss_tready <= 1; 
        sm_tdata <= temp_result;
    end
    end
end



endmodule
