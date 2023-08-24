module ay_verilog_probe
(
	// Шина адреса Z80.
	input [15:0] ADR,
	// Шина данных Z80.
	inout wire [7:0] DATA,
	// Управляющие сигналы Z80.
	input IORQ,
	input WR,
	input RD,
	input CLK,
	input M1,
	output WAIT,
	
	// IORQGE
	output IORQGE,
	// OIRQ
	input OIRQ,
	// DOS Enable
	input DOSEN,
	
	// Внешнее тактирование из платы Пентагона.
	input CLK14M,
	
	// SPI2
	input SPI_SCK,
	input SPI_NSS,
	input SPI_MOSI,
	input	[1:0] SPI_A,
	
	// Управляющие сигналы звукового чипа.
	output BDIR,
	output BC1,
	output CLK1_75,
	output BEEP,
	
	// lock 128k memory 
	output LOCK128K,
	
	// FDD swap A\B drive
	output DS0_swap,
	output DS1_swap,
	input  DS_0,
	input  DS_1,
	
	
	// Дополнительные пины.
	output out_0,
	output out_1//,
	
	//output magic
);

	// SPI
	localparam SPI_ADR_CONFIG 	= 2'b00;
	localparam SPI_ADR_MOUSE 	= 2'b01;
	localparam SPI_ADR_KMPST 	= 2'b10;
	localparam SPI_ADR_KBD 		= 2'b11;
	
	
	// Config.
   localparam cpld_config_mouse 			= 0;
   localparam cpld_config_kbd 			= 1;
   localparam cpld_config_kmpstn 		= 2;
   localparam cpld_config_fdd_swap 		= 3;
   localparam cpld_config_128k_lock 	= 4;
   localparam cpld_config_psg_A15		= 5;
   localparam cpld_config_out_1 			= 6;
   localparam cpld_config_wait			= 7;
	
	reg [39:0] spi_kbd;// = 40'h0;
	wire k_clk = SPI_SCK & (~SPI_NSS) & (SPI_A == SPI_ADR_KBD);
	always @(posedge k_clk) begin	
			spi_kbd = spi_kbd << 1;
			spi_kbd[0] = ~SPI_MOSI;// <<-- инверсия!
	end
	

	reg [23:0] spi_mouse;// = 24'b1;
	wire m_clk = SPI_SCK & (~SPI_NSS) & (SPI_A == SPI_ADR_MOUSE);
	//
	always @(posedge m_clk) begin	
			spi_mouse = spi_mouse << 1;
			spi_mouse[0] = SPI_MOSI;
	end

	reg [7:0]  spi_kempston;
	wire g_clk = SPI_SCK & (~SPI_NSS) & (SPI_A == SPI_ADR_KMPST);
	always @(posedge g_clk) begin	
			spi_kempston = spi_kempston << 1;
			spi_kempston[0] = SPI_MOSI;
	end
	
	reg [7:0]  spi_config;// = 8'b11111111;
	wire c_clk = SPI_SCK & (~SPI_NSS) & (SPI_A == SPI_ADR_CONFIG);
	always @(posedge c_clk) begin	
			spi_config = spi_config << 1;
			spi_config[0] = SPI_MOSI;
	end
	
	// Wait, позволяет остановить Z80.
	assign WAIT = ( spi_config[cpld_config_wait] )? 1'b0 : 1'bz;
	//assign WAIT = 1'bz;
	
	// Блокировка расширенной памяти.
	assign LOCK128K = spi_config[cpld_config_128k_lock];
	
	// Выходы.
	//assign out_0 = spi_config[cpld_config_out_0];
	assign out_1 = spi_config[cpld_config_out_1];
	
	
	// FDD swap.
	assign DS0_swap = ( spi_config[cpld_config_fdd_swap] ) ? DS_0 : DS_1;
	assign DS1_swap = ( spi_config[cpld_config_fdd_swap] ) ? DS_1 : DS_0;
	//assign DS0_swap = ( spi_config[cpld_config_fdd_swap] ) ? ~DS_0 : ~DS_1;
	//assign DS1_swap = ( spi_config[cpld_config_fdd_swap] ) ? ~DS_1 : ~DS_0;

	assign IORQGE = IORQ | kbd;
	wire IORQ_RD = IORQ | RD ;//& SPI_NSS;

	// Кемпстон Джойстик. 8 Бит.
	wire kmpstn = ~( ADR[5] | ADR[6] | ADR[7] | OIRQ | RD ) ;//& spi_config[cpld_config_kmpstn];
	assign DATA = ( kmpstn  /*& ~SPI_NSS*/) ? spi_kempston[7:0] : 8'hZ;// <<-- TODO: CHECK SPI_NSS
	
	// Кемпстон мышка. 3*8 Бит.
	//wire mouse = ~( IORQ_RD | ADR[5] );//) & ( ADR[7:0] == 8'hDF);
	wire mouse = ~( IORQ_RD ) & ( ADR[7:0] == 8'hDF) & spi_config[cpld_config_mouse];
	wire mouse_b = mouse & ( ADR[15:8] == 8'hFA );
	wire mouse_x = mouse & ( ADR[15:8] == 8'hFB );
	wire mouse_y = mouse & ( ADR[15:8] == 8'hFF );
	assign DATA = ( mouse_b /*& ~SPI_NSS*/) ? spi_mouse[7:0] 	: 8'hZ;// <<-- TODO: CHECK SPI_NSS
	assign DATA = ( mouse_x /*& ~SPI_NSS*/) ? spi_mouse[15:8] : 8'hZ;// <<-- TODO: CHECK SPI_NSS
	assign DATA = ( mouse_y /*& ~SPI_NSS*/) ? spi_mouse[23:16]: 8'hZ;// <<-- TODO: CHECK SPI_NSS
	
	// Выходные линии массива кнопок клавиатуры.
	wire kbd_data [4:0];
	
	assign kbd_data[4] = ( ~ADR[15] & spi_kbd[39] ) | ( ~ADR[14] & spi_kbd[38] ) | ( ~ADR[13] & spi_kbd[37] ) | 
		( ~ADR[12] & spi_kbd[36] ) | ( ~ADR[11] & spi_kbd[35] ) | ( ~ADR[10] & spi_kbd[34] ) | ( ~ADR[9] & spi_kbd[33] ) | ( ~ADR[8] & spi_kbd[32] );
	assign kbd_data[3] = ( ~ADR[15] & spi_kbd[31] ) | ( ~ADR[14] & spi_kbd[30] ) | ( ~ADR[13] & spi_kbd[29] ) |
		( ~ADR[12] & spi_kbd[28] ) | ( ~ADR[11] & spi_kbd[27] ) | ( ~ADR[10] & spi_kbd[26] ) | ( ~ADR[9] & spi_kbd[25] ) | ( ~ADR[8] & spi_kbd[24] );
	assign kbd_data[2] = ( ~ADR[15] & spi_kbd[23] ) | ( ~ADR[14] & spi_kbd[22] ) | ( ~ADR[13] & spi_kbd[21] ) |
		( ~ADR[12] & spi_kbd[20] ) | ( ~ADR[11] & spi_kbd[19] ) | ( ~ADR[10] & spi_kbd[18] ) | ( ~ADR[9] & spi_kbd[17] ) | ( ~ADR[8] & spi_kbd[16] );
	assign kbd_data[1] = ( ~ADR[15] & spi_kbd[15] ) | ( ~ADR[14] & spi_kbd[14] ) | ( ~ADR[13] & spi_kbd[13] ) |
		( ~ADR[12] & spi_kbd[12] ) | ( ~ADR[11] & spi_kbd[11] ) | ( ~ADR[10] & spi_kbd[10] ) | ( ~ADR[9] & spi_kbd[9] )  | ( ~ADR[8] & spi_kbd[8] );
	assign kbd_data[0] = ( ~ADR[15] & spi_kbd[7] )  | ( ~ADR[14] & spi_kbd[6] )  | ( ~ADR[13] & spi_kbd[5] ) |
		( ~ADR[12] & spi_kbd[4] )  | ( ~ADR[11] & spi_kbd[3] )  | ( ~ADR[10] & spi_kbd[2] )  | ( ~ADR[9] & spi_kbd[1] )  | ( ~ADR[8] & spi_kbd[0] );
	
	
	wire kbd = (~( ADR[0] | IORQ_RD )) & spi_config[cpld_config_kbd] ;//& SPI_NSS; // <<-- TODO: CHECK SPI_NSS
	//wire kbd = (~( ADR[0] | IORQ ) & RD) & spi_config[cpld_config_kbd] ;//& SPI_NSS; // <<-- TODO: CHECK SPI_NSS
	
	assign DATA = ( kbd ) ?  {3'hZ, kbd_data[4], kbd_data[3], kbd_data[2], kbd_data[1], kbd_data[0]} : 8'hZ;


	
	// Деление 3.5 МГц на 2 для тактирования звукового генератора.
	always @(negedge CLK) begin
		clk_div_cnt <= ~clk_div_cnt;
	end	
	reg clk_div_cnt 	= 1'd0;
	assign CLK1_75 = clk_div_cnt;

	

	// Дешифрация звукового генератора.
	wire	ssg;
	// ADR[13] | spi_config[cpld_config_psg_A15] ->> Для совместимости с упрощенной дешифрацией.
	assign ssg = ~( (ADR[13] | spi_config[cpld_config_psg_A15]) & ADR[15] & ( ~(ADR[1] | IORQ)));
	//assign ssg = ~( ADR[13] & ADR[15] & ( ~(ADR[1] | IORQ)));
	assign BC1  = ~( ssg | ( ~(ADR[14] & M1)));
	assign BDIR = ~( ssg | WR);
	
	
	// Дешифрация бипера. Работает аналогично пентагоновской схеме.
	//localparam PORT_FE  = 8'hFE;
	reg pre_beeper;
	always @(negedge CLK) begin
		//if( (~IORQ) & (~WR) & (ADR[7:0] == PORT_FE) ) pre_beeper = DATA[4];
		if( ~(IORQ | WR | ADR[0]) ) pre_beeper = DATA[4];
 	end

	assign BEEP = pre_beeper;
	
endmodule 
