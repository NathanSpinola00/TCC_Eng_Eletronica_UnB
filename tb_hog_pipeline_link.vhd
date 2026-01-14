
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_hog_pipeline_link is
end entity;

architecture sim of tb_hog_pipeline_link is

  constant CLK_PERIOD : time := 10 ns;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal frame_start : std_logic := '0';

  -- DUT input
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal pixel_in : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  -- AXI output
  signal m_axis_tdata  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;

  signal frame_done : std_logic;

  -- =========================
  -- DEBUG COUNTERS
  -- =========================
  signal sent_cnt     : integer := 0;
  signal accepted_cnt : integer := 0;
  signal axi_cnt      : integer := 0;

begin

  ------------------------------------------------------------------
  -- CLOCK
  ------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD/2;

  ------------------------------------------------------------------
  -- DUT
  ------------------------------------------------------------------
  dut : entity work.hog_pipeline_link
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid => in_valid,
      in_ready => in_ready,
      pixel_in => pixel_in,

      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast,

      frame_done => frame_done
    );

  ------------------------------------------------------------------
  -- RESET
  ------------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 50 ns;
    rst <= '0';
    wait;
  end process;

  ------------------------------------------------------------------
  -- INPUT DRIVER (HOLD-VALID + DRAIN LAST PIXEL)
  ------------------------------------------------------------------
  process
    file f_in : text open read_mode is
      "C:\Users\Natan\Documents\Codigos_Python\pixels.txt";
    variable L   : line;
    variable pix : integer;

    variable have_pixel : boolean := false;
  begin
    wait until rst = '0';
    wait until rising_edge(clk);

    -- start frame
    frame_start <= '1';
    wait until rising_edge(clk);
    frame_start <= '0';

    in_valid <= '0';

    -- =========================
    -- SEND ALL PIXELS
    -- =========================
    while not endfile(f_in) loop
      wait until rising_edge(clk);

      -- load new pixel only if none pending
      if not have_pixel then
        readline(f_in, L);
        read(L, pix);
        pixel_in <= to_unsigned(pix, PIXEL_BITS);
        in_valid <= '1';
        have_pixel := true;
        sent_cnt <= sent_cnt + 1;
      end if;

      -- real handshake
      if (in_valid = '1' and in_ready = '1') then
        accepted_cnt <= accepted_cnt + 1;
        in_valid <= '0';
        have_pixel := false;
      end if;
    end loop;

    -- =========================
    -- DRAIN LAST PIXEL (CRITICAL)
    -- =========================
    while have_pixel loop
      wait until rising_edge(clk);
      if (in_valid = '1' and in_ready = '1') then
        accepted_cnt <= accepted_cnt + 1;
        in_valid <= '0';
        have_pixel := false;
      end if;
    end loop;

    in_valid <= '0';
    wait;
  end process;

  ------------------------------------------------------------------
  -- AXI CAPTURE
  ------------------------------------------------------------------
  process
    file f_out : text open write_mode is
      "C:\Users\Natan\Documents\Codigos_Python\hog_out.txt";
    variable L : line;
    variable last_i : integer;
  begin
    wait until rst = '0';

    while true loop
      wait until rising_edge(clk);

      if (m_axis_tvalid = '1' and m_axis_tready = '1') then
        axi_cnt <= axi_cnt + 1;

        if m_axis_tlast = '1' then
          last_i := 1;
        else
          last_i := 0;
        end if;

        write(L, last_i);
        write(L, string'(" "));
        hwrite(L, m_axis_tdata);
        writeline(f_out, L);
      end if;
    end loop;
  end process;

  ------------------------------------------------------------------
  -- FINAL REPORT
  ------------------------------------------------------------------
  process
  begin
    wait until frame_done = '1';

    report "======================================";
    report "FRAME DONE";
    report "sent_cnt     = " & integer'image(sent_cnt);
    report "accepted_cnt = " & integer'image(accepted_cnt);
    report "axi_cnt      = " & integer'image(axi_cnt);
    report "EXPECTED PIXELS = " & integer'image(TOTAL_PIXELS_IN);
    report "EXPECTED AXI    = " & integer'image(NUM_WORDS);
    report "======================================";

    wait;
  end process;

end architecture;

