library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_cell_hist_dump is
end entity;

architecture sim of tb_cell_hist_dump is
  constant CLK_PERIOD : time := 10 ns;

  -- ============================================================
  -- CAMINHOS (Windows)
  -- ============================================================
  constant BASE_DIR : string := "C:\\Users\\Natan\\Documents\\Codigos_Python\\";
  constant PIXELS_PATH : string := BASE_DIR & "pixels.txt";
  constant OUT_PATH    : string := BASE_DIR & "cell_hist_hw.txt";

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal frame_start : std_logic := '0';

  -- pixels
  signal in_valid_px : std_logic := '0';
  signal in_ready_px : std_logic;
  signal pixel_in    : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  -- win_cross_taps -> grad_mag_bin
  signal v_taps : std_logic;
  signal r_taps : std_logic;
  signal p12, p21, p23, p32 : unsigned(PIXEL_BITS-1 downto 0);

  -- grad_mag_bin -> cell_hist
  signal v_gmb   : std_logic;
  signal r_gmb   : std_logic;
  signal mag_out : unsigned(MAG_BITS-1 downto 0);
  signal bin_out : unsigned(3 downto 0);

  -- cell_hist output
  signal v_cell    : std_logic;
  signal r_cell    : std_logic := '1'; -- writer sempre pronto
  signal cell_idx  : unsigned(NUM_CELLS_BITS-1 downto 0);
  signal cell_hist : CellHist_t;

  -- controle TB
  signal done_pixels : std_logic := '0';
  signal done_all    : std_logic := '0';

  -- arquivos
  file f_pixels : text;
  file f_out    : text;

begin
  -- clock
  clk <= not clk after CLK_PERIOD/2;

  -- ============================================================
  -- DUTs
  -- ============================================================
  U_TAPS: entity work.win_cross_taps
    port map (
      clk         => clk,
      rst         => rst,
      frame_start => frame_start,

      in_valid    => in_valid_px,
      in_ready    => in_ready_px,
      pixel_in    => pixel_in,

      out_valid   => v_taps,
      out_ready   => r_taps,

      p12         => p12,
      p21         => p21,
      p23         => p23,
      p32         => p32
    );

  U_GMB: entity work.grad_mag_bin
    port map (
      clk       => clk,
      rst       => rst,

      in_valid  => v_taps,
      in_ready  => r_taps,

      p12       => p12,
      p21       => p21,
      p23       => p23,
      p32       => p32,

      out_valid => v_gmb,
      out_ready => r_gmb,

      mag_out   => mag_out,
      bin_out   => bin_out
    );

  U_CELL: entity work.hog_cell_histogram
    port map (
      clk           => clk,
      rst           => rst,
      frame_start   => frame_start,

      in_valid      => v_gmb,
      in_ready      => r_gmb,
      mag_in        => mag_out,
      bin_in        => bin_out,

      out_valid     => v_cell,
      out_ready     => r_cell,
      cell_idx_out  => cell_idx,
      cell_hist_out => cell_hist
    );

  -- ============================================================
  -- Process 1: Stimulus (lê pixels.txt e injeta PAD_SIZE*PAD_SIZE)
  -- ============================================================
  p_stimulus: process
    variable L : line;
    variable slv8 : std_logic_vector(PIXEL_BITS-1 downto 0);
    variable sent_pixels : integer := 0;
  begin
    -- abre arquivo de entrada
    file_open(f_pixels, PIXELS_PATH, read_mode);

    -- reset
    rst <= '1';
    frame_start <= '0';
    in_valid_px <= '0';
    wait for 10*CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- pulso frame_start
    wait until rising_edge(clk);
    frame_start <= '1';
    wait until rising_edge(clk);
    frame_start <= '0';

    -- envia TOTAL_PIXELS_IN
    sent_pixels := 0;
    while sent_pixels < TOTAL_PIXELS_IN loop
      wait until rising_edge(clk);

      if in_ready_px = '1' then
        if endfile(f_pixels) then
          assert false report "pixels.txt acabou antes de TOTAL_PIXELS_IN" severity failure;
        end if;

        readline(f_pixels, L);
        -- formato: 1 byte HEX por linha (ex: FF)
        hread(L, slv8);
        pixel_in <= unsigned(slv8);

        in_valid_px <= '1';
        sent_pixels := sent_pixels + 1;
      else
        -- segura valid e dados
        in_valid_px <= '1';
      end if;
    end loop;

    -- encerra envio
    wait until rising_edge(clk);
    in_valid_px <= '0';
    pixel_in <= (others => '0');

    file_close(f_pixels);

    done_pixels <= '1';
    report "STIM DONE: sent_pixels=" & integer'image(sent_pixels) severity note;
    wait;
  end process;

  -- ============================================================
  -- Process 2: Writer (captura 1 token por célula e grava cell_hist_hw.txt)
  -- ============================================================
  p_writer: process
    variable Lout : line;
    variable got_cells : integer := 0;
  begin
    -- abre arquivo de saída
    file_open(f_out, OUT_PATH, write_mode);

    -- header
    write(Lout, string'("cell_idx b0 b1 b2 b3 b4 b5 b6 b7 b8"));
    writeline(f_out, Lout);

    -- espera sair do reset e começar frame
    wait until rst = '0';
    wait until frame_start = '0';
    wait until rising_edge(clk);

    got_cells := 0;
    while got_cells < NUM_CELLS_TOTAL loop
      wait until rising_edge(clk);

      if (v_cell = '1') and (r_cell = '1') then
        write(Lout, to_integer(cell_idx));
        for b in 0 to NUM_BINS-1 loop
          write(Lout, string'(" "));
          write(Lout, to_integer(cell_hist(b)));
        end loop;
        writeline(f_out, Lout);

        got_cells := got_cells + 1;
      end if;
    end loop;

    file_close(f_out);

    done_all <= '1';
    report "WRITER DONE: got_cells=" & integer'image(got_cells) &
           " wrote file: " & OUT_PATH severity note;

    wait;
  end process;

end architecture;
