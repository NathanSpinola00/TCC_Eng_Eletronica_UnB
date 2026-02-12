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

  type lb_row_t is array (0 to NUM_CELLS_X-1) of CellHist_t;
  type lb_mem_t is array (0 to LB_ROWS-1) of lb_row_t;

  signal lb_mem : lb_mem_t := (others => (others => (others => (others => '0'))));
  signal cur_row : lb_row_t := (others => (others => (others => '0')));

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

    variable write_lb_now : boolean;
    variable cur_row_next : lb_row_t;
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));
        cur_row      <= (others => (others => (others => '0')));

      elsif frame_start='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));
        cur_row      <= (others => (others => (others => '0')));

      else
        if (v_out='1') and (out_ready='1') then
          v_out <= '0';
        end if;

        if (in_valid='1') and (in_ready_i='1') then
          idx_i := to_integer(cell_idx_in);
          cx := idx_i mod NUM_CELLS_X;
          cy := idx_i / NUM_CELLS_X;

          -- prepara linha atual "next"
          cur_row_next := cur_row;
          cur_row_next(cx) := cell_hist_in;

          -- registra linha atual
          cur_row <= cur_row_next;

          -- fim da linha?
          write_lb_now := (LB_ROWS > 0) and (cx = (NUM_CELLS_X-1));

          -- (A) PRIMEIRO monta bloco usando lb_mem ANTIGO (linha cy-1 preservada)
          if (cx >= (K-1)) and (cy >= (K-1)) and
             (to_integer(block_cnt) < TOTAL_BLOCKS) then

            for by in 0 to K-1 loop
              for bx in 0 to K-1 loop
                cell_lin := by*K + bx;

                if by = K-1 then
                  new_block(cell_lin) := cur_row_next(cx - (K-1-bx));
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

          -- (B) DEPOIS, se acabou a linha, empurra cur_row_next para lb_mem
          if write_lb_now then
            row_slot_write := mod_pos(cy, LB_ROWS);
            lb_mem(row_slot_write) <= cur_row_next;
          end if;

          -- limpa cur_row no fim da linha (opcional)
          if cx = (NUM_CELLS_X-1) then
            cur_row <= (others => (others => (others => '0')));
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;
