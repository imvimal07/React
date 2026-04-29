/*Welcome_Display
 *
 * By: Gordon Lee
 * Date: 15/04/2024
 *
 *----------
 *This moudule is to display "Welome to the reaction game" when it turn on
 *----------
 *
 */

module Welcome_Display ( 
	// Global Clock/Reset
   // - Clock
   input              clock,
   // - Global Reset
   input              globalReset,
   // - Application Reset - for debug
   output             resetApp,
    
   // LT24 Interface
   output             LT24Wr_n,
   output             LT24Rd_n,
   output             LT24CS_n,
   output             LT24RS,
   output             LT24Reset_n,
   output [     15:0] LT24Data,
   output             LT24LCDOn
);

//-----Local Variables-----

reg  [ 7:0] xAddr;
reg  [ 8:0] yAddr;
reg  [15:0] pixelData;
wire        pixelReady;
reg         pixelWrite;


//-----LCD Limits-----
localparam LCD_W = 240;
localparam LCD_H = 320;

LT24Display #(
    .WIDTH       (LCD_W ),
    .HEIGHT      (LCD_H ),
    .CLOCK_FREQ  (50000000   )
) Display (
    //Clock and Reset In
    .clock       (clock      ),
    .globalReset (~globalReset),
    //Reset for User Logic
    .resetApp    (resetApp   ),
    //Pixel Interface
    .xAddr       (xAddr      ),
    .yAddr       (yAddr      ),
    .pixelData   (pixelData  ),
    .pixelWrite  (pixelWrite ),
    .pixelReady  (pixelReady ),
    //Use pixel addressing mode
    .pixelRawMode(1'b0       ),
    //Unused Command Interface
    .cmdData     (8'b0       ),
    .cmdWrite    (1'b0       ),
    .cmdDone     (1'b0       ),
    .cmdReady    (           ),
    //Display Connections
    .LT24Wr_n    (LT24Wr_n   ),
    .LT24Rd_n    (LT24Rd_n   ),
    .LT24CS_n    (LT24CS_n   ),
    .LT24RS      (LT24RS     ),
    .LT24Reset_n (LT24Reset_n),
    .LT24Data    (LT24Data   ),
    .LT24LCDOn   (LT24LCDOn  )
);

// -----X Counter-----

wire [7:0] xCount;
UpCounterNbit #(
    .WIDTH    (          8),
    .MAX_VALUE(LCD_W    -1)
) xCounter (
    .clock     (clock     ),
    .reset     (resetApp  ),
    .enable    (pixelReady),
    .countValue(xCount    )
);

// -----Y Counter-----

wire [8:0] yCount;
wire yCntEnable = pixelReady && (xCount == (LCD_W-1));
UpCounterNbit #(
    .WIDTH    (           9),
    .MAX_VALUE(LCD_H     -1)
) yCounter (
    .clock     (clock     ),
    .reset     (resetApp  ),
    .enable    (yCntEnable),
    .countValue(yCount    )
);

wire [16:0] romAddr = ({8'b0,yCount} * 17'd240) + {9'b0,xCount};

wire [15:0] imagePixel;

//Import figures

/*WelcomeROM WelcomeROM(
	 .clock   (clock    ),
	 .address (romAddr  ),
	 .q       (imagePixel)
);
*/
/*GGROM GGROM (
	 .clock   (clock    ),
	 .address (romAddr  ),
	 .q       (imagePixel)
);
*/
MaxROM MaxROM (
	 .clock   (clock    ),
	 .address (romAddr  ),
	 .q       (imagePixel)
);

//-----Colour setting-----
always @ (posedge clock or posedge resetApp) begin
    if (resetApp) begin
        pixelWrite <= 1'b0;
		  pixelData  <= 16'h0000;
		  xAddr      <= 8'd0;
		  yAddr      <= 9'd0;
    end else begin
		  pixelWrite <= 1'b1;
		  xAddr      <= xCount;
		  yAddr      <= yCount;
		  pixelData  <= imagePixel;
		  
	 end
end

endmodule

module UpCounterNbit #(
    parameter WIDTH = 10,               //10bit wide
    parameter INCREMENT = 1,            //Value to increment counter by each cycle
    parameter MAX_VALUE = (2**WIDTH)-1  //Maximum value default is 2^WIDTH - 1
)(   
    input                    clock,
    input                    reset,
    input                    enable,    //Increments when enable is high
    output reg [(WIDTH-1):0] countValue //Output is declared as "WIDTH" bits wide
);

always @ (posedge clock) begin
    if (reset) begin
        //When reset is high, set back to 0
        countValue <= {(WIDTH){1'b0}};
    end else if (enable) begin
        //Otherwise counter is not in reset
        if (countValue >= MAX_VALUE[WIDTH-1:0]) begin
            //If the counter value is equal or exceeds the maximum value
            countValue <= {(WIDTH){1'b0}};   //Reset back to 0
        end else begin
            //Otherwise increment
            countValue <= countValue + INCREMENT[WIDTH-1:0];
        end
    end
end

endmodule



