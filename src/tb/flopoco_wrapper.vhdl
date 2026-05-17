library ieee;
use ieee.std_logic_1164.all;

entity fpall_shared_wrapper is
    generic (
        OP_CODE_GEN : std_logic_vector(1 downto 0) := "00"; -- 00: Add, 01: Mul, 10: Sqrt, 11: Div
        FMT_GEN     : std_logic := '0'                      -- '0': FP32, '1': FP16
    );
    port (
        clk : in std_logic;
        X : in std_logic_vector(33 downto 0);
        Y : in std_logic_vector(33 downto 0) := (others => '0');
        R : out std_logic_vector(33 downto 0) 
    );
end entity;

architecture arch of fpall_shared_wrapper is
    -- Instantiate the logic wrapper which handles the SV enum casting
    component fpall_shared_logic_wrapper is
        port (
            clk : in std_logic;
            opcode_in : in std_logic_vector(1 downto 0);
            fmt_in : in std_logic;
            X : in std_logic_vector(31 downto 0);
            Y : in std_logic_vector(31 downto 0);
            R : out std_logic_vector(31 downto 0)
        );
    end component;
begin
    U_SHARED_LOGIC_WRAP: fpall_shared_logic_wrapper
    port map (
        clk => clk,
        opcode_in => OP_CODE_GEN,
        fmt_in => FMT_GEN,
        X => X(31 downto 0),
        Y => Y(31 downto 0),
        R => R(31 downto 0)
    );
    
    -- FloPoCo specific exception handling for VHDL testbenches
    R(33 downto 32) <= "10" when (OP_CODE_GEN = "10" and X(33 downto 32) /= "01") else
                       "10" when (OP_CODE_GEN /= "10" and (X(33 downto 32) /= "01" or Y(33 downto 32) /= "01")) else
                       "01";
end architecture;
