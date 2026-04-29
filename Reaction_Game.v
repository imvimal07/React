module Reaction_Game (
    input              CLOCK_50,
    input      [3:0]   KEY,
    input      [9:0]   SW,
    output     [9:0]   LEDR,// led
    output     [6:0]   HEX0,//sevensegs display
    output     [6:0]   HEX1,
    output     [6:0]   HEX2,
    output     [6:0]   HEX3,
    output     [6:0]   HEX4,
    output     [6:0]   HEX5,
    output             LT24Wr_n,//lt24 lcd interface
    output             LT24Rd_n,
    output             LT24CS_n,
    output             LT24RS,
    output             LT24Reset_n,
    output     [15:0]  LT24Data,
    output             LT24LCDOn
);

localparam LCD_W = 240;//screen sizing
localparam LCD_H = 320;

localparam ST_IDLE       = 3'd0;//game states
localparam ST_START_SEQ  = 3'd1;
localparam ST_GO         = 3'd2;
localparam ST_PASS       = 3'd3;
localparam ST_GAMEOVER   = 3'd4;
localparam ST_WIN_TROPHY = 3'd5;
localparam ST_WIN_MAX    = 3'd6;
localparam ST_INTRO      = 3'd7;

localparam PASS_NONE = 2'd0;
localparam PASS_1    = 2'd1;
localparam PASS_2    = 2'd2;

localparam INTRO_MS          = 14'd5000;
localparam WIN_TROPHY_MS         = 14'd2000;
localparam RANDOM_WAIT_MS    = 14'd600;
localparam START_LIGHT_ON_MS = 9'd180;
localparam START_LIGHT_OFF_MS= 9'd90;
localparam START_LIGHTS      = 4'd10;
localparam CAR_ROM_W             = 8'd24;
localparam CAR_ROM_H             = 9'd16;
localparam CAR_LOOP_MS       = 14'd760;
localparam CAR_ROM_PIXELS     = 9'd384;

localparam COL_BLACK = 16'h0000;// RGB565 colour palette used by the procedural LCD renderer
localparam COL_WHITE = 16'hFFFF;
localparam COL_RED   = 16'hF800;
localparam COL_GREEN = 16'h07E0;
localparam COL_GREY  = 16'h8410;
localparam COL_TRACK = 16'h52AA;
localparam COL_GRASS = 16'h03E0;
localparam COL_BLUE     = 16'h001F;
localparam COL_CYAN     = 16'h07FF;
localparam COL_YELLOW   = 16'hFFE0;
localparam COL_MAGENTA  = 16'hF81F;
localparam COL_ORANGE   = 16'hFD20;
localparam COL_NAVY     = 16'h0010;
localparam COL_DKGREEN  = 16'h03E0;
localparam COL_CAR_RED  = 16'hF000;
localparam COL_CAR_DARK = 16'h2104;
localparam COL_SILVER   = 16'hC638;

wire globalReset = 1'b0;
wire resetApp;

reg  [7:0]  xAddr;
reg  [8:0]  yAddr;
reg  [15:0] pixelData;
reg         pixelWrite;
wire        pixelReady;

reg  [7:0] scanX;
reg  [8:0] scanY;
reg  [15:0] nextPixelColor;

reg  [15:0] msDiv;
reg         msTick;
reg  [15:0] lfsr;

reg [2:0]  gameState;//CORE GAME STATES
reg [3:0]  roundIdx;//SELects one of the 10 fixed reCTIONS wondows
reg [3:0]  lostRoundIdx;
reg [13:0] stateTimerMs;
reg [13:0] reactionMs;//runs only after the green "go" appears
reg [13:0] carAnimCounterMs;//drives the straign line car animation only on successful rounds
reg [3:0]  startPhase;//implement red light sequence
reg [8:0]  startPhaseTimerMs;
reg  [13:0] waitCounterMs;
reg  [10:0] winScreenTimerMs;
reg  [1:0]  lastPassClass;

// Time digits for the seven-segment and LCD reaction-time display.
reg [3:0] liveSecTens, liveSecOnes, liveMsHundreds, liveMsTens, liveMsOnes;// Live digits update every millisecond during ST_GO.
reg [3:0] lastSecTens, lastSecOnes, lastMsHundreds, lastMsTens, lastMsOnes;// Last digits capture the most recent successful or failed reaction time.

reg  [3:0]  pass1Tens, pass1Ones, pass2Tens, pass2Ones;// Pass counters stored directly in BCD for easy display.


wire startPressed;
wire reactPressed;
wire skipPressed; 
wire menuPressed; 

reg sw9Sync0, sw9Sync1, sw9Prev;
wire sw9Restart = sw9Sync1 & ~sw9Prev;

wire [13:0] allowedReactionMs   = roundWindowMs(roundIdx);
wire [13:0] reactionThresholdMs = {1'b0, allowedReactionMs[13:1]};
wire [3:0]  roundNumberDigit    = roundIdx + 4'd1;

wire [3:0] hex5Value = (gameState == ST_GO) ? liveSecTens    : lastSecTens;
wire [3:0] hex4Value = (gameState == ST_GO) ? liveSecOnes    : lastSecOnes;
wire [3:0] hex3Value = (gameState == ST_GO) ? liveMsHundreds : lastMsHundreds;
wire [3:0] hex2Value = (gameState == ST_GO) ? liveMsTens     : lastMsTens;
wire [3:0] hex1Value = (gameState == ST_GO) ? liveMsOnes     : lastMsOnes;
wire [3:0] hex0Value = 4'd0;

wire [7:0] trackCarX = 8'd18 + carAnimCounterMs[9:2];
wire [16:0] fullRomAddr = ({8'b0, scanY} * 17'd240) + {9'b0, scanX};
wire [7:0]  introPixel;
wire [7:0]  menuPixel;
wire [7:0]  crashPixel;
wire [7:0]  trophyPixel;
wire [7:0]  maxPixel;
wire [15:0] carPixel;
wire [8:0]  carLocalX = {1'b0, scanX} - {1'b0, trackCarX};
wire [8:0]  carLocalY = scanY - 9'd200;
wire        carPixelInRange =
    (scanX >= trackCarX) &&
    (scanX < (trackCarX + CAR_ROM_W)) &&
    (scanY >= 9'd200) &&
    (scanY < (9'd200 + CAR_ROM_H));
wire [8:0]  carRomAddr = (carLocalY * CAR_ROM_W) + carLocalX;
wire [8:0]  carRomAddrSafe = carPixelInRange ? carRomAddr : 9'd0;


LT24Display #(
    .WIDTH(LCD_W),
    .HEIGHT(LCD_H),
    .CLOCK_FREQ(50000000)
) u_lcd (
    .clock(CLOCK_50),
    .globalReset(globalReset),
    .resetApp(resetApp),
    .xAddr(xAddr),
    .yAddr(yAddr),
    .pixelData(pixelData),
    .pixelWrite(pixelWrite),
    .pixelReady(pixelReady),
    .pixelRawMode(1'b0),
    .cmdData(8'b0),
    .cmdWrite(1'b0),
    .cmdDone(1'b0),
    .cmdReady(),
    .LT24Wr_n(LT24Wr_n),
    .LT24Rd_n(LT24Rd_n),
    .LT24CS_n(LT24CS_n),
    .LT24RS(LT24RS),
    .LT24Reset_n(LT24Reset_n),
    .LT24Data(LT24Data),
    .LT24LCDOn(LT24LCDOn)
);

ButtonConditioner b0 (.clock(CLOCK_50), .reset(resetApp), .sampleTick(msTick), .button_n(KEY[0]), .pressed(), .pressPulse(startPressed));
ButtonConditioner b1 (.clock(CLOCK_50), .reset(resetApp), .sampleTick(msTick), .button_n(KEY[1]), .pressed(), .pressPulse(reactPressed));
ButtonConditioner b2 (.clock(CLOCK_50), .reset(resetApp), .sampleTick(msTick), .button_n(KEY[2]), .pressed(), .pressPulse(skipPressed));
ButtonConditioner b3 (.clock(CLOCK_50), .reset(resetApp), .sampleTick(msTick), .button_n(KEY[3]), .pressed(), .pressPulse(menuPressed));

F1v2       u_intro  (.clock(CLOCK_50), .address(fullRomAddr), .q(introPixel));
Instruction u_menu  (.clock(CLOCK_50), .address(fullRomAddr), .q(menuPixel));
car_crash2 u_crash  (.clock(CLOCK_50), .address(fullRomAddr), .q(crashPixel));
trophy     u_trophy (.clock(CLOCK_50), .address(fullRomAddr), .q(trophyPixel));
MaxROM     u_max    (.clock(CLOCK_50), .address(fullRomAddr), .q(maxPixel));
F1_car     u_car    (.clock(CLOCK_50), .address(carRomAddrSafe), .q(carPixel));

// Seven-segment decoders for the stopwatch-style time output.
// HEX5..HEX0 display SS : MM : 10ms
SevenSegDecoder hex0Dec (.value(hex0Value), .segments(HEX0));
SevenSegDecoder hex1Dec (.value(hex1Value), .segments(HEX1));
SevenSegDecoder hex2Dec (.value(hex2Value), .segments(HEX2));
SevenSegDecoder hex3Dec (.value(hex3Value), .segments(HEX3));
SevenSegDecoder hex4Dec (.value(hex4Value), .segments(HEX4));
SevenSegDecoder hex5Dec (.value(hex5Value), .segments(HEX5));

// LEDs provide a simple round indicator
assign LEDR =
    (gameState == ST_GAMEOVER) ? 10'b1111100000 :
    ((gameState == ST_WIN_TROPHY) || (gameState == ST_WIN_MAX)) ? 10'b1111111111 :
    roundLedMask(roundIdx);
	 
function [15:0] rgb332_to_565;
    input [7:0] c;
    begin
        rgb332_to_565 = {c[7:5], c[7:6], c[4:2], c[4:2], c[1:0], c[1:0], c[1]};
    end
endfunction

function [13:0] roundWindowMs;//create a 10 round timmer from 1500ms to 150ms
    input [3:0] r;
    begin
        case (r)
            4'd0: roundWindowMs = 14'd1500;
            4'd1: roundWindowMs = 14'd1350;
            4'd2: roundWindowMs = 14'd1200;
            4'd3: roundWindowMs = 14'd1050;
            4'd4: roundWindowMs = 14'd900;
            4'd5: roundWindowMs = 14'd750;
            4'd6: roundWindowMs = 14'd600;
            4'd7: roundWindowMs = 14'd450;
            4'd8: roundWindowMs = 14'd300;
            default: roundWindowMs = 14'd150;
        endcase
    end
endfunction

function lightPixel;
    input [7:0] px;
    input [8:0] py;
    input [7:0] left;
    input [8:0] top;
    begin
        lightPixel =
            (px >= left) && (px < left + 8'd20) &&
            (py >= top)  && (py < top + 9'd20) &&
            !((px < left + 8'd2)  && (py < top + 9'd2)) &&
            !((px > left + 8'd17) && (py < top + 9'd2)) &&
            !((px < left + 8'd2)  && (py > top + 9'd17)) &&
            !((px > left + 8'd17) && (py > top + 9'd17));
    end
endfunction

//to display the timer on the screen as well
function digitPixel;
    input [7:0] px;
    input [8:0] py;
    input [7:0] left;
    input [8:0] top;
    input [3:0] digit;
    reg   [6:0] mask;
    begin
        mask = sevenSegMask(digit);
        digitPixel =
            (mask[6] && (px >= left + 8'd4)  && (px < left + 8'd20) && (py >= top)         && (py < top + 9'd4))  ||
            (mask[5] && (px >= left + 8'd18) && (px < left + 8'd22) && (py >= top + 9'd4)  && (py < top + 9'd20)) ||
            (mask[4] && (px >= left + 8'd18) && (px < left + 8'd22) && (py >= top + 9'd22) && (py < top + 9'd38)) ||
            (mask[3] && (px >= left + 8'd4)  && (px < left + 8'd20) && (py >= top + 9'd38) && (py < top + 9'd42)) ||
            (mask[2] && (px >= left)         && (px < left + 8'd4)  && (py >= top + 9'd22) && (py < top + 9'd38)) ||
            (mask[1] && (px >= left)         && (px < left + 8'd4)  && (py >= top + 9'd4)  && (py < top + 9'd20)) ||
            (mask[0] && (px >= left + 8'd4)  && (px < left + 8'd20) && (py >= top + 9'd19) && (py < top + 9'd23));
    end
endfunction

function colonPixel;
    input [7:0] px;
    input [8:0] py;
    input [7:0] left;
    input [8:0] top;
    begin
        colonPixel =
            ((px >= left) && (px < left + 8'd4) && (py >= top + 9'd10) && (py < top + 9'd14)) ||
            ((px >= left) && (px < left + 8'd4) && (py >= top + 9'd28) && (py < top + 9'd32));
    end
endfunction


function [9:0] roundLedMask;//lights up the appropraite led for the round
    input [3:0] roundIdx;
    begin
        case (roundIdx)
            4'd0: roundLedMask = 10'b0000000001;
            4'd1: roundLedMask = 10'b0000000011;
            4'd2: roundLedMask = 10'b0000000111;
            4'd3: roundLedMask = 10'b0000001111;
            4'd4: roundLedMask = 10'b0000011111;
            4'd5: roundLedMask = 10'b0000111111;
            4'd6: roundLedMask = 10'b0001111111;
            4'd7: roundLedMask = 10'b0011111111;
            4'd8: roundLedMask = 10'b0111111111;
            default: roundLedMask = 10'b1111111111;
        endcase
    end
endfunction

function [6:0] sevenSegMask;
    input [3:0] digit;
    begin
        case (digit)
            4'd0: sevenSegMask = 7'b1111110;
            4'd1: sevenSegMask = 7'b0110000;
            4'd2: sevenSegMask = 7'b1101101;
            4'd3: sevenSegMask = 7'b1111001;
            4'd4: sevenSegMask = 7'b0110011;
            4'd5: sevenSegMask = 7'b1011011;
            4'd6: sevenSegMask = 7'b1011111;
            4'd7: sevenSegMask = 7'b1110000;
            4'd8: sevenSegMask = 7'b1111111;
            4'd9: sevenSegMask = 7'b1111011;
            default: sevenSegMask = 7'b0000001;
        endcase
    end
endfunction


always @(posedge CLOCK_50) begin// 1 ms tick generator
    if (resetApp) begin
        msDiv <= 16'd0;
        msTick    <= 1'b0;
    end else if (msDiv == 16'd49999) begin
        msDiv <= 16'd0;
        msTick    <= 1'b1;
    end else begin
        msDiv <= msDiv + 16'd1;
        msTick    <= 1'b0;
    end
end

always @(posedge CLOCK_50) begin//random sequence generator for the small pre-delay before the lights
    if (resetApp) begin
        lfsr <= 16'hACE1;
    end else begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end
end

always @(posedge CLOCK_50) begin//Main F1 game state machine
    if (resetApp) begin
        sw9Sync0 <= 1'b0; sw9Sync1 <= 1'b0; sw9Prev <= 1'b0;
    end else begin
        sw9Sync0 <= SW[9];
        sw9Sync1 <= sw9Sync0;
        sw9Prev  <= sw9Sync1;
    end
end

always @(posedge CLOCK_50) begin
    if (resetApp) begin
        gameState <= ST_INTRO;
        roundIdx <= 4'd0;
        lostRoundIdx <= 4'd0;
        stateTimerMs <= 14'd0;
		  waitCounterMs <= 14'd0;
        reactionMs <= 14'd0;
        carAnimCounterMs <= 14'd0;
        startPhase <= 4'd0;
        startPhaseTimerMs <= 9'd0;
		  winScreenTimerMs <= 11'd0;
		  lastPassClass <= PASS_NONE;
		  
        liveSecTens <= 4'd0;
        liveSecOnes <= 4'd0;
        liveMsHundreds <= 4'd0;
        liveMsTens <= 4'd0;
        liveMsOnes <= 4'd0;

        lastSecTens <= 4'd0;
        lastSecOnes <= 4'd0;
        lastMsHundreds <= 4'd0;
        lastMsTens <= 4'd0;
        lastMsOnes <= 4'd0;

        pass1Tens <= 4'd0;
        pass1Ones <= 4'd0;
        pass2Tens <= 4'd0;
        pass2Ones <= 4'd0;
    end else begin
        case (gameState)
            ST_INTRO: begin
                if (skipPressed) begin
                    gameState <= ST_IDLE;
                    stateTimerMs <= 14'd0;
                end else if (msTick) begin
                    if (stateTimerMs >= (INTRO_MS - 14'd1)) begin
                        gameState <= ST_IDLE;
                        stateTimerMs <= 14'd0;
                    end else begin
                        stateTimerMs <= stateTimerMs + 14'd1;
                    end
                end
            end

            ST_IDLE: begin
                reactionMs        <= 14'd0;
                startPhase        <= 4'd0;
                startPhaseTimerMs <= 9'd0;
                carAnimCounterMs  <= 14'd0;
                winScreenTimerMs  <= 11'd0;
                lastPassClass     <= PASS_NONE;

                if (startPressed) begin
                    waitCounterMs  <= RANDOM_WAIT_MS + {7'b0000000, lfsr[6:0]};
                    liveSecTens    <= 4'd0;
                    liveSecOnes    <= 4'd0;
                    liveMsHundreds <= 4'd0;
                    liveMsTens     <= 4'd0;
                    liveMsOnes     <= 4'd0;
                    gameState      <= ST_START_SEQ;
                end
            end

            ST_START_SEQ: begin
                if (reactPressed) begin
                    lostRoundIdx <= roundIdx;
                    gameState <= ST_GAMEOVER;
                end else if (msTick) begin
                    if (waitCounterMs > 14'd0) begin
                        waitCounterMs <= waitCounterMs - 14'd1;
                    end else if ((startPhase[0] == 1'b0) && (startPhaseTimerMs < START_LIGHT_ON_MS)) begin
                        startPhaseTimerMs <= startPhaseTimerMs + 9'd1;
                    end else if ((startPhase[0] == 1'b1) && (startPhaseTimerMs < START_LIGHT_OFF_MS)) begin
                        startPhaseTimerMs <= startPhaseTimerMs + 9'd1;
                    end else if (startPhase < (START_LIGHTS - 1'b1)) begin
                        startPhase        <= startPhase + 4'd1;
                        startPhaseTimerMs <= 9'd0;
                    end else begin
                        reactionMs     <= 14'd0;
                        liveSecTens    <= 4'd0;
                        liveSecOnes    <= 4'd0;
                        liveMsHundreds <= 4'd0;
                        liveMsTens     <= 4'd0;
                        liveMsOnes     <= 4'd0;
                        gameState      <= ST_GO;
                    end
                end
            end

            ST_GO: begin
                if (reactPressed) begin
                    lastSecTens <= liveSecTens; lastSecOnes <= liveSecOnes;
                    lastMsHundreds <= liveMsHundreds; lastMsTens <= liveMsTens; lastMsOnes <= liveMsOnes;
                    if (reactionMs <= reactionThresholdMs) begin
                        lastPassClass <= PASS_1;
                        if (pass1Ones == 4'd9) begin
                            pass1Ones <= 4'd0;
                            if (pass1Tens == 4'd9) pass1Tens <= 4'd0;
                            else pass1Tens <= pass1Tens + 4'd1;
                        end else pass1Ones <= pass1Ones + 4'd1;
                    end else begin
                        lastPassClass <= PASS_2;
                        if (pass2Ones == 4'd9) begin
                            pass2Ones <= 4'd0;
                            if (pass2Tens == 4'd9) pass2Tens <= 4'd0;
                            else pass2Tens <= pass2Tens + 4'd1;
                        end else pass2Ones <= pass2Ones + 4'd1;
                    end

                    carAnimCounterMs <= 14'd0;
                    gameState        <= ST_PASS;
                end else if (msTick) begin
                    if ((reactionMs + 14'd1) >= allowedReactionMs) begin
                        lastSecTens    <= liveSecTens;
                        lastSecOnes    <= liveSecOnes;
                        lastMsHundreds <= liveMsHundreds;
                        lastMsTens     <= liveMsTens;
                        lastMsOnes     <= liveMsOnes;
                        lostRoundIdx   <= roundIdx;
                        gameState      <= ST_GAMEOVER;
                    end else begin
                        reactionMs <= reactionMs + 14'd1;

                        if (liveMsOnes == 4'd9) begin
                            liveMsOnes <= 4'd0;
                            if (liveMsTens == 4'd9) begin
                                liveMsTens <= 4'd0;
                                if (liveMsHundreds == 4'd9) begin
                                    liveMsHundreds <= 4'd0;
                                    if (liveSecOnes == 4'd9) begin
                                        liveSecOnes <= 4'd0;
                                        if (liveSecTens == 4'd9) liveSecTens <= 4'd0;
                                        else liveSecTens <= liveSecTens + 4'd1;
                                    end else liveSecOnes <= liveSecOnes + 4'd1;
                                end else liveMsHundreds <= liveMsHundreds + 4'd1;
                            end else liveMsTens <= liveMsTens + 4'd1;
                        end else liveMsOnes <= liveMsOnes + 4'd1;
                    end
                end
            end
            ST_PASS: begin
                if (msTick) begin
                    if (carAnimCounterMs >= CAR_LOOP_MS) carAnimCounterMs <= 14'd0;
                    else carAnimCounterMs <= carAnimCounterMs + 14'd1;
                end
                if (startPressed) begin
                    if (roundIdx == 4'd9) begin
                        winScreenTimerMs <= 11'd0;
                        gameState        <= ST_WIN_TROPHY;
                    end else begin
                        roundIdx <= roundIdx + 4'd1;
                        waitCounterMs  <= RANDOM_WAIT_MS + {7'b0000000, lfsr[6:0]};
                        liveSecTens    <= 4'd0;
                        liveSecOnes    <= 4'd0;
                        liveMsHundreds <= 4'd0;
                        liveMsTens     <= 4'd0;
                        liveMsOnes     <= 4'd0;
                        startPhase     <= 4'd0;
                        startPhaseTimerMs <= 9'd0;
                        gameState      <= ST_START_SEQ;
                    end
                end
            end
            ST_GAMEOVER: begin
                if (menuPressed) begin
                    roundIdx <= lostRoundIdx;
                    waitCounterMs <= RANDOM_WAIT_MS + {7'b0000000, lfsr[6:0]};
                    startPhase <= 4'd0;
                    startPhaseTimerMs <= 9'd0;
                    gameState <= ST_START_SEQ;
                end else if (sw9Restart) begin
                    roundIdx <= 4'd0;
                    gameState <= ST_IDLE;
                end
            end

            ST_WIN_TROPHY: begin
                if (msTick) begin
                    if (winScreenTimerMs >= (WIN_TROPHY_MS - 11'd1)) gameState <= ST_WIN_MAX;
                    else winScreenTimerMs <= winScreenTimerMs + 11'd1;
                end
            end

            ST_WIN_MAX: begin
                if (startPressed) begin
                    roundIdx <= 4'd0;
                    gameState <= ST_IDLE;
                end
            end
            default: gameState <= ST_IDLE;
        endcase
    end
end

always @(posedge CLOCK_50) begin
    if (resetApp) begin
        scanX <= 0; scanY <= 0; xAddr <= 0; yAddr <= 0;
        pixelData <= 16'h0000; pixelWrite <= 1'b0;
    end else begin
        pixelWrite <= 1'b1;
        xAddr <= scanX; yAddr <= scanY;
        pixelData <= nextPixelColor;

        if (pixelReady) begin
            if (scanX == LCD_W-1) begin
                scanX <= 0;
                if (scanY == LCD_H-1) scanY <= 0;
                else scanY <= scanY + 1;
            end else scanX <= scanX + 1;
        end
    end
end

always @* begin
    reg [2:0] redOn;
    reg blankPhase;
    nextPixelColor = COL_BLACK;
    redOn = 0;
    blankPhase = 1'b0;

    if (gameState == ST_START_SEQ) begin
        case (startPhase)
            4'd0: begin redOn=1; blankPhase=0; end
            4'd1: begin redOn=1; blankPhase=1; end
            4'd2: begin redOn=2; blankPhase=0; end
            4'd3: begin redOn=2; blankPhase=1; end
            4'd4: begin redOn=3; blankPhase=0; end
            4'd5: begin redOn=3; blankPhase=1; end
            4'd6: begin redOn=4; blankPhase=0; end
            4'd7: begin redOn=4; blankPhase=1; end
            4'd8: begin redOn=5; blankPhase=0; end
            default: begin redOn=5; blankPhase=1; end
        endcase
    end

    case (gameState)
        ST_INTRO:      nextPixelColor = rgb332_to_565(introPixel);
        ST_IDLE:       nextPixelColor = rgb332_to_565(menuPixel);
        ST_GAMEOVER:   nextPixelColor = rgb332_to_565(crashPixel);
        ST_WIN_TROPHY: nextPixelColor = rgb332_to_565(trophyPixel);
        ST_WIN_MAX:    nextPixelColor = rgb332_to_565(maxPixel);
        ST_GO: begin
            nextPixelColor = COL_DKGREEN;

    if ((scanX > 8'd18) && (scanX < 8'd222) && (scanY > 9'd20) && (scanY < 9'd100))
        nextPixelColor = COL_CAR_DARK;

    if (lightPixel(scanX, scanY, 8'd32,  9'd45) ||
        lightPixel(scanX, scanY, 8'd68,  9'd45) ||
        lightPixel(scanX, scanY, 8'd104, 9'd45) ||
        lightPixel(scanX, scanY, 8'd140, 9'd45) ||
        lightPixel(scanX, scanY, 8'd176, 9'd45))
        nextPixelColor = COL_GREEN;

    if (digitPixel(scanX, scanY, 8'd18,  9'd120, liveSecTens)    ||
        digitPixel(scanX, scanY, 8'd44,  9'd120, liveSecOnes)    ||
        colonPixel(scanX, scanY, 8'd70,  9'd120)                 ||
        digitPixel(scanX, scanY, 8'd80,  9'd120, liveMsHundreds) ||
        digitPixel(scanX, scanY, 8'd106, 9'd120, liveMsTens)     ||
        colonPixel(scanX, scanY, 8'd132, 9'd120)                 ||
        digitPixel(scanX, scanY, 8'd142, 9'd120, liveMsOnes)     ||
        digitPixel(scanX, scanY, 8'd168, 9'd120, 4'd0))
        nextPixelColor = COL_WHITE;

    if ((scanX > 8'd28) && (scanX < 8'd212) && (scanY > 9'd250) && (scanY < 9'd295))
        nextPixelColor = COL_TRACK;
end

        ST_PASS: begin
            nextPixelColor = COL_GRASS;
            if ((scanX > 12) && (scanX < 228) && (scanY > 160) && (scanY < 265)) nextPixelColor = COL_TRACK;
            if (carPixelInRange) nextPixelColor = carPixel;
        end

        ST_START_SEQ: begin
            nextPixelColor = COL_BLACK;
            if (lightPixel(scanX, scanY, 8'd32,  9'd45)) nextPixelColor = (!blankPhase && redOn>=1) ? COL_RED : COL_GREY;
            if (lightPixel(scanX, scanY, 8'd68,  9'd45)) nextPixelColor = (!blankPhase && redOn>=2) ? COL_RED : COL_GREY;
            if (lightPixel(scanX, scanY, 8'd104, 9'd45)) nextPixelColor = (!blankPhase && redOn>=3) ? COL_RED : COL_GREY;
            if (lightPixel(scanX, scanY, 8'd140, 9'd45)) nextPixelColor = (!blankPhase && redOn>=4) ? COL_RED : COL_GREY;
            if (lightPixel(scanX, scanY, 8'd176, 9'd45)) nextPixelColor = (!blankPhase && redOn>=5) ? COL_RED : COL_GREY;
        end

        default: nextPixelColor = COL_BLACK;
    endcase
end


endmodule

module ButtonConditioner (
    input  clock,
    input  reset,
    input  sampleTick,
    input  button_n,
    output reg pressed,
    output reg pressPulse
);
reg buttonSync0, buttonSync1;
reg [3:0] sampleHistory;
wire buttonActive     = ~button_n;
wire buttonStableHigh = &{sampleHistory[2:0], buttonSync1};
wire buttonStableLow  = ~|{sampleHistory[2:0], buttonSync1};

always @(posedge clock) begin
    buttonSync0 <= buttonActive;
    buttonSync1 <= buttonSync0;
    if (reset) begin
        sampleHistory <= 4'b0000;
        pressed <= 1'b0;
        pressPulse <= 1'b0;
    end else begin
        pressPulse <= 1'b0;
        if (sampleTick) begin
            sampleHistory <= {sampleHistory[2:0], buttonSync1};
            if (buttonStableHigh && !pressed) begin
                pressed <= 1'b1;
                pressPulse <= 1'b1;
            end else if (buttonStableLow) begin
                pressed <= 1'b0;
            end
        end
    end
end
endmodule

module SevenSegDecoder (
    input      [3:0] value,
    output reg [6:0] segments
);
always @* begin
    case (value)
        4'h0: segments = 7'b1000000;
        4'h1: segments = 7'b1111001;
        4'h2: segments = 7'b0100100;
        4'h3: segments = 7'b0110000;
        4'h4: segments = 7'b0011001;
        4'h5: segments = 7'b0010010;
        4'h6: segments = 7'b0000010;
        4'h7: segments = 7'b1111000;
        4'h8: segments = 7'b0000000;
        4'h9: segments = 7'b0010000;
        4'hA: segments = 7'b0001000;
        4'hB: segments = 7'b0000011;
        4'hC: segments = 7'b1000110;
        4'hD: segments = 7'b0100001;
        4'hE: segments = 7'b0000110;
        default: segments = 7'b0001110;
    endcase
end
endmodule
