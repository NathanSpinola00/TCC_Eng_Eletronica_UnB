library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity hog_block_assemble is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: 1 token por célula
    in_valid     : in  std_logic;
    in_ready     : out std_logic;
    cell_idx_in  : in  unsigned(NUM_CELLS_BITS-1 downto 0);
    cell_hist_in : in  CellHist_t;

    -- Saída: 1 token por bloco
    out_valid      : out std_logic;
    out_ready      : in  std_logic;
    block_hist_out : out BlockHist_t
  );
end entity;

architecture rtl of hog_block_assemble is

  constant K       : integer := BLOCK_SIDE;
  constant LB_ROWS : integer := K-1;

  -- linebuffer: guarda K-1 linhas completas
  type lb_row_t is array (0 to NUM_CELLS_X-1) of CellHist_t;
  type lb_mem_t is array (0 to LB_ROWS-1) of lb_row_t;

  signal lb_mem : lb_mem_t := (others => (others => (others => (others => '0'))));

  -- saída 1-deep
  signal v_out        : std_logic := '0';
  signal block_hist_r : BlockHist_t := (others => (others => (others => '0')));

  signal in_ready_i : std_logic;

  signal block_cnt : unsigned(BLOCK_COUNTER_BITS-1 downto 0) := (others => '0');

  function mod_pos(a : integer; m : integer) return integer is
    variable r : integer;
  begin
    if m <= 0 then return 0; end if;
    r := a mod m;
    if r < 0 then r := r + m; end if;
    return r;
  end function;

begin

  -- stall-capable
  in_ready_i <= '1' when (v_out='0') or (out_ready='1') else '0';
  in_ready   <= in_ready_i;

  out_valid      <= v_out;
  block_hist_out <= block_hist_r;

  process(clk)
    variable idx_i : integer;
    variable cx, cy : integer;

    variable row_slot_write : integer;
    variable slot_read      : integer;

    variable new_block : BlockHist_t;
    variable by, bx    : integer;
    variable cell_lin  : integer;
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));

      elsif frame_start='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));

      else
        -- consumo do bloco
        if (v_out='1') and (out_ready='1') then
          v_out <= '0';
        end if;

        -- aceita nova célula
        if (in_valid='1') and (in_ready_i='1') then
          idx_i := to_integer(cell_idx_in);
          cx := idx_i mod NUM_CELLS_X;
          cy := idx_i / NUM_CELLS_X;

          -- 1) escreve a célula no linebuffer
          if LB_ROWS > 0 then
            row_slot_write := mod_pos(cy, LB_ROWS);
            lb_mem(row_slot_write)(cx) <= cell_hist_in;
          end if;

          -- 2) produz bloco APENAS usando dados já armazenados
          if (cx >= (K-1)) and (cy >= (K-1)) and
             (to_integer(block_cnt) < TOTAL_BLOCKS) then

            for by in 0 to K-1 loop
              for bx in 0 to K-1 loop
                cell_lin := by*K + bx;

                if by = K-1 then
                  -- linha inferior: vem da célula atual
                  new_block(cell_lin) := cell_hist_in;
                else
                  slot_read := mod_pos(cy - (K-1-by), LB_ROWS);
                  new_block(cell_lin) := lb_mem(slot_read)(cx - (K-1-bx));
                end if;

              end loop;
            end loop;

            block_hist_r <= new_block;
            v_out        <= '1';
            block_cnt    <= block_cnt + 1;
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;
