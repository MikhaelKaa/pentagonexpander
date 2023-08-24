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
	
	// Отладочные пины.
	input button_3,
	input button_4,
	
	output led,
	output DBG_PIN
);
	

	reg kb_read;
	always @(negedge CLK14M) begin
			kb_read =  ~(ADR[0] | IORQ | RD ) & (spi_config[7] == 1);
	end
		
	assign DBG_PIN =  spi_kbd[39];

	// SPI
	localparam SPI_CONFIG = 2'b00;
	localparam SPI_MOUSE = 2'b01;
	localparam SPI_KMPST = 2'b10;
	localparam SPI_KBD = 2'b11;
	
	reg[39:0] spi_kbd;
	reg [23:0] spi_mouse;
	reg [7:0] spi_config;
	
	always @(posedge SPI_SCK) begin
		if( (~SPI_NSS)  ) begin
			if( SPI_A == SPI_MOUSE ) begin
				spi_mouse = spi_mouse << 1;
				spi_mouse[0] = SPI_MOSI;
			end
			
			if( SPI_A == SPI_CONFIG ) begin
				spi_config = spi_config << 1;
				spi_config[0] = SPI_MOSI;
			end
			
			if( SPI_A == SPI_KBD ) begin
				spi_kbd = spi_kbd << 1;
				spi_kbd[0] = SPI_MOSI;
			end
		end
	end


	// IORQGE
	assign IORQGE = IORQ | kb_read;
	
	// Дешифрация Kempston Mouse
	localparam PORT_FADF = 16'hFADF; // 64223 #FADF 1111 1010 1101 1111 - Kempston mouse, состояние кнопок 
	localparam PORT_FBDF = 16'hFBDF; // 64479 #FBDF 1111 1011 1101 1111 - Kempston mouse, X-координата
	localparam PORT_FFDF = 16'hFFDF; // 65503 #FFDF 1111 1111 1101 1111 - Kempston mouse, Y-координата

	reg reg_kemston_mouse_b;
	reg reg_kemston_mouse_x;
	reg reg_kemston_mouse_y;
	
	always @(negedge CLK14M)
		begin
			if( (~IORQ) & (~RD) & (ADR[15:0] == PORT_FADF) ) reg_kemston_mouse_b = 1'b1;
			else reg_kemston_mouse_b = 1'b0;	

			if( (~IORQ) & (~RD) & (ADR[15:0] == PORT_FBDF) ) reg_kemston_mouse_x = 1'b1;
			else reg_kemston_mouse_x = 1'b0;

			if( (~IORQ) & (~RD) & (ADR[15:0] == PORT_FFDF) ) reg_kemston_mouse_y = 1'b1;
			else reg_kemston_mouse_y = 1'b0;
		end
		
	//assign DBG_PIN = reg_kemston_mouse_b | reg_kemston_mouse_x | reg_kemston_mouse_y;
	assign DATA = (reg_kemston_mouse_b ) ? spi_mouse[7:0] : 8'hZ;
	assign DATA = (reg_kemston_mouse_x ) ? spi_mouse[15:8] : 8'hZ;
	assign DATA = (reg_kemston_mouse_y ) ? spi_mouse[23:16]: 8'hZ;
	
	// Деление 14 МГц на 8 для тактирования звукового генератора.
	reg [2:0] clk_div_cnt 	= 3'd0;
	always @(negedge CLK14M)	
		clk_div_cnt <= clk_div_cnt + 3'd1;
	assign CLK1_75 = clk_div_cnt[2];

	// Кнопка активации выходов, для отладки.
	reg enable_out 	= 0;
	always @(negedge button_3)
		enable_out <= !enable_out;
		
	assign led = enable_out;
	
	// Wait, позволяет остановить Z80.
	assign WAIT = 1'bz;
	
	
	// Дешифрация звукового генератора.
	/*localparam PORT_FD = 8'hFD;
	reg pre_bc1, pre_bdir;
	
	always @(negedge CLK14M)
	begin
		pre_bc1 	= 1'b0;
		pre_bdir = 1'b0;
		if( ADR[7:0] == PORT_FD )
		begin
			if( ADR[15:14] == 2'b11 )
			begin
				pre_bc1 	= 1'b1;
				pre_bdir	= 1'b1;
			end
			else if( ADR[15:14]==2'b10 )
			begin
				pre_bc1 	= 1'b0;
				pre_bdir	= 1'b1;
			end
		end
	end
	assign BC1  = pre_bc1 & M1 & (~IORQ) & ((~RD) | (~WR));
	assign BDIR = pre_bdir & M1 & (~IORQ) & (~WR);*/
	
	assign BC1  = ~((~(ADR[13] & ADR[15] & (~(ADR[1] | IORQ)))) | (~(ADR[14] & M1)));
	assign BDIR = ~((~(ADR[13] & ADR[15] & (~(ADR[1] | IORQ)))) | WR);
	
	// Дешифрация бипера.
	localparam PORT_FE  = 8'hFE;
	reg pre_beeper;
	always @(negedge CLK14M)
		begin
			if( (~IORQ) & (~WR) & (ADR[7:0] == PORT_FE) ) pre_beeper = DATA[4];
		end
	assign BEEP = pre_beeper;
	
	
	// 7FFD На чтение. В test4.30 пишет порт на чтение недоступен, но из бейсиков вроде норм. Надо проверять.
	localparam PORT_7FFD = 16'h7FFD;
	reg reg_7ffd_read;
	reg [7:0]reg_7ffd;

	always @(negedge CLK14M)
		begin
			// Z80 читает 7FFD
			if( (ADR[15:0] == PORT_7FFD) & (~RD) & (~IORQ) ) reg_7ffd_read = 1'b1; // ({ADR[15],ADR[1]} == 2'b00)
			else reg_7ffd_read = 1'b0;
			
			// Z80 пишет 7FFD
			if( (ADR[15:0] == PORT_7FFD) & (~WR) & (~IORQ) ) reg_7ffd <= DATA;	// (ADR[15:0] == PORT_7FFD)

		end
	assign DATA = (reg_7ffd_read) ? reg_7ffd : 8'hZ;
	
	
endmodule 


/*
  always @(negedge CLK14M)
  begin
    pre_bc1   = 1'b0;
    pre_bdir = 1'b0;
Внутри клокового always всегда надо писать <= для тех имен, котоыре настоящие регистры (а не временные переменные)
*/

/*
module ap6 (da, db, oe_n, dir);
	inout [7:0] da;
	inout [7:0] db;
	input oe_n;
	input dir;

	assign db = (dir & !oe_n) ? da : 8'hzz;
	assign da = (!dir & !oe_n) ? db : 8'hzz;
endmodule
*/

/*
http://zxdn.narod.ru/coding/zg45pent.txt
Из журнала ZX-Guide#4.5, Рязань, 08.2002

U#74
05.06.02
Samara-City
 
          Удобству отлавливания глюков дешифрации посвящается...
 
* и красным цветом помечены биты(адреса),
по которым производится дешифрация портов в Пне-128(512,1024)
 
  ДЕШИФРАЦИЯ И РАСКЛАДКА ПОРТОВ  ZX-SPECTRUM ( по Пентагону )
 =============================================================
 
                      ПОРТЫ КОНФИГУРАЦИИ.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
1FFD  0   0   0   1   1   1  1  1  1  1  1  1  1  1  0  1  SCORP
7FFD  0*  1   1   1   1   1  1  1  1  1  1  1  1  1  0* 1  Пень
DFFD  1*  1*  0*  1   1   1  1  1  1  1  1  1  1  1  0* 1  Профи
FDDF  1   1   1   1   1   1  0  1  1  1  1  1  1  1  0  1  ATM
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                    МУЗЫКАЛЬНЫЙ СОПРОЦЕССОР.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
BFFD  1*  0*  1*  1   1   1  1  1  1  1  1  1  1  1  0* 1  WRITE
FFFD  1   1   1   1   1   1  1  1  1  1  1  1  1  1  0  1  READ
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                    CMOS-ЧАСЫ (по GLUK'у).
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
BFF7  1   0   1   1   1   1  1  1  1  1  1  1  0  1  1  1 R/W D
DFF7  1   1   0   1   1   1  1  1  1  1  1  1  0  1  1  1 ADR.WR
EFF7  1*  1*  1*  0*  1   1  1  1  1  1  1  1  0* 1  1  1 Enable
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                КОНТРОЛЛЕР КЭША 32/128Kb (ЧeВo#7).
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
F3F7  1   1   1   1   0*  0* 1  1  1  1  1  1  0* 1  1  1 PAGE
FBF7  1   1   1   1   1   0  1  1  1  1  1  1  0  1  1  1 Enable
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                        KEMPSTON MOUSE.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
FADF  1   1   1   1   1   0* 1  0* 1* 1  0* 1  1  1  1  1 Button
FBDF  1   1   1   1   1   0  1  1  1  1  0  1  1  1  1  1 Xкоорд
FFDF  1   1   1   1   1   1  1  1  1  1  0  1  1  1  1  1 Yкоорд
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                        СИСТЕМНЫЕ ПОРТЫ.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
xxFB  x   x   x   x   x   x  x  x  1  1  1  1  1  0* 1  1  ZXLpr
xxFE  x   x   x   x   x   x  x  x  1  1  1  1  1  1  1  0* !!!!
xxFF  x   x   x   x   x   x  x  x  1  1  1  1  1  1  1  1  Attr
xx1F  x   x   x   x   x   x  x  x  0  0  0* 1  1  1  1  1  K.Joy (oirq, not iorq)
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                     ПОРТЫ КОНТРОЛЛЕРА FDD.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
001F  0   0   0   0   0   0  0  0  0* 0* 0* 1* 1  1  1* 1* Comm.
003F  0   0   0   0   0   0  0  0  0  0  1  1  1  1  1  1  Track
005F  0   0   0   0   0   0  0  0  0  1  0  1  1  1  1  1  Sect.
007F  0   0   0   0   0   0  0  0  0  1  1  1  1  1  1  1  DATA
00FF  0   0   0   0   0   0  0  0  1  1  1  1  1  1  1  1  Syst.
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
 
                 COVOX'ы (SOUNDRIVE1.51+ etc.).
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0 NOTE
xx0F  x   x   x   x   x   x  x  x  0  0* 0* 0* 1  1  1  1 Chan.A
xx1F  x   x   x   x   x   x  x  x  0  0  0  1  1  1  1  1 Chan.B
xx4F  x   x   x   x   x   x  x  x  0  1  0  0  1  1  1  1 Chan.C
xx5F  x   x   x   x   x   x  x  x  0  1  0  1  1  1  1  1 Chan.D
xxDD  x   x   x   x   x   x  x  x  1  1  0  1  1  1  0  1 Profi
xxFB  x   x   x   x   x   x  x  x  1  1  1  1  1* 0* 1* 1 Пень
PORT A15 A14 A13 A12 A11 A1O A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
             Девиз:Дополни и передай другому!!!!!

*/


/*
#FADF - Kempston mouse, состояние кнопок
#FBDF - Kempston mouse, X-координата
#FFDF - Kempston mouse, Y-координата
*/

/*
Порт 1F
Порт #1F (31) — стандартный порт для Kempston-джойстика.

Декодирование
Декодирование адреса порта в оригинальном устройстве выполнялось только по сброшенному A5.

Назначение битов
Опрос Kempston joystick выполняется чтением порта #1F. 
Отдельные биты прочитанного байта возвращают состояние кнопок джойстика (D0=вправо, D1=влево, D2=вниз, D3=вверх, D4=огонь). 
Установленный бит соответствует нажатой кнопке. Джойстик присутствует, если значение, считанное из порта #1F при отпущенных кнопках, равно 0. 
Опрос Kempston джойстика при его отсутствии - одна из самых частых причин неработоспособности программ.
*/

/*
#FE - клавиатура, цвет бордюра, бипер, магнитофон
Порт #FE (254) - стандартный порт ZX Spectrum, предназначен для работы с внутренними и внешними устройствами.

Декодирование
В оригинальном ZX Spectrum декодирование адресов портов максимально упрощено - определение обращения к порту клавиатуры происходит по сброшенному A0.
Поэтому обращение по любому чётному адресу приведёт к обращению к порту #FE.
Однако, во избежание конфликтов с портами периферийных устройств требуется использовать именно указанный адрес.
В компьютере Timex Sinclair 2068 декодирование адреса порта клавитуры выполняется полностью.

Назначение битов при чтении из порта
D0-D4 - отображают состояние определённого полуряда клавиатуры ZX Spectrum.
Порты полурядов - #7FFE, #BFFE, #DFFE, #EFFE, #F7FE, #FBFE, #FDFE и #FEFE.
Возможно одновременное чтение нескольких полурядов при сбросе нескольких бит в старшем байте адреса порта.
В контроллере клавиатуры компьютера ATM Turbo некоторые комбинации старших адресов заняты другими функциями.
D6 - отображает состояние магнитофонного входа (EAR).
D5, D7 - обычно не используются. В некоторых клонах ZX Spectrum эти биты используются для чтения сигналов последовательного и параллельного интерфейса.
В компьютерах Спарк и Аллофон эти биты отображают состояние дополнительных клавиш.

Назначение битов при записи в порт
D0-D2 - определяют цвет бордюра.
D3 - управляет состоянием выхода записи на магнитофон MIC.
D4 - управляет внутренним динамиком (бипером).
D5-D7 - обычно не используются.
Особенности оригинального ZX Spectrum
В оригинальных ZX Spectrum производства Sinclair Research с ULA первой версии установка бита D4 также блокирует прохождение сигнала магнитофона с входа EAR.
Для последующих версий ULA устанавливает повышенную чувствительность магнитофонного входа EAR.

D3 также влияет на уровень напряжения на выходе внутреннего ЦАПа ULA, подаваемого на внутренний динамик, но имеет меньший весовой коэффициент, чем бит D4.
Теоретически это позволяет получить 4 уровня сигнала, однако в существующих программах эта особенность не использовалась.

В отечественных клонах и компьютерах производства Amstrad эти особенности отсутствуют.

#7FFE - полуряд Space...B
#BFFE - полуряд Enter...H
#DFFE - полуряд P...Y
#EFFE - полуряд 0...6
#F7FE - полуряд 1...5
#FBFE - полуряд Q...T
#FDFE - полуряд A...G
#FEFE - полуряд CS...V
#FF - порт атрибутов



/*

http://svn.zxevo.ru/listing.php?repname=pentevo&path=%2Ffpga%2Fcurrent%2F&rev=921&peg=921#a0e99544d885856b3a591393b2a4ba7c1

assign loa=a[7:0];
localparam PORTFD = 8'hFD;
reg pre_bc1,pre_bdir;

alone_coder — Сегодня, в 0:13
// AY control
	always @*
	begin
		pre_bc1 = 1'b0;
		pre_bdir = 1'b0;

		if( loa==PORTFD )
		begin
			if( a[15:14]==2'b11 )
			begin
				pre_bc1=1'b1;
				pre_bdir=1'b1;
			end
			else if( a[15:14]==2'b10 )
			begin
				pre_bc1=1'b0;
				pre_bdir=1'b1;
			end
		end
	end

	assign ay_bc1  = pre_bc1  & (~iorq_n) & ((~rd_n) | (~wr_n));
	assign ay_bdir = pre_bdir & (~iorq_n) & (~wr_n);
*/


/*
	A15..............A0
bffd - 1011 1111 1111 1101
fffd - 1111 1111 1111 1101
*/

/*
https://github.com/UzixLS/zx-sizif-512/blob/master/cpld/rtl/ay.sv

//              bdir bc1 description
// bffd read  |   0   0  inactive
// bffd write |   1   0  write to psg
// fffd read  |   0   1  read from psg
// fffd write |   1   1  latch address

		ay_bc1  <= bus.a[15] == 1'b1 && bus.a[14] == 1'b1 && bus.a[1] == 0 && bus.ioreq;
		ay_bdir <= bus.a[15] == 1'b1 && bus.a[1] == 0 && bus.ioreq && bus.wr;	  
*/


/*
https://zx-pk.ru/threads/3429-deshifratsiya-ay-ym/page4.html

Вот примерно будет выглядеть так обращение к AY:

BC1 - он же FFFDh на чтение и запись:
BC1 = !(A15 & A14 & A3 & A2 & A0) # A1 # IORQ # ! (WR $ RD);

BDIR - он же BFFDh на запись:
BDIR = !(A15 & A3 & A2 & A0 & RD) # A14 # A1 # WR # IORQ;

По моему так. Правда обращение к AY будет в достаточно большом диапазоне адресов, которые заканчиваются на Dh.
Но зато у тебя освобождаются несколько входов - и взаиморотации с управляющими сигналами, описанными выше, ты освободишь себе несколько выходов.

$ - это какая логическая функция ??
Это - Исключающее ИЛИ (XOR - по нашему). Так в WinCupl записывается.
*/