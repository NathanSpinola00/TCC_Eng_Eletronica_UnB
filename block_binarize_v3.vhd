----------------------------------------------------------------------------------
-- Arquivo: block_binarize_v3.vhd
-- Proposta 3 (Legarda) - binarização por bloco:
--   - Entrada: BlockHist_t (BLOCK_SIZE células, cada uma com NUM_BINS bins amplitude)
--   - Soma total do bloco (todos os bins) => soma_total
--   - Média: avg = soma_total / (BLOCK_SIZE*NUM_BINS)
--   - Saída binária: bit_i = 1 se bin_i >= avg, senão 0
--
-- Stall-capable: 1-deep buffer na saída.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity block_binarize_v3 is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: token por bloco
    in_valid      : in  std_logic;
    in_ready      : out std_logic;
    block_hist_in : in  BlockHist_t;

    -- Saída: descritor binário do bloco
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    bin_desc_out    : out std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0)
  );
end entity;

architecture rtl of block_binarize_v3 is
  constant NUM_FEATURES : integer := BLOCK_SIZE * NUM_BINS;

  -- 1-deep output buffer
  signal v_out   : std_logic := '0';
  signal desc_r  : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0) := (others => '0');

  signal in_ready_i : std_logic;

begin
  -- posso aceitar novo bloco se:
  -- - não tenho saída pendente, ou
  -- - tenho saída pendente mas o downstream vai consumir agora
  in_ready_i <= '1' when (v_out='0') or (out_ready='1') else '0';
  in_ready   <= in_ready_i;

  out_valid    <= v_out;
  bin_desc_out <= desc_r;

  process(clk)
    variable sum_total : unsigned(SUM_BLOCK_BITS-1 downto 0);
    variable avg       : unsigned(HIST_BIN_BITS-1 downto 0);

    variable bitvec : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0);
    variable k      : integer;

    variable val_bin : unsigned(HIST_BIN_BITS-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out  <= '0';
        desc_r <= (others => '0');

      else
        if frame_start='1' then
          v_out  <= '0';
          desc_r <= (others => '0');

        else
          -- consumo de saída
          if (v_out='1') and (out_ready='1') then
            v_out <= '0';
          end if;

          -- calcula novo descritor se aceitar entrada
          if (in_valid='1') and (in_ready_i='1') then
            -- 1) soma total (todos os bins do bloco)
            sum_total := (others => '0');
            for c in 0 to BLOCK_SIZE-1 loop
              for b in 0 to NUM_BINS-1 loop
                sum_total := sum_total + resize(block_hist_in(c)(b), SUM_BLOCK_BITS);
              end loop;
            end loop;

            -- 2) média por feature
            -- avg tem HIST_BIN_BITS, sum_total é maior: divide por constante
            avg := resize(sum_total / to_unsigned(NUM_FEATURES, SUM_BLOCK_BITS), HIST_BIN_BITS);

            -- 3) binariza em ordem linear: cell-major, depois bin
            -- idx = c*NUM_BINS + b
            bitvec := (others => '0');
            for c in 0 to BLOCK_SIZE-1 loop
              for b in 0 to NUM_BINS-1 loop
                k := c*NUM_BINS + b;
                val_bin := block_hist_in(c)(b);
                if val_bin >= avg then
                  bitvec(k) := '1';
                else
                  bitvec(k) := '0';
                end if;
              end loop;
            end loop;

            desc_r <= bitvec;
            v_out  <= '1';
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;
