// Paul Kennedy
// 18-341
// Project 3

`default_nettype none

`define CRC5_residue 5'b01100
`define CRC16_residue 16'h800d

`define PID_ACK 8'b0100_1011
`define PID_NAK 8'b0101_1010
`define PID_OUT 8'b1000_0111
`define PID_IN 8'b1001_0110
`define PID_DATA 8'b1100_0011

module usbDevice
	#(parameter [6:0] addr = 7'h00)
  (input logic clk, rst_L,
  usbWires wires);

	logic DM, DP;
	assign DM = wires.DM;
	assign DP = wires.DP;

	logic drive_wires;
	logic DM_out, DP_out;
	assign wires.DM = (drive_wires) ? DM_out : 1'bz;
	assign wires.DP = (drive_wires) ? DP_out : 1'bz;

	logic NRZI_J, NRZI_K, SE0, SE1;
	assign NRZI_J = (DP && ~DM);
	assign NRZI_K = (DM && ~DP);
	assign SE0 = (~DM && ~DP);
	assign SE1 = (DM && DP);

	logic [7:0] PID;
	logic [15:0] Token;
	logic [63:0] Scan_Data;
	logic [63:0] Print_Data;
	logic [7:0] PID_out;

	logic [4:0] CRC5;
	logic CRC5_valid;
	logic [15:0] CRC16;
	logic CRC16_valid;

	// Output of NRZI Decoder
	logic NRZ;

	// Output of Stuffed Bit Detector
	logic isStuffed;

	// Output of SOP Detector
	logic sawSOP;

	// Output of EOP Detector
	logic sawEOP;
	logic sawNoEOP;

	// Output of PID Reader
	logic donePID;
	logic isToken;
	logic isIN;
	logic isOUT;
	logic isData;
	logic isHS;
	logic isNAK;
	logic isACK;
	logic invalidPID;

	assign isToken = isIN || isOUT;
	assign isHS = isACK || isNAK;

	// Output of Token Reader
	logic doneToken;

	// Output of Data Reader
	logic doneData;

	// Receiver FSM Outputs
	// outputs to bit-level receiver modules
	logic readPID;
	logic readToken;
	logic readData;
	logic savePID;
	logic enSBD;
	logic lookForEOP;
	// outputs to protocol FSM
	logic receivedIN;
	logic receivedOUT;
	logic receivedDATA;
	logic receivedACK;
	logic receivedNAK;
	logic dataGood;

	// Outputs of Protocol FSM
	// to sender
	logic sendData;
	logic sendNAK;
	logic sendACK;

	// Outputs of Sender FSM
	// to Protocol FSM
	logic sentPacket;
	// to bit level sender FSMs
	logic driveSOP;
	logic drivePID;
	logic driveData;
	logic driveEOP;

	// Output of bit level FSMs to NRZ encoder
	logic SOP_bit;
	logic PID_bit;
	logic Data_bit;
	logic EOP_bit;
	logic send_bit;
	assign send_bit = SOP_bit | PID_bit | Data_bit | EOP_bit;
	assign EOP_bit = driveEOP;

	// Output of bit level sender FSMs
	logic doneSOP; // Output of SOP Sender
	logic doneSPID; // Output of PID sender
	logic doneSData; // Output of Data and CRC16 sender
	logic enBS;	// enable signal for bit stuffer

	// Output of Bit stuffer to bit level sender FSMs
	logic stuffing;
	logic send_bit_stuffed;
	assign send_bit_stuffed = send_bit & ~stuffing;

	// Output of Data Reader
	logic Data_en;
	logic [6:0] Data_count;
	logic CRC_count_en;
	logic [4:0] CRC_count;
	logic Data_count_lt_64;
	logic CRC_count_lt_15;
	logic rstDataCount;
	logic rstCRC_count;
	logic en_CRC16_valid;
	logic clr_CRC16_valid;
	assign Data_count_lt_64 = (Data_count < 64);
	assign CRC_count_lt_15 = (CRC_count < 15);



	//**************************************************************
	// Beginning of Protocol FSM
	//**************************************************************

	enum {P_WAIT, P_SD, P_WHS, P_WD, P_SACK, P_SNAK} P_curr, P_next;
	assign drive_wires = (P_curr == P_SD || P_curr == P_SACK || P_curr == P_SNAK);

	logic [3:0] attemptCount;
	logic attemptCount_lt_8;
	logic attemptCount_inc;
	assign attemptCount_lt_8 = (attemptCount < 8);

	always_comb begin
		// default outputs
		sendData = 1'b0;
		sendNAK = 1'b0;
		sendACK = 1'b0;
		attemptCount_inc = 1'b0;

		case(P_curr)
			P_WAIT: begin
				P_next = (receivedIN) ? P_SD : P_WAIT;
				sendData = (receivedIN) ? 1'b1 : 1'b0;
				if(receivedOUT)
					P_next = P_WD;
			end
			P_SD: begin
				P_next = (sentPacket) ? P_WHS : P_SD;
			end
			P_WHS: begin
				if(~receivedACK && ~receivedNAK) begin
					P_next = P_WHS;
				end
				else if(receivedACK) begin
					P_next = P_WAIT;
				end
				else if(receivedNAK) begin
					P_next = P_SD;
					sendData = (attemptCount_lt_8)? 1'b1 : 1'b0;
					attemptCount_inc = 1'b1;
				end
			end
			P_WD: begin
				P_next = (receivedDATA) ? (dataGood ? P_SACK : P_SNAK) : P_WD;
				sendNAK = (receivedDATA && ~dataGood);
				sendACK = (receivedDATA && dataGood);
			end
			P_SACK: begin
				P_next = (sentPacket) ? P_WAIT : P_SACK;
			end
			P_SNAK: begin
				P_next = (sentPacket) ? P_WD : P_SACK;
			end
			default: P_next = P_WAIT;
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L) attemptCount <= 4'b0;
		else if(attemptCount_inc) attemptCount <= attemptCount + 1;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	P_curr <= P_WAIT;
		else		P_curr <= P_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	PID_out <= 8'h00;
		else if(sendACK) PID_out <= `PID_ACK;
		else if(sendNAK) PID_out <= `PID_NAK;
		else if(sendData) PID_out <= `PID_DATA;
	end

	//**************************************************************
	// End of Protocol FSM
	//**************************************************************

	//**************************************************************
	// Start of Sender FSM
	//**************************************************************

	enum {S_WAIT, S_A_SOP, S_A_PID, S_N_SOP, S_N_PID, S_D_SOP, S_D_PID, S_D_DATA, S_EOP} S_curr, S_next;

	always_comb begin
		// default outputs
		driveSOP = 1'b0;
		drivePID = 1'b0;
		driveData = 1'b0;
		driveEOP = 1'b0;

		case(S_curr)
			S_WAIT: begin
				S_next = S_WAIT;
				if(~sendData && ~sendNAK && ~sendACK)
					S_next = S_WAIT;
				else begin
					driveSOP = 1'b1;
					if(sendACK) S_next = S_A_SOP;
					else if(sendNAK) S_next = S_N_SOP;
					else if(sendData) S_next = S_D_SOP;
				end
			end
			S_A_SOP: begin
				S_next = (doneSOP) ? S_A_PID : S_A_SOP;
				drivePID = (doneSOP) ? 1'b1 : 1'b0;
			end
			S_N_SOP: begin
				S_next = (doneSOP) ? S_N_PID : S_N_SOP;
				drivePID = (doneSOP) ? 1'b1 : 1'b0;
			end
			S_A_PID: begin
				S_next = (doneSPID) ? S_EOP : S_A_PID;
				driveEOP = (doneSPID) ? 1'b1 : 1'b0;
			end
			S_N_PID: begin
				S_next = (doneSPID) ? S_EOP : S_N_PID;
				driveEOP = (doneSPID) ? 1'b1 : 1'b0;
			end
			S_D_SOP: begin
				S_next = (doneSOP) ? S_D_PID : S_D_SOP;
				drivePID = (doneSOP) ? 1'b1 : 1'b0;
			end
			S_D_PID: begin
				S_next = (doneSPID) ? S_D_DATA : S_D_PID;
				driveData = (doneSPID) ? 1'b1 : 1'b0;
			end
			S_D_DATA: begin
				S_next = (doneSData) ? S_EOP : S_D_DATA;
				driveEOP = (doneSData) ? 1'b1 : 1'b0;
			end
			S_EOP: begin
				S_next = S_WAIT;
			end

			default:
				S_next = S_WAIT;
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	S_curr <= S_WAIT;
		else		S_curr <= S_next;
	end

	//**************************************************************
	// End of Sender FSM
	//**************************************************************

	//**************************************************************
	// Start of SOP Sender
	//**************************************************************

	enum {SOP_A, SOP_B, SOP_C, SOP_D, SOP_E, SOP_F, SOP_G, SOP_H, SOP_I} SOP_curr, SOP_next;

	always_comb begin
		// default output
		SOP_bit = 1'b0;
		doneSOP = 1'b0;

		case(SOP_curr)
			SOP_A: SOP_next = (driveSOP) ? SOP_B : SOP_A;
			SOP_B: SOP_next = SOP_C;
			SOP_C: SOP_next = SOP_D;
			SOP_D: SOP_next = SOP_E;
			SOP_E: SOP_next = SOP_F;
			SOP_F: SOP_next = SOP_G;
			SOP_G: SOP_next = SOP_H;
			SOP_H: SOP_next = SOP_I;
			SOP_I: begin
				SOP_next = SOP_A;
				SOP_bit = 1'b1;
				doneSOP = 1'b1;
			end
			default: SOP_next = SOP_A; // shouldn't get here
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	SOP_curr <= SOP_A;
		else		SOP_curr <= SOP_next;
	end

	//**************************************************************
	// End of SOP Sender
	//**************************************************************

	//**************************************************************
	// Start of PID Sender
	//**************************************************************

	enum {PID_S_W, PID_S_S} PID_S_curr, PID_S_next;

	logic [3:0] PID_index;
	logic PID_index_en;
	logic PID_index_lt_8;
	logic rstPIDIndex;
	assign PID_index_lt_8 = (PID_index < 8);

	always_comb begin
		// default output
		PID_index_en = 1'b0;
		rstPIDIndex = 1'b0;
		doneSPID = 1'b0;
		PID_bit = 1'b0;

		case(PID_S_curr)
			PID_S_W: begin
				PID_S_next = (drivePID) ? PID_S_S : PID_S_W;
				PID_bit = (drivePID) ? PID_out[7-PID_index] : 1'b0;
			end
			PID_S_S: begin
				PID_S_next = (PID_index_lt_8) ? PID_S_S : PID_S_W;
				PID_index_en = (PID_index_lt_8) ? 1'b1 : 1'b0;
				rstPIDIndex = (PID_index_lt_8) ? 1'b0 : 1'b1;
				doneSPID = (PID_index_lt_8) ? 1'b0 : 1'b1;
				PID_bit = (PID_index_lt_8) ? PID_out[7-PID_index] : 1'b0;
				doneSPID = (PID_index_lt_8) ? 1'b0 : 1'b1;
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	PID_S_curr <= PID_S_W;
		else		PID_S_curr <= PID_S_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstPIDIndex)	PID_index <= 4'b0;
		else if(PID_index_en)		PID_index <= PID_index + 1;
	end

	//**************************************************************
	// End of PID Sender
	//**************************************************************

	//**************************************************************
	// Start of Data Sender
	//**************************************************************

	logic CRC_count_en_S;
	logic rstCRC_count_S;
	logic en_CRC16_valid_S;
	logic clr_CRC16_valid_S;

	enum {D_S_W, D_S_S, D_S_CRC} D_S_curr, D_S_next;

	logic [4:0] CRC_send_count;
	logic [7:0] Data_index;
	logic Data_index_en;
	logic Data_index_lt_64;
	logic rstDataIndex;
	assign Data_index_lt_64 = (Data_index < 64);
	logic CRC_send_count_lt_15;
	assign CRC_send_count_lt_15 = (CRC_send_count < 15);
	logic CRC_send_count_en;

	always_comb begin
		// default output
		Data_index_en = 1'b0; 
		rstDataIndex = 1'b0;
		doneSData = 1'b0;
		Data_bit = 1'b0;
		enBS = 1'b0;
		CRC_count_en_S = 1'b0;
		en_CRC16_valid_S = 1'b0;
		clr_CRC16_valid_S = 1'b0;
		rstCRC_count_S = 1'b0;
		CRC_send_count_en = 1'b0;


		case(D_S_curr)
			D_S_W: begin
				D_S_next = (driveData) ? D_S_S : D_S_W;
				Data_bit = (driveData) ? Scan_Data[Data_index] : 1'b0;
				enBS = (driveData) ? 1'b1 : 1'b0;
				Data_index_en = (driveData) ? 1'b1 : 1'b0;
			end
			D_S_S: begin
				D_S_next = (Data_index_lt_64) ? D_S_S : D_S_CRC;
				Data_index_en = (Data_index_lt_64 && ~stuffing) ? 1'b1 : 1'b0;
				rstDataIndex = (Data_index_lt_64) ? 1'b0 : 1'b1;
				Data_bit = (Data_index_lt_64) ? Scan_Data[Data_index] : ~CRC16[15];
				enBS = (Data_index_lt_64) ? 1'b1 : 1'b0;
				clr_CRC16_valid_S = (Data_index_lt_64) ? 1'b1 : 1'b0;
			end
			D_S_CRC: begin
				Data_bit = (CRC_send_count_lt_15) ? ~CRC16[14-CRC_send_count] : 1'b0;
				enBS = (CRC_send_count_lt_15) ? 1'b1 : 1'b0;
				D_S_next = (CRC_send_count_lt_15) ? D_S_CRC : D_S_W;
				en_CRC16_valid_S = (CRC16 == `CRC16_residue) ? 1'b1 : 1'b0;
				clr_CRC16_valid_S = (~CRC16 != `CRC16_residue) ? 1'b1 : 1'b0;
				doneSData = (CRC_send_count_lt_15) ? 1'b0 : 1'b1;
				CRC_send_count_en = 1'b1;
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L) CRC_send_count <=  4'b0;
		else if(CRC_send_count_en) CRC_send_count <= CRC_send_count +1;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	D_S_curr <= D_S_W;
		else		D_S_curr <= D_S_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstDataIndex)	Data_index <= 7'b0;
		else if(Data_index_en)		Data_index <= Data_index + 1;
	end

	//**************************************************************
	// End of Data Sender
	//**************************************************************

	//**************************************************************
	// Start of Bit Stuffer
	//**************************************************************

	logic [3:0] onesOutCount;
	logic onesOutCount_gte_6;

	assign onesOutCount_gte_6 = (onesOutCount >= 6);
	assign stuffing = onesOutCount_gte_6;

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || ~enBS || ~send_bit || onesOutCount_gte_6) onesOutCount <= 4'b0;
		else onesOutCount <= onesOutCount+1;
	end

	//**************************************************************
	// End of Bit Stuffer
	//**************************************************************

	//**************************************************************
	// Beginning of NRZI Encoder
	//**************************************************************

	enum {NRZ_prevK, NRZ_prevJ, NRZ_EOP1, NRZ_EOP2} NRZ_curr, NRZ_next;

	always_comb begin
		DM_out = 1'b0;
		DP_out = 1'b0;
		sentPacket = 1'b0;

		case(NRZ_curr)
			NRZ_prevK: begin
				NRZ_next = (send_bit_stuffed) ? NRZ_prevK : NRZ_prevJ;
				{DP_out, DM_out} = (send_bit_stuffed) ? {1'b0,1'b1} : {1'b1,1'b0} ;
			end
			NRZ_prevJ: begin
				NRZ_next = (send_bit_stuffed) ? NRZ_prevJ : NRZ_prevK;
				{DP_out, DM_out} = (send_bit_stuffed) ? {1'b1,1'b0} : {1'b0,1'b1};
			end
			NRZ_EOP1: begin
				NRZ_next = NRZ_EOP2;
				{DP_out, DM_out} = {1'b0, 1'b0}; // send X
			end
			NRZ_EOP2: begin
				NRZ_next = NRZ_prevJ;
				{DP_out, DM_out} = {1'b1, 1'b0}; // send J
				sentPacket = 1'b1;
			end

		endcase

		if(driveEOP) begin
			NRZ_next = NRZ_EOP1;
			{DP_out, DM_out} = {1'b0, 1'b0}; // send X
		end

		if(driveSOP) begin
			NRZ_next = NRZ_prevJ;
			{DP_out, DM_out} = {1'b0, 1'b0};
		end
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	NRZ_curr <= NRZ_prevJ; // assume idle start
		else		NRZ_curr <= NRZ_next;
	end


	//**************************************************************
	// End of NRZ Encoder
	//**************************************************************

	//**************************************************************
	// Beginning of NRZI Decoder
	//**************************************************************

	enum {NRZI_prevK, NRZI_prevJ} NRZI_curr, NRZI_next;

	always_comb begin
		//default outputs
		NRZ = 0;
		NRZI_next = (NRZI_J) ? NRZI_prevJ : NRZI_prevK;

		case(NRZI_curr)
			NRZI_prevK: NRZ = (NRZI_J) ? 0 : 1;
			NRZI_prevJ: NRZ = (NRZI_J) ? 1 : 0;
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	NRZI_curr <= NRZI_prevJ; // assume idle start
		else		NRZI_curr <= NRZI_next;
	end

	//**************************************************************
	// Ending of NRZI Decoder
	//**************************************************************

	//**************************************************************
	// Beginning of Stuffed Bit Detector
	//**************************************************************

	logic [3:0] onesCount;
	logic onesCount_gte_6;

	assign onesCount_gte_6 = (onesCount >= 6);
	assign isStuffed = onesCount_gte_6;

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || ~enSBD || ~NRZ || onesCount_gte_6) onesCount <= 4'b0;
		else onesCount <= onesCount+1;
	end

	//**************************************************************
	// Ending of Stuffed Bit Detector
	//**************************************************************

	//**************************************************************
	// Beginning of SOP Detector
	//**************************************************************

	enum {LFS_A, LFS_B, LFS_C, LFS_D, LFS_E, LFS_F, LFS_G, LFS_H, LFS_error} LFS_curr, LFS_next;

	always_comb begin
		// default output
		sawSOP = 0;

		case(LFS_curr)
			LFS_A:	LFS_next = (NRZI_K)? LFS_B : LFS_A;
			LFS_B:	LFS_next = (NRZI_J)? LFS_C : LFS_B;
			LFS_C:	LFS_next = (NRZI_K)? LFS_D : LFS_A;
			LFS_D:	LFS_next = (NRZI_J)? LFS_E : LFS_A;
			LFS_E:	LFS_next = (NRZI_K)? LFS_F : LFS_A;
			LFS_F:	LFS_next = (NRZI_J)? LFS_G : LFS_A;
			LFS_G:	LFS_next = (NRZI_K)? LFS_H : LFS_A;
			LFS_H: begin
				LFS_next = (NRZI_K)? LFS_A : LFS_G;
				sawSOP = (NRZI_K)? 1'b1 : 1'b0;
			end
			default: LFS_next = LFS_error; // shouldn't get here
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	LFS_curr <= LFS_A;
		else		LFS_curr <= LFS_next;
	end
	//**************************************************************
	// Ending of SOP Detector
	//**************************************************************

	//**************************************************************
	// Beginning of EOP Detector
	//**************************************************************
	enum {LFE_A, LFE_B, LFE_C, LFE_D} LFE_curr, LFE_next;

	always_comb begin
		// default output
		sawEOP = 1'b0;
		sawNoEOP = 1'b0;

		case(LFE_curr)
			LFE_A: begin
				LFE_next = (lookForEOP && SE0) ? LFE_B : LFE_A;
				sawNoEOP = (lookForEOP && ~SE0);
			end
			LFE_B: begin
				LFE_next = (SE0)? LFE_C : LFE_A;
				sawNoEOP = ~SE0;
			end
			LFE_C: begin
				LFE_next = LFE_A;
				sawNoEOP = (NRZI_J)? 1'b0 : 1'b1;
				sawEOP = (NRZI_J)? 1'b1: 1'b0;
			end
			default: LFE_next = LFE_A;
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	LFE_curr <= LFE_A;
		else		LFE_curr <= LFE_next;
	end

	//**************************************************************
	// Ending of EOP Detector
	//**************************************************************


	//**************************************************************
	// Beginning of Receiver FSM
	//**************************************************************

	logic [7:0] savedPID;

	enum {R_WSOP, R_WPID, R_WTOK, R_WDATA, R_WEOP} R_curr, R_next;

	always_comb begin
		// default outputs
		// outputs to PID reader, Token Reader, and Data Reader,
		// EOP Detector, and Stuffed Bit Detector FSMs
		readPID = 1'b0;
		readToken = 1'b0;
		readData = 1'b0;
		savePID = 1'b0;
		lookForEOP = 1'b0;
		enSBD = 1'b1;

		// Outputs to Protocol FSM
		receivedIN = 1'b0;
		receivedOUT = 1'b0;
		receivedDATA = 1'b0;
		receivedACK = 1'b0;
		receivedNAK = 1'b0;
		dataGood = 1'b0;

		case(R_curr)
			R_WSOP: begin
				R_next = (sawSOP) ? R_WPID : R_WSOP;
				readPID = (sawSOP) ? 1'b1 : 1'b0;
				enSBD = 1'b0;
			end
			R_WPID: begin
				enSBD = (isToken || isData) ? 1'b1 : 1'b0;
				savePID = 1'b1;
				if(isToken) begin
					R_next = R_WTOK;
					readToken = 1'b1;
				end
				else if(isData) begin
					R_next = R_WDATA;
					readData = 1'b1;
				end
				else if(isHS) begin
					R_next = R_WEOP;
					lookForEOP = 1'b1;
				end
				else if(invalidPID) begin
					R_next = R_WSOP;
				end
				else
					R_next = R_WPID;
			end
			R_WTOK: begin
				R_next = (doneToken) ? R_WEOP : R_WTOK;
				lookForEOP = (doneToken) ? 1'b1 : 1'b0;
			end
			R_WDATA: begin
				R_next = (doneData) ? R_WEOP : R_WDATA;
				lookForEOP = (doneData) ? 1'b1 : 1'b0;
			end
			R_WEOP: begin
				enSBD = 1'b0;
				R_next = (~sawEOP && ~sawNoEOP) ? R_WEOP : R_WSOP;
				if(sawEOP) begin
					if(savedPID == `PID_OUT && Token[6:0] == addr && Token[9:7] == 4'h3 && CRC5_valid) receivedOUT = 1'b1;
					else if(savedPID == `PID_IN && Token[6:0] == addr && CRC5_valid) receivedIN = 1'b1;
					else if(savedPID == `PID_DATA) begin 
						receivedDATA = 1'b1;
						if(CRC16_valid)
							dataGood = 1'b1;
					end
					else if(savedPID == `PID_ACK) receivedACK = 1'b1;
					else if(savedPID == `PID_NAK) receivedNAK = 1'b1;
				end
				if(sawNoEOP)
					;
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	R_curr <= R_WSOP;
		else		R_curr <= R_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	savedPID <= 8'b0;
		else		savedPID <= PID;
	end

	//**************************************************************
	// End of Receiver FSM
	//**************************************************************

	//**************************************************************
	// Start of PID Reader
	//**************************************************************

	enum {PID_W, PID_S} PID_curr, PID_next;

	logic PID_en;
	logic [3:0] PID_count;
	logic PID_count_lt_8;
	logic rstPIDCount;
	assign PID_count_lt_8 = (PID_count < 8);

	always_comb begin
		// default output
		PID_en = 1'b0;
		rstPIDCount = 1'b0;
		donePID = 1'b0;

		isOUT = 1'b0;
		isIN = 1'b0;
		isData = 1'b0;
		isACK = 1'b0;
		isNAK = 1'b0;
		invalidPID = 1'b0;

		case(PID_curr)
			PID_W: begin
				PID_next = (readPID) ? PID_S : PID_W;
			end
			PID_S: begin
				PID_next = (PID_count_lt_8) ? PID_S : PID_W;
				PID_en = (PID_count_lt_8) ? 1'b1 : 1'b0;
				rstPIDCount = (PID_count_lt_8) ? 1'b0 : 1'b1;
				donePID = (PID_count_lt_8) ? 1'b0 : 1'b1;

				if(~PID_count_lt_8) begin
					if(PID == 8'b1000_0111) isOUT = 1'b1;
					else if(PID == `PID_IN) isIN = 1'b1;
					else if(PID == `PID_DATA) isData = 1'b1;
					else if(PID == `PID_ACK) isACK = 1'b1;
					else if(PID == `PID_NAK) isNAK = 1'b1;
					else	invalidPID = 1'b1;
				end
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	PID_curr <= PID_W;
		else		PID_curr <= PID_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)
			PID <= 8'b0;
		else if(PID_en) begin
			PID[7:1] <= PID[6:0];
			PID[0] <= NRZ;
		end
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstPIDCount)	PID_count <= 4'b0;
		else if(PID_en)			PID_count <= PID_count + 1;
	end

	//**************************************************************
	// End of PID Reader
	//**************************************************************

	//**************************************************************
	// Start of Token Reader
	//**************************************************************

	enum {T_W, T_S} Token_curr, Token_next;

	logic Token_en;
	logic [4:0] Token_count;
	logic Token_count_lt_16;
	logic rstTokenCount;
	logic en_CRC5_valid;
	logic clr_CRC5_valid;
	assign Token_count_lt_16 = (Token_count < 16);

	always_comb begin
		// default output
		Token_en = 1'b0;
		rstTokenCount = 1'b0;
		doneToken = 1'b0;
		en_CRC5_valid = 1'b0;
		clr_CRC5_valid = 1'b0;

		case(Token_curr)
			T_W: begin
				Token_next = (readToken) ? T_S : T_W;
				clr_CRC5_valid = (readToken) ? 1'b1 : 1'b0;
				Token_en = (readToken) ? 1'b1 : 1'b0;
			end
			T_S: begin
				Token_next = (Token_count_lt_16) ? T_S : T_W;
				Token_en = (Token_count_lt_16) ? 1'b1 : 1'b0;
				rstTokenCount = (Token_count_lt_16) ? 1'b0 : 1'b1;
				doneToken = (Token_count_lt_16) ? 1'b0 : 1'b1;
				en_CRC5_valid = (CRC5 == `CRC5_residue) ? 1'b1 : 1'b0;
				clr_CRC5_valid = (CRC5 != `CRC5_residue) ? 1'b1 : 1'b0;
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	Token_curr <= T_W;
		else		Token_curr <= Token_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)
			Token <= 16'b0;
		else if(Token_en) begin
			Token[14:0] <= Token[15:1];
			Token[15] <= NRZ;
		end
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstTokenCount)	Token_count <= 4'b0;
		else if(Token_en)		Token_count <= Token_count + 1;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || clr_CRC5_valid)	CRC5_valid <= 1'b0;
		else if(en_CRC5_valid)		CRC5_valid <= 1'b1;
	end

	//**************************************************************
	// End of Token Reader
	//**************************************************************


	//**************************************************************
	// Start of Data Reader
	//**************************************************************

	enum {D_W, D_S, D_CRC} Data_curr, Data_next;


	always_comb begin
		// default output
		Data_en = 1'b0;
		rstDataCount = 1'b0;
		doneData = 1'b0;
		CRC_count_en = 1'b0;
		en_CRC16_valid = 1'b0;
		clr_CRC16_valid = 1'b0;
		rstCRC_count = 1'b0;

		case(Data_curr)
			D_W: begin
				Data_next = (readData) ? D_S : D_W;
				Data_en = (readData) ? 1'b1 : 1'b0;
			end
			D_S: begin
				Data_next = (Data_count_lt_64) ? D_S : D_CRC;
				Data_en = (Data_count_lt_64 && ~isStuffed) ? 1'b1 : 1'b0;
				rstDataCount = (Data_count_lt_64) ? 1'b0 : 1'b1;
				clr_CRC16_valid = (Data_count_lt_64) ? 1'b0 : 1'b1;
			end
			D_CRC: begin
				Data_next = (CRC_count_lt_15) ? D_CRC : D_W;
				CRC_count_en = 1'b1;
				rstCRC_count = (CRC_count_lt_15) ? 1'b0 : 1'b1;
				doneData = (CRC_count_lt_15) ? 1'b0 : 1'b1;
				en_CRC16_valid = (CRC16 == `CRC16_residue) ? 1'b1 : 1'b0;
				clr_CRC16_valid = (CRC16 != `CRC16_residue) ? 1'b1 : 1'b0;
			end
		endcase
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)	Data_curr <= D_W;
		else		Data_curr <= Data_next;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L)
			Print_Data <= 64'b0;
		else if(Data_en) begin
			Print_Data[62:0] <= Print_Data[63:1];
			Print_Data[63] <= NRZ;
		end
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstCRC_count || rstCRC_count_S)	CRC_count <= 5'b0;
		else if(CRC_count_en || CRC_count_en_S)		CRC_count <= CRC_count + 1;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || rstDataCount)	Data_count <= 7'b0;
		else if(Data_en)		Data_count <= Data_count + 1;
	end

	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || clr_CRC16_valid || clr_CRC16_valid_S)	CRC16_valid <= 1'b0;
		else if(en_CRC16_valid || en_CRC16_valid_S)		CRC16_valid <= 1'b1;
	end


	//**************************************************************
	// End of Data Reader
	//**************************************************************

	//***************************************
	// Start of CRC 5
	//***************************************
	
	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || sawSOP)
			CRC5 = 5'b11111;
		else if((readToken || R_curr == R_WTOK) && ~isStuffed) begin
			CRC5[0] <= CRC5[4] ^ NRZ;
			CRC5[1] <= CRC5[0];
			CRC5[2] <= CRC5[1] ^ (CRC5[4] ^ NRZ);
			CRC5[3] <= CRC5[2];
			CRC5[4] <= CRC5[3];
		end
	end

	//***************************************
	// End of CRC 5
	//***************************************

	//***************************************
	// Start of CRC 16
	//***************************************
	
	always_ff @(posedge clk, negedge rst_L) begin
		if(~rst_L || (sawSOP && R_curr == R_WSOP))
			CRC16 = 16'hffff;
		else if((((readData || R_curr == R_WDATA) && ~isStuffed) || ((driveData || D_S_curr == D_S_S) && ~stuffing)) && Data_index_lt_64 && D_S_curr != D_S_CRC) begin
			CRC16[0] <= CRC16[15] ^ NRZ;
			CRC16[1] <= CRC16[0];
			CRC16[2] <= CRC16[1] ^ (CRC16[15] ^ NRZ);
			CRC16[3] <= CRC16[2];
			CRC16[4] <= CRC16[3];
			CRC16[5] <= CRC16[4];
			CRC16[6] <= CRC16[5];
			CRC16[7] <= CRC16[6];
			CRC16[8] <= CRC16[7];
			CRC16[9] <= CRC16[8];
			CRC16[10] <= CRC16[9];
			CRC16[11] <= CRC16[10];
			CRC16[12] <= CRC16[11];
			CRC16[13] <= CRC16[12];
			CRC16[14] <= CRC16[13];
			CRC16[15] <= CRC16[14] ^ (CRC16[15] ^ NRZ);
		end
	end

	//***************************************
	// End of CRC 16
	//***************************************



  /*  Don't modify the headers!
   *
   *  scan  - simply set internal memory to scannedMsg
   *        - a display would be nice too...
   */
  task scan
  (input logic [63:0]  scannedMsg);
  
    //put some code here
    $display("scanning...");
    Scan_Data = scannedMsg;
    $display("The Scanned Data is: %h", scannedMsg);
  
  endtask
  
  
  /*
   *  print - simply set printMsg to current internal memory
   *        - a display would be nice too...
   */
  task print
  (output  logic [63:0]  printMsg);
    
    //you may want to change this line...
    printMsg = Print_Data;

    $display("printing...");
    $display("The Data is: %h",Print_Data);
  
  endtask


endmodule
