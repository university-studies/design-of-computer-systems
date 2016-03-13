-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2011 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Zdenek Vasicek <vasicek AT fit.vutbr.cz>

-- Author: Pavol Loffay
-- Email: xloffa00@stud.fit.vutbr.cz
-- Data: 14.12.2011
-- Project: 2. projekt do predmetu INP, implementacia procesora pre jazuik brainFuck

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
-- zde dopiste potrebne deklarace signalu
-- deklaracia signalov pouzitych vnutry entity (cize v cpu)

-- deklaracia typov signalov pre stavovy automat
type fsm_states is (state_idle, state_fetch0, state_fetch1, state_decode, state_inc_pointer,
                    state_store_my_reg, state_dec_pointer, state_inc_value0,
						  state_inc_value1, state_inc_value2, state_dec_value0, state_dec_value1,
						  state_dec_value2, state_while_begin, state_while_begin1,
						  state_while_begin2, state_while_begin3, state_while_begin4, state_while_begin5,
						  state_while_end, state_while_end1, state_while_end2, state_while_end3,
						  state_while_end4, state_while_end5, state_while_end6, state_write0,
						  state_write1, state_write2, state_getchar0,
						  state_getchar1, state_getchar2, state_null, state_comment);
signal present_state : fsm_states;
signal next_state : fsm_states;

-- PC - program counter
-- signaly pre PC register - urcuje adresu kde sa nachadza nasledujuca instrukcia
signal pc_inc : std_logic;
signal pc_dec : std_logic;
signal pc_abus : std_logic; -- urcuje ci sa bude davat obsah pc_reg na adresovy zbernicu
signal pc_reg : std_logic_vector(11 downto 0);

--register kde sa uchovava nacitany kod instrukcie - musi sa dekodovat
signal ireg_reg: std_logic_vector(7 downto 0);
type instruction_type is (inst_inc_pointer, inst_dec_pointer, inst_inc_value, inst_dec_value,
                          inst_while_begin, inst_while_end, inst_write,
								  inst_getchar, inst_null, inst_comment);
								  
-- uchovava dekodovany typ instrukcie
signal ireg_decoded : instruction_type;
signal ireg_ld : std_logic; --urcuje ci sa bude ukladat informacia do ireg_reg

-- ptr register , uklada adresu
signal ptr_inc : std_logic;
signal ptr_dec : std_logic;
signal ptr_abus : std_logic;
signal ptr_reg : std_logic_vector(9 downto 0);

-- cnt register, sluzi pre cyklus while
signal cnt_ld_one : std_logic;
signal cnt_inc : std_logic;
signal cnt_dec : std_logic;
signal cnt_no_zero : std_logic;
signal cnt_reg : std_logic_vector(9 downto 0);

-- my register, uklada vacsinou data na adrese
signal my_reg_inc : std_logic;
signal my_reg_dec : std_logic;
signal my_reg : std_logic_vector(7 downto 0);
signal my_reg_ld_ram : std_logic; -- urcuje ci sa bude zapisovat do my_reg z ram
signal my_reg_ld_port : std_logic; -- urcuje ci sa bude zapisovat do my_reg z klavesnice
signal my_reg_wdata_bus : std_logic; -- pripojenie k RAM cez 3st. budic na zapisovanie obsahu my_reg do RAM
signal my_reg_outdata_bus : std_logic; --pripojenie na lcd cez 3st. budic na zapisovanie obsahu my_reg na LCD
begin
---------------------------------------------------------------------------------
--                         procesy, kod programu
---------------------------------------------------------------------------------
-- zde dopiste vlastni VHDL kod
-- tu budu paralerne beziace procesi 
-- kod v procese ide linearne a zmeny v premennych/signaloch 
-- 	sa prejavia az po skonceni procesu 

---------------------------------------------------------------------------------
--                         PC - register
---------------------------------------------------------------------------------
--proces pre PC register
pc_register: process (RESET, CLK)
-- cast pre deklarovanie premennych v procese
begin
	-- vynulovanie ak je nastaveny reset
	if (RESET = '1') then
		pc_reg <= (others => '0');
	
	--ak je znema na CLK a CLK = 1
	elsif (CLK'event) and (CLK = '1') then
		if (pc_inc = '1') then
			pc_reg <= pc_reg + 1;
		elsif (pc_dec = '1') then
			pc_reg <= pc_reg - 1;
		end if;
	end if;
end process pc_register;

-- tristavovy budic sposoby prenesenie hodnoty z pc_reg
-- na adresovu zbernicu ROM kde su ulozene INSTRUKCIE
-- 'Z' znamena stav vysokej impedancie cize 
-- pc_reg je odpojeny od CODE_ADDR
CODE_ADDR <= pc_reg when (pc_abus = '1')
	else (others => 'Z');

---------------------------------------------------------------------------------
--                         IR - instruction register
---------------------------------------------------------------------------------
-- IR - instrukcny register, uchovava aktualnu instrukciu
-- z DBUS sa ulozi instrukcia
inst_reg: process (RESET, CLK)
begin
	if (RESET = '1') then
		ireg_reg <= (others => '0');
		
	elsif (CLK'event) and (CLK = '1') then
		if (ireg_ld = '1') then
			ireg_reg <= CODE_DATA;
		end if;
	end if;
end process inst_reg;

-- dekodovanie instrukcii ulozenych v inst_reg
process (ireg_reg)
begin
	case (ireg_reg(7 downto 4)) is
		when X"0" => 
			case (ireg_reg(3 downto 0)) is
				when X"0" =>
					ireg_decoded <= inst_null;
				when others =>
					ireg_decoded <= inst_comment;
			end case;
			
		when X"2" =>
			case (ireg_reg(3 downto 0)) is
				when X"B" =>
					ireg_decoded <= inst_inc_value;
				when X"D" =>
					ireg_decoded <= inst_dec_value;
				when X"E" =>
					ireg_decoded <= inst_write;
				when X"C" =>
					ireg_decoded <= inst_getchar;
				when others =>
					ireg_decoded <= inst_comment;
			end case;
			
		when X"3" =>
			case (ireg_reg(3 downto 0)) is
				when X"E" =>
					ireg_decoded <= inst_inc_pointer;
				when X"C" =>
					ireg_decoded <= inst_dec_pointer;
				when others =>
					ireg_decoded <= inst_comment;
			end case;
			
		when X"5" => 
			case (ireg_reg(3 downto 0)) is
				when X"B" =>
					ireg_decoded <= inst_while_begin;
				when X"D" =>
					ireg_decoded <= inst_while_end;
				when others =>
					ireg_decoded <= inst_comment;
			end case;
		when others => 
			ireg_decoded <= inst_comment;
		end case;
end process;

---------------------------------------------------------------------------------
--                         ptr_reg
---------------------------------------------------------------------------------
-- proces pre PTR register
ptr_register: process (RESET, CLK)
begin
	if (RESET = '1') then
		ptr_reg <= (others => '0');
		
	elsif (CLK'event) and (CLK = '1') then
		if (ptr_inc = '1') then
			ptr_reg <= ptr_reg + 1;
		elsif (ptr_dec = '1') then
			ptr_reg <= ptr_reg - 1;
		end if;
	end if;	
end process ptr_register;

-- tristavovy budic na pripojenie ptr_reg na DATA_ADDR
DATA_ADDR <= ptr_reg when (ptr_abus = '1')
	else (others => 'Z');

---------------------------------------------------------------------------------
--                         cnt_reg
---------------------------------------------------------------------------------
-- proces pre CNT register
cnt_register: process (RESET, CLK)
begin
	if (RESET = '1') then
		cnt_reg <= (others => '0');
		
	elsif (CLK'event) and (CLK = '1') then
		if (cnt_ld_one = '1') then
			cnt_reg(9 downto 0) <= "0000000001";
		elsif (cnt_inc = '1') then
			cnt_reg <= cnt_reg + 1;
		elsif (cnt_dec = '1') then
			cnt_reg <= cnt_reg - 1;
		end if;
	end if;	
end process cnt_register;

cnt_no_zero <= '1' when (cnt_reg(9 downto 0) /= "0000000000")
	else '0';
---------------------------------------------------------------------------------
--                         my_register
---------------------------------------------------------------------------------
my_register: process(RESET, CLK)
begin
	if (RESET = '1') then
		my_reg <= (others => '0');
		
	elsif (CLK'event) and (CLK = '1') then
		if (my_reg_ld_ram = '1') then
			my_reg <= DATA_RDATA;
		elsif (my_reg_ld_port = '1') then
			my_reg <= IN_DATA;
		elsif (my_reg_inc = '1') then
			my_reg <= my_reg + 1;
		elsif (my_reg_dec = '1') then
			my_reg <= my_reg - 1;
		end if;
	end if;
end process my_register;

DATA_WDATA <= my_reg when (my_reg_wdata_bus = '1')
	else (others => 'Z');
	
OUT_DATA <= my_reg when (my_reg_outdata_bus = '1')
	else (others => 'Z');
---------------------------------------------------------------------------------
--                         FSM - finite state machine
---------------------------------------------------------------------------------
--proces, ktory zaruci aby sa nastavoval present state
-- na zaciatku nastavi stav s_idle
fsm_pstate: process(RESET, CLK)
begin
	if (RESET = '1') then
		present_state <= state_idle;
	
	-- ak je aktivita na CLK a EN je aktivne 
	--posunie sa do dalsieho stavu 
	elsif (CLK'event) and (CLK = '1') then
		if (EN = '1') then
			present_state <= next_state;
		end if;
	end if;
end process fsm_pstate;

-- proces stavoveho automatu
next_state_logic: process(present_state, ireg_decoded, OUT_BUSY, IN_VLD, cnt_no_zero, my_reg)
begin
----------------------------------------------------------------------
--                      inicializacia signalov
---------------------------------------------------------------------- 
	next_state <= state_idle;

	pc_inc <= '0';
	pc_dec <= '0';
	pc_abus <= '0';
	
	CODE_EN <= '0';
	DATA_RDWR <= '0';
	OUT_WE <= '0';
	DATA_EN <= '0';
	IN_REQ <= '0';
	
	ptr_inc <= '0';
	ptr_dec <= '0';
	ptr_abus <= '0';
	
	cnt_inc <= '0';
	cnt_dec <= '0';
	cnt_ld_one <= '0';
	
	my_reg_inc <= '0';
	my_reg_dec <= '0';
	my_reg_ld_ram <= '0';
	my_reg_ld_port <= '0';
	my_reg_outdata_bus <= '0';
	my_reg_wdata_bus <= '0';
	
	ireg_ld <= '0';
	
	case (present_state) is
----------------------------------------------------------------------
--                            idle
---------------------------------------------------------------------- 
		-- idle stav procesuru
		when state_idle =>
			next_state <= state_fetch0;

----------------------------------------------------------------------
--                        instruction fetch 
---------------------------------------------------------------------- 
		-- pripoji pc_abus na 1, co sposoby 
		-- prenesenie hodnoty pc_reg na CODE_ADDR
		-- nastavi CODE_EN co sposobi aktivaciu pamete
		when state_fetch0 =>
			next_state <= state_fetch1;
			pc_abus <= '1';
			CODE_EN <= '1';
	
		-- skopiruje kod instrukcie ktory je na CODE_DATA
		-- do inst_reg
		when state_fetch1 =>
			next_state <= state_decode;
			ireg_ld <= '1';

----------------------------------------------------------------------
--                     instruction decode
---------------------------------------------------------------------- 
		when state_decode =>
			case ireg_decoded is
				when inst_inc_pointer =>
					next_state <= state_inc_pointer;
				when inst_dec_pointer =>
					next_state <= state_dec_pointer;
				when inst_inc_value =>
					next_state <= state_inc_value0;
				when inst_dec_value =>
					next_state <= state_dec_value0;
				when inst_while_begin =>
					next_state <= state_while_begin;
				when inst_while_end =>
					next_state <= state_while_end;
				when inst_write =>
					next_state <= state_write0;
				when inst_getchar =>
					next_state <= state_getchar0;
				when inst_null =>
					next_state <= state_null;
				when inst_comment =>
					next_state <= state_comment;
				
				when others =>
					next_state <= state_null;
			end case;

----------------------------------------------------------------------
--                     instruction execute
---------------------------------------------------------------------- 	
----------------------------------------------------------------------
--                     ptr_reg++, ptr_reg--
---------------------------------------------------------------------- 
		-- ptr_reg++
		when state_inc_pointer =>
			next_state <= state_fetch0;
			pc_inc <= '1';
			ptr_inc <= '1';			
		
		-- ptr_reg--
		when state_dec_pointer =>
			next_state <= state_fetch0;
			pc_inc <= '1';
			ptr_dec <= '1';

----------------------------------------------------------------------
--                     *ptr_reg++
---------------------------------------------------------------------- 		
		-- *ptr_reg++
		-- na DATA_ADDR vystavim hodnotu ptr_reg
		when state_inc_value0 =>
			next_state <= state_inc_value1;
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '0';
			
		
		-- z DATA_RDATA sa ulozia data do my_reg
		when state_inc_value1 =>
			next_state <= state_inc_value2;
			my_reg_ld_ram <= '1';
			
		-- inkrementujem my_reg
		when state_inc_value2 =>
			next_state <= state_store_my_reg;				
			my_reg_inc <= '1';
----------------------------------------------------------------------
--                     store_my_reg
---------------------------------------------------------------------- 	
		-- ulozenie obsahu my_reg na adresu ptr_reg v pameti RAM
		-- vystavenie adresy, zapnutie pamete
		when state_store_my_reg =>
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '1';
			my_reg_wdata_bus <= '1';
			next_state <= state_fetch0;
			pc_inc <= '1';

----------------------------------------------------------------------
--                     *ptr_reg--
---------------------------------------------------------------------- 		
		-- *ptr_reg--
		-- dekrementuje hodnotu
		when state_dec_value0 =>
			next_state <= state_dec_value1;
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '0';
		
		-- z DATA_RDATA sa ulozia data do my_reg
		when state_dec_value1 =>
			next_state <= state_dec_value2;
			my_reg_ld_ram <= '1';
		
		-- inkrementujem my_reg
		when state_dec_value2 =>
			next_state <= state_store_my_reg;
			my_reg_dec <= '1';
		
--------------------------------------------------------------
--                     while
--------------------------------------------------------------	
		--inkrementujem PC a nacitam ram[ptr]
		when state_while_begin =>
			next_state <= state_while_begin1;
			pc_inc <= '1';
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '0';
		
		when state_while_begin1 =>
			next_state <= state_while_begin2; 
			my_reg_ld_ram <= '1';
			
		-- v my_reg uz mam nacitany ram(ptr)
		-- akje my_reg = 0 skocim za ], inak pokracujem
		-- inkrementujem cnt_reg,
		when state_while_begin2 =>			
			if (my_reg(7 downto 0) = "00000000") then
				cnt_ld_one <= '1';
				next_state <= state_while_begin3;
			else
				next_state <= state_fetch0;
		end if;
		
		-- tu sa musia preskocit vsetky vnorene [[[]]]
		when state_while_begin3 =>
			if (cnt_no_zero = '1') then
				-- nahram do iar_reg obsah ram[pc] a dekodujem instrukciu
				-- ako keby fetch0
				pc_abus <= '1';
				CODE_EN <= '1';
				next_state <= state_while_begin4;
			else
				next_state <= state_fetch0;
		end if;
		
		-- ako keby fetch1
		when state_while_begin4 =>
			ireg_ld <= '1';
			next_state <= state_while_begin5;
			
		when state_while_begin5 =>
			pc_inc <= '1';
			next_state <= state_while_begin3;
			case (ireg_decoded) is
				when inst_while_begin =>
					cnt_inc <= '1';
				when inst_while_end =>
					cnt_dec <= '1';
				when others =>
					null;
			end case;
----------------------------------------------------------------
			--			while_end
		-- ak je hodnota ram[ptr] = 0; skoci
		-- za [ ikan pokracuje dalej
		when state_while_end =>
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '0';
			next_state <= state_while_end1;
		
		when state_while_end1 =>
			next_state <= state_while_end2;
			my_reg_ld_ram <= '1';
			
		when state_while_end2 =>
			if (my_reg(7 downto 0) = "00000000") then
				pc_inc <= '1';
				next_state <= state_fetch0;
			else
				cnt_ld_one <= '1';
				pc_dec <= '1';
				next_state <= state_while_end3;
			end if;
			
		when state_while_end3 =>
			if (cnt_no_zero = '1') then
				-- nahram do iar_reg obsah ram[pc] a dekodujem instrukciu
				-- ako keby fetch0
				pc_abus <= '1';
				CODE_EN <= '1';
				next_state <= state_while_end4;
			else
				next_state <= state_fetch0;
			end if;
			
		--	ako keby fetch1
		when state_while_end4 =>
			ireg_ld <= '1';
			next_state <= state_while_end5;
			
		when state_while_end5 =>
			next_state <= state_while_end6;
			case (ireg_decoded) is
				when inst_while_end =>
					cnt_inc <= '1';
				when inst_while_begin =>
					cnt_dec <= '1';
				when others =>
					null;
			end case;
		
		when state_while_end6 =>
			next_state <= state_while_end3;
			if (cnt_no_zero = '1') then
				pc_dec <= '1';
			else
				pc_inc <= '1';
			end if;
					
--------------------------------------------------------------
--                     putchar(*ptr)
--------------------------------------------------------------
		-- putchar(*ptr)
		-- musi pockat while (OUT_BUSI) {}
		when state_write0 =>			
			next_state <= state_write1;
			ptr_abus <= '1';
			DATA_EN <= '1';
			DATA_RDWR <= '0';
		
		when state_write1 => 
			next_state <= state_write2;
			my_reg_ld_ram <= '1';
		
		when state_write2 =>
			if (OUT_BUSY = '0') then				
				OUT_WE <= '1';
				my_reg_outdata_bus <= '1';
				pc_inc <= '1';
				next_state <= state_fetch0;
			else
				next_state <= state_write2;				
			end if;						
						
--------------------------------------------------------------
--                     getchar(*ptr)
--------------------------------------------------------------		
		when state_getchar0 =>			
			next_state <= state_getchar1;			
			IN_REQ <= '1';
			
		when state_getchar1 =>
			if (IN_VLD = '1') then
				next_state <= state_getchar2;
				my_reg_ld_port <= '1';
				--IN_REQ <= '0';
			else
				next_state <= state_getchar1;
			end if;			
			
		when state_getchar2 =>
			next_state <= state_store_my_reg;

--------------------------------------------------------------
--                     null, commet, others
--------------------------------------------------------------	
		-- zastavenie programu
		when state_null =>
			next_state <= state_null;
		
		-- stav komentaru, nedeje sa nic
		when state_comment =>
			pc_inc <= '1';
			next_state <= state_fetch0;
				
		when others =>
			null;
			--next_state <= state_null; --TODO asi je to OK
	end case;
		
end process next_state_logic;
end behavioral;