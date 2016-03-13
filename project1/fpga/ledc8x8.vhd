--Author: Pavol Loffay xloffa00@stud.fit.vutbr.cz
--Date: 9.10.2011
--Project: projekt 1. do predmetu INP, riadenie maticoveho displeja
--sucastou projektu je aj subor ledc8x8.ucf

--kniznice
library ieee;
	--kniznica obsahujuca zakladne syntetizovatelne funkcie
	use ieee.std_logic_1164.all;
	--podpora pre syntezu aritmetickych operacii
	use ieee.std_logic_arith.all;
	--umoznuje pracovat bez znamienka
	use ieee.std_logic_unsigned.all;
	
--deklaracia entity	
entity ledc8x8 is
	port (
--vstupne signaly entity
		SMCLK		: in std_logic;
		RESET		: in std_logic;
--vystupne signaly entity
		LED		: out std_logic_vector(7 downto 0);
		ROW		: out std_logic_vector(7 downto 0)
	);
end ledc8x8;

--deklaracia architektury
architecture behavioral of ledc8x8 is 
	--deklaracia signalov pouzitych vnutry architektury (entity)
	signal ce		: std_logic;
	signal switch	: std_logic;
	--moje vlastne
	--pocitadlo pre proces crl_cnt
	signal counter : std_logic_vector(21 downto 0);
	signal vypis : std_logic_vector(7 downto 0);
	signal aktivny_riadok : std_logic_vector(7 downto 0);

--zaciatok modelovane s procesmi	
begin

	--proces sa spusti iba v pripade aktivacie RESET alebo SMLCLK
	crl_cnt: process(RESET,SMCLK)
	--cast pre deklarovanie premennych v procese
	begin
		-- ak je reset v log. '1'
		if(RESET = '1') then
			--tak sa vynuluje counter
			counter <= (others => '0');
		--ak je SMCLK aktivne a v log. 1,
		elsif (SMCLK'event and SMCLK = '1') then
			--tak sa obsah counter zvacsi o 1
			counter <= counter + 1;
		end if;
	end process crl_cnt;
	
	--nastavenie signalov ce a switch, ktore su zavysle na counter 		
	--ce sa nastaci ak je spodnych 8 bitov counter v log. 1
	ce <= '1' when counter(7 downto 0) = "11111111" else
		'0';
				
	--do switch sa priradi 21bit
	switch <= counter(21);
		
	--ce
	row_cnt: process(SMCLK,RESET,aktivny_riadok,ce)
	begin
		--ak je RESET v log. 1 tak sa nastavi 
		--aktivny prvy riadok
		if (RESET = '1') then
			aktivny_riadok <= "11111110";
		elsif (SMCLK'event and SMCLK = '1' and ce = '1') then
			--rotacia
			aktivny_riadok <= aktivny_riadok(0) & aktivny_riadok(7 downto 1);
		end if;
		
		--do row sa priradi aktivny riadok
		ROW <= aktivny_riadok;
	end process row_cnt;
		
	--tento proces popisuje ktore ledky maju byt aktivne na ktorom riadku
	--proces sa spusta ked je zmena na signale aktivny_riadok
	dec: process(aktivny_riadok)
	begin 
		case aktivny_riadok is 
			when "01111111" => vypis <= "11110001";
			when "10111111" => vypis <= "00010001";
			when "11011111" => vypis <= "00010001";
			when "11101111" => vypis <= "00010001";
			when "11110111" => vypis <= "00011111";
			when "11111011" => vypis <= "00011001";
			when "11111101" => vypis <= "00011001";
			when "11111110" => vypis <= "00011111";
			when others => vypis <= "00000000";
		end case;
	end process dec;
		
	--proces sposobi, ze ked je aktivny switch tak nastavi LED, ktore ledky sa maju aktivovat	
	--toto je suciastka z planu ?? je to multiplexor
	multiplexor: process(switch,vypis)
	begin
		if switch = '1' then
			LED <= vypis;
		else
			LED <= "00000000";
		end if;
	end process multiplexor;
			
end architecture behavioral;