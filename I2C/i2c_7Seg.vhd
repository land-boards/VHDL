
-- I2C总线是一种非常常用的串行总线，它操作简便，占用接口少。本程序介绍操作一个I2C总线接口的EEPROM AT24C02
-- 的方法，使用户了解I2C总线协议和读写方法。
-- 实验过程是：按动开发板键盘某个键CPLD将拨码开关的数据写入EEPROM的某个地址，按动另外一个键，将刚写入的数据
-- 读回CPLD，并在数码管上显示。（ 按sw0写拨码 开关值入24c02,按sw1读出数值在数码管上显示
-- 为了更好的理解程序，用户应该仔细阅读光盘中的AT24C02的手册
-- 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY i2c IS
   PORT (
      clk                     : IN std_logic;   
      rst                     : IN std_logic;   
      data_in                 : IN std_logic_vector(3 DOWNTO 0);   
      scl                     : OUT std_logic;    --I2C时钟线
      sda                     : INOUT std_logic;  --I2C数据线 
      wr_input                : IN std_logic;     --拨码开关输入想写入EEPROM的数据
      rd_input                : IN std_logic;     --要求写的输入
      lowbit                  : OUT std_logic;    --要求读的输入
      en                      : OUT std_logic_vector(1 DOWNTO 0);   --输出一个低电平给矩阵键盘的某一行
      seg_data                : OUT std_logic_vector(7 DOWNTO 0)); --  数码管使能
END i2c;

ARCHITECTURE translated OF i2c IS


   SIGNAL seg_data_buf             :  std_logic_vector(7 DOWNTO 0);   
   SIGNAL cnt_scan                 :  std_logic_vector(11 DOWNTO 0);   
   SIGNAL sda_buf                  :  std_logic;   --sda输入输出数据缓存
   SIGNAL link                     :  std_logic;   -- sda输出标志
   --一个scl时钟周期的四个相位阶段，将一个scl周期分为4段
   --phase0对应scl的上升沿时刻，phase2对应scl的下降沿时刻，phase1对应从scl高电平的中间时刻，phase2对应从scl低电平的中间时刻，
   SIGNAL phase0                   :  std_logic;   
   SIGNAL phase1                   :  std_logic;   
   SIGNAL phase2                   :  std_logic;   
   SIGNAL phase3                   :  std_logic;   
   --phase0对应scl的上升沿时刻，phase2对应scl的下降沿时刻，phase1对应从scl高电平的中间时刻，phase2对应从scl低电平的中间时刻，
   SIGNAL clk_div                  :  std_logic_vector(7 DOWNTO 0);  --分频计数器 
   SIGNAL main_state               :  std_logic_vector(1 DOWNTO 0);   
   SIGNAL i2c_state                :  std_logic_vector(2 DOWNTO 0);--对i2c操作的状态   
   SIGNAL inner_state              :  std_logic_vector(3 DOWNTO 0);--i2c每一操作阶段内部状态   
   SIGNAL cnt_delay                :  std_logic_vector(19 DOWNTO 0); --按键延时计数器  
   SIGNAL start_delaycnt           :  std_logic;   --按键延时开始
   SIGNAL writeData_reg            :  std_logic_vector(7 DOWNTO 0);--要写的数据的寄存器   
   SIGNAL readData_reg             :  std_logic_vector(7 DOWNTO 0);--读回数据的寄存器   
   SIGNAL addr                     :  std_logic_vector(7 DOWNTO 0);--被操作的EEPROM字节的地址   
   CONSTANT  div_parameter         :  std_logic_vector(7 DOWNTO 0) := "01100100";--分频系数，AT24C02最大支持400K时钟速率    
   CONSTANT  start                 :  std_logic_vector(3 DOWNTO 0) := "0000";     --开始
   CONSTANT  first                 :  std_logic_vector(3 DOWNTO 0) := "0001";     --第1位
   CONSTANT  second                :  std_logic_vector(3 DOWNTO 0) := "0010";     --第2位
   CONSTANT  third                 :  std_logic_vector(3 DOWNTO 0) := "0011";    --第3位
   CONSTANT  fourth                :  std_logic_vector(3 DOWNTO 0) := "0100";     --第4位
   CONSTANT  fifth                 :  std_logic_vector(3 DOWNTO 0) := "0101";    --第5位
   CONSTANT  sixth                 :  std_logic_vector(3 DOWNTO 0) := "0110";     --第6位
   CONSTANT  seventh               :  std_logic_vector(3 DOWNTO 0) := "0111";     --第7位
   CONSTANT  eighth                :  std_logic_vector(3 DOWNTO 0) := "1000";    --第8位
   CONSTANT  ack                   :  std_logic_vector(3 DOWNTO 0) := "1001";    --确认位
   CONSTANT  stop                  :  std_logic_vector(3 DOWNTO 0) := "1010";    --结束位
   CONSTANT  ini                   :  std_logic_vector(2 DOWNTO 0) := "000";    --初始化EEPROM状态
   CONSTANT  sendaddr              :  std_logic_vector(2 DOWNTO 0) := "001";    --发送地址状态
   CONSTANT  write_data            :  std_logic_vector(2 DOWNTO 0) := "010";    --写数据状态�
   CONSTANT  read_data             :  std_logic_vector(2 DOWNTO 0) := "011";    --读数据状态
   CONSTANT  read_ini              :  std_logic_vector(2 DOWNTO 0) := "100";    
   SIGNAL temp_xhdl6               :  std_logic;   
   SIGNAL scl_xhdl1                :  std_logic;   
   SIGNAL lowbit_xhdl2             :  std_logic;   
   SIGNAL en_xhdl3                 :  std_logic_vector(1 DOWNTO 0);   
   SIGNAL seg_data_xhdl4           :  std_logic_vector(7 DOWNTO 0);     

BEGIN
   scl <= scl_xhdl1;
   lowbit <= lowbit_xhdl2;
   en <= en_xhdl3;
   seg_data <= seg_data_xhdl4;
   lowbit_xhdl2 <= '0' ;
   temp_xhdl6 <= sda_buf WHEN (link) = '1' ELSE 'Z';
   sda <= temp_xhdl6 ;

   PROCESS(clk,rst)
   BEGIN
      
      IF (NOT rst = '1') THEN
         cnt_delay <= "00000000000000000000";    
      ELSIF(clk'event and clk='1')THEN
         IF (start_delaycnt = '1') THEN
            IF (cnt_delay /= "11000011010100000000") THEN
               cnt_delay <= cnt_delay + "00000000000000000001";    
            ELSE
               cnt_delay <= "00000000000000000000";    
            END IF;
         END IF;
      END IF;
   END PROCESS;

   PROCESS(clk,rst)
   BEGIN
      
      IF (NOT rst = '1') THEN
         clk_div <= "00000000";    
         phase0 <= '0';    
         phase1 <= '0';    
         phase2 <= '0';    
         phase3 <= '0';    
      ELSIF(clk'event and clk='1')THEN
         IF (clk_div /= div_parameter - 1) THEN
            clk_div <= clk_div + "00000001";    
         ELSE
            clk_div <= "00000000";    
         END IF;
         IF (phase0 = '1') THEN
            phase0 <= '0';    
         ELSE
            IF (clk_div = "01100011") THEN
               phase0 <= '1';    
            END IF;
         END IF;
         IF (phase1 = '1') THEN
            phase1 <= '0';    
         ELSE
            IF (clk_div = "00011000") THEN
               phase1 <= '1';    
            END IF;
         END IF;
         IF (phase2 = '1') THEN
            phase2 <= '0';    
         ELSE
            IF (clk_div = "00110001") THEN
               phase2 <= '1';    
            END IF;
         END IF;
         IF (phase3 = '1') THEN
            phase3 <= '0';    
         ELSE
            IF (clk_div = "01001010") THEN
               phase3 <= '1';    
            END IF;
         END IF;
      END IF;
   END PROCESS;

--///////////////////////////EEPROM操作部分/////////////
   PROCESS(clk,rst)
   BEGIN
      
      IF (NOT rst = '1') THEN
         start_delaycnt <= '0';    
         main_state <= "00";    
         i2c_state <= ini;    
         inner_state <= start;    
         scl_xhdl1 <= '1';    
         sda_buf <= '1';    
         link <= '0';    
         writeData_reg <= "00000101";    
         readData_reg <= "00000000";    
         addr <= "00001010";    
      ELSIF(clk'event and clk='1')THEN
         CASE main_state IS
            WHEN "00" =>  --等待读写要求
                     writeData_reg <= "0000" & data_in;    
                     scl_xhdl1 <= '1';    
                     sda_buf <= '1';    
                     link <= '0';    
                     inner_state <= start;    
                     i2c_state <= ini;    
                     IF (cnt_delay = "00000000000000000000" AND (NOT (wr_input='1') OR NOT (rd_input='1'))) THEN
                        start_delaycnt <= '1';    
                     ELSE
                        IF (cnt_delay = "11000011010100000000") THEN
                           start_delaycnt <= '0';    
                           IF (NOT wr_input = '1') THEN
                              main_state <= "01";    
                           ELSE
                              IF (NOT rd_input = '1') THEN
                                 main_state <= "10";    
                              END IF;
                           END IF;
                        END IF;
                     END IF;
            WHEN "01" =>   --向EEPROM写入数据
                     IF (phase0 = '1') THEN
                        scl_xhdl1 <= '1';    
                     ELSE
                        IF (phase2 = '1') THEN
                           scl_xhdl1 <= '0';    
                        END IF;
                     END IF;
                     CASE i2c_state IS
                        WHEN ini =>    --初始化EEPROM
                                 CASE inner_state IS
                                    WHEN start =>
                                             IF (phase1 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= '0';    
                                             END IF;
                                             IF ((phase3 AND link) = '1') THEN
                                                inner_state <= first;    
                                                sda_buf <= '1';    
                                                link <= '1';    
                                             END IF;
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '1';    
                                                link <= '1';    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(7);    
                                                inner_state <= first;    
                                                i2c_state <= sendaddr;    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN sendaddr =>   --送相应字节的地址
                                 CASE inner_state IS
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(6);    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(5);    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(4);    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(3);    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(2);    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(1);    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(0);    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(7);    
                                                inner_state <= first;    
                                                i2c_state <= write_data;    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN write_data =>  ---写入数据
                                 CASE inner_state IS
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(6);    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(5);    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(4);    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(3);    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(2);    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(1);    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= writeData_reg(0);    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             ELSE
                                                IF (phase3 = '1') THEN
                                                   link <= '1';    
                                                   sda_buf <= '0';    
                                                   inner_state <= stop;    
                                                END IF;
                                             END IF;
                                    WHEN stop =>
                                             IF (phase1 = '1') THEN
                                                sda_buf <= '1';    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                main_state <= "00";    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN OTHERS  =>
                                 main_state <= "00";    
                        
                     END CASE;
            WHEN "10" =>  --读EEPROM
                     IF (phase0 = '1') THEN
                        scl_xhdl1 <= '1';    
                     ELSE
                        IF (phase2 = '1') THEN
                           scl_xhdl1 <= '0';    
                        END IF;
                     END IF;
                     CASE i2c_state IS
                        WHEN ini =>
                                 CASE inner_state IS
                                    WHEN start =>
                                             IF (phase1 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= '0';    
                                             END IF;
                                             IF ((phase3 AND link) = '1') THEN
                                                inner_state <= first;    
                                                sda_buf <= '1';    
                                                link <= '1';    
                                             END IF;
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '1';    
                                                link <= '1';    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(7);    
                                                inner_state <= first;    
                                                i2c_state <= sendaddr;    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN sendaddr =>
                                 CASE inner_state IS
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(6);    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(5);    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(4);    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(3);    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(2);    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(1);    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= addr(0);    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= '1';    
                                                inner_state <= start;    
                                                i2c_state <= read_ini;    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN read_ini =>
                                 CASE inner_state IS
                                    WHEN start =>
                                             IF (phase1 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= '0';    
                                             END IF;
                                             IF ((phase3 AND link) = '1') THEN
                                                inner_state <= first;    
                                                sda_buf <= '1';    
                                                link <= '1';    
                                             END IF;
                                    WHEN first =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '1';    
                                                link <= '1';    
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '0';    
                                                link <= '1';    
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase3 = '1') THEN
                                                sda_buf <= '1';    
                                                link <= '1';    
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                IF (sda_buf = '1') THEN
                                                   main_state <= "00";    
                                                END IF;
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                link <= '0';    
                                                inner_state <= first;    
                                                i2c_state <= read_data;    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN read_data =>
                                 CASE inner_state IS
                                    WHEN first =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= second;    
                                             END IF;
                                    WHEN second =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= third;    
                                             END IF;
                                    WHEN third =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= fourth;    
                                             END IF;
                                    WHEN fourth =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= fifth;    
                                             END IF;
                                    WHEN fifth =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= sixth;    
                                             END IF;
                                    WHEN sixth =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= seventh;    
                                             END IF;
                                    WHEN seventh =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= eighth;    
                                             END IF;
                                    WHEN eighth =>
                                             IF (phase0 = '1') THEN
                                                sda_buf <= sda;    
                                             END IF;
                                             IF (phase1 = '1') THEN
                                                readData_reg(7 DOWNTO 1) <= readData_reg(6 DOWNTO 0);    
                                                readData_reg(0) <= sda;    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                inner_state <= ack;    
                                             END IF;
                                    WHEN ack =>
                                             IF (phase3 = '1') THEN
                                                link <= '1';    
                                                sda_buf <= '0';    
                                                inner_state <= stop;    
                                             END IF;
                                    WHEN stop =>
                                             IF (phase1 = '1') THEN
                                                sda_buf <= '1';    
                                             END IF;
                                             IF (phase3 = '1') THEN
                                                main_state <= "00";    
                                             END IF;
                                    WHEN OTHERS =>
                                             NULL;
                                    
                                 END CASE;
                        WHEN OTHERS =>
                                 NULL;
                        
                     END CASE;
            WHEN OTHERS =>
                     NULL;
            
         END CASE;
      END IF;
   END PROCESS;

---///////////////////////////数码管显示部分/////////////	
   PROCESS(clk,rst)
   BEGIN
      
      IF (NOT rst = '1') THEN
         cnt_scan <= "000000000000";    
         en_xhdl3 <= "10";    
      ELSIF(clk'event and clk='1')THEN
         cnt_scan <= cnt_scan + "000000000001";    
         IF (cnt_scan = "111111111111") THEN
            en_xhdl3 <= NOT en_xhdl3;    
         END IF;
      END IF;
   END PROCESS;

   PROCESS(writeData_reg,readData_reg,en_xhdl3)
   BEGIN
      CASE en_xhdl3 IS
         WHEN "10" =>
                  seg_data_buf <= writeData_reg;    
         WHEN "01" =>
                  seg_data_buf <= readData_reg;    
         WHEN OTHERS  =>
                  seg_data_buf <= "00000000";    
         
      END CASE;
   END PROCESS;

   PROCESS(seg_data_buf)
   BEGIN
      CASE seg_data_buf IS
         WHEN "00000000" =>
                  seg_data_xhdl4 <= "11000000";    
         WHEN "00000001" =>
                  seg_data_xhdl4 <= "11111001";    
         WHEN "00000010" =>
                  seg_data_xhdl4 <= "10100100";    
         WHEN "00000011" =>
                  seg_data_xhdl4 <= "10110000";    
         WHEN "00000100" =>
                  seg_data_xhdl4 <= "10011001";    
         WHEN "00000101" =>
                  seg_data_xhdl4 <= "10010010";    
         WHEN "00000110" =>
                  seg_data_xhdl4 <= "10000010";    
         WHEN "00000111" =>
                  seg_data_xhdl4 <= "11111000";    
         WHEN "00001000" =>
                  seg_data_xhdl4 <= "10000000";    
         WHEN "00001001" =>
                  seg_data_xhdl4 <= "10010000";    
         WHEN "00001010" =>
                  seg_data_xhdl4 <= "10001000";   --A 
         WHEN "00001011" =>
                  seg_data_xhdl4 <= "10000011";    
         WHEN "00001100" =>
                  seg_data_xhdl4 <= "11000110";    
         WHEN "00001101" =>
                  seg_data_xhdl4 <= "10100001";    
         WHEN "00001110" =>
                  seg_data_xhdl4 <= "10000110";    
         WHEN "00001111" =>
                  seg_data_xhdl4 <= "10001110";    
         WHEN OTHERS  =>
                  seg_data_xhdl4 <= "11111111";    
         
      END CASE;
   END PROCESS;

END translated;
