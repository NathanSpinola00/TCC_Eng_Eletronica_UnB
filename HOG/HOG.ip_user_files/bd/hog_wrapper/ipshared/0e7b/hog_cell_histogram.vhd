library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity hog_cell_histogram is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: 1 token por pixel útil (ROI_SIZE x ROI_SIZE)
    in_valid : in  std_logic;
    in_ready : out std_logic;
    mag_in   : in  unsigned(MAG_BITS-1 downto 0);
    bin_in   : in  unsigned(3 downto 0); -- 0..8

    -- Saída: 1 token por célula
    out_valid     : out std_logic;
    out_ready     : in  std_logic;
    cell_idx_out  : out unsigned(NUM_CELLS_BITS-1 downto 0);
    cell_hist_out : out CellHist_t
  );
end entity;

architecture rtl of hog_cell_histogram is
  -- pixel counters
  signal x : integer range 0 to ROI_SIZE-1 := 0;
  signal y : integer range 0 to ROI_SIZE-1 := 0;

  -- acumuladores internos
  type ucell_t is array(0 to NUM_BINS-1) of unsigned(HIST_BIN_BITS-1 downto 0);
  signal acc : ucell_t := (others => (others => '0'));

  -- 1-deep output buffer (token de célula)
  signal v_out : std_logic := '0';
  signal cell_idx_r : unsigned(NUM_CELLS_BITS-1 downto 0) := (others => '0');
  signal cell_hist_r : CellHist_t := (others => (others => '0'));

  signal in_ready_i : std_logic;
  signal take_in    : std_logic;

  function clamp_bin(b : unsigned(3 downto 0)) return integer is
    variable bi : integer;
  begin
    bi := to_integer(b);
    if bi < 0 then return 0;
    elsif bi > (NUM_BINS-1) then return (NUM_BINS-1);
    else return bi;
    end if;
  end function;

begin
  -- trava entrada enquanto houver célula pendente para o downstream
  in_ready_i <= '1' when (v_out='0') else '0';
  in_ready   <= in_ready_i;
  take_in    <= in_valid and in_ready_i;

  out_valid    <= v_out;
  cell_idx_out <= cell_idx_r;
  cell_hist_out<= cell_hist_r;

  process(clk)
    variable acc_next : ucell_t;
    variable bin_i    : integer;
    variable mag_ext  : unsigned(HIST_BIN_BITS-1 downto 0);

    variable cx, cy   : integer;
    variable cell_idx : integer;
    variable end_cell : boolean;

    variable x_next, y_next : integer;
    variable out_hist : CellHist_t;
  begin
    if rising_edge(clk) then
      if rst='1' then
        x <= 0; y <= 0;
        acc <= (others => (others => '0'));
        v_out <= '0';
        cell_idx_r <= (others => '0');
        cell_hist_r <= (others => (others => '0'));
      else
        if frame_start='1' then
          x <= 0; y <= 0;
          acc <= (others => (others => '0'));
          v_out <= '0';
          cell_idx_r <= (others => '0');
          cell_hist_r <= (others => (others => '0'));
        else
          -- consumo do token de célula
          if (v_out='1') and (out_ready='1') then
            v_out <= '0';
          end if;

          -- processa pixel (somente se não há saída pendente)
          if take_in='1' then
            acc_next := acc;

            bin_i   := clamp_bin(bin_in);
            mag_ext := resize(mag_in, HIST_BIN_BITS);
            acc_next(bin_i) := acc_next(bin_i) + mag_ext;

            end_cell := ((x mod CELL_SIZE) = (CELL_SIZE-1)) and
                        ((y mod CELL_SIZE) = (CELL_SIZE-1));

            -- próximo pixel
            if x = ROI_SIZE-1 then
              x_next := 0;
              if y = ROI_SIZE-1 then y_next := 0;
              else                   y_next := y + 1;
              end if;
            else
              x_next := x + 1;
              y_next := y;
            end if;

            x <= x_next;
            y <= y_next;

            if end_cell then
              cx := x / CELL_SIZE;
              cy := y / CELL_SIZE;
              cell_idx := cy * NUM_CELLS_X + cx;

              -- converte ucell_t -> CellHist_t
              for i in 0 to NUM_BINS-1 loop
                out_hist(i) := resize(acc_next(i), HIST_BIN_BITS);
              end loop;

              cell_idx_r  <= to_unsigned(cell_idx, NUM_CELLS_BITS);
              cell_hist_r <= out_hist;
              v_out       <= '1';

              acc <= (others => (others => '0'));
            else
              acc <= acc_next;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
