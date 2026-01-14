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

  constant BASE_DIR : string := "C:\Users\Natan\Documents\Codigos_Python\sim_inputs\";
  constant N_FRAMES : integer := 20;

  -- timeout por frame (ciclos) só pra não travar se algo der ruim
  constant MAX_CYCLES_PER_FRAME : integer := 500000;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal frame_start : std_logic := '0';

  -- pixels
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal pixel_in : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  -- AXI out
  signal m_axis_tdata  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;
  signal frame_done    : std_logic;

  -- string "0000".."9999" sem integer'image (evita espaços)
  function to_4digits(n : integer) return string is
    variable s : string(1 to 4);
    variable v : integer := n;
    variable d0, d1, d2, d3 : integer;
  begin
    if v < 0 then v := 0; end if;
    if v > 9999 then v := 9999; end if;

    d0 := (v / 1000) mod 10;
    d1 := (v / 100)  mod 10;
    d2 := (v / 10)   mod 10;
    d3 :=  v         mod 10;

    s(1) := character'val(character'pos('0') + d0);
    s(2) := character'val(character'pos('0') + d1);
    s(3) := character'val(character'pos('0') + d2);
    s(4) := character'val(character'pos('0') + d3);
    return s;
  end function;

begin
  clk <= not clk after CLK_PERIOD/2;

  -- DUT
  U_DUT : entity work.hog_pipeline_link
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

  process
    file f_in  : text;
    file f_out : text;

    variable Lin : line;
    variable Lout: line;

    variable pix_slv : std_logic_vector(PIXEL_BITS-1 downto 0);

    variable frame_id    : integer;
    variable frame_str   : string(1 to 4);

    variable sent_pixels : integer;
    variable word_count  : integer;
    variable cycles      : integer;

    variable holding     : boolean;

  begin
    -- reset
    rst <= '1';
    in_valid <= '0';
    pixel_in <= (others => '0');
    frame_start <= '0';
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    for frame_id in 0 to N_FRAMES-1 loop
      frame_str := to_4digits(frame_id);

      -- abre input e output do frame
      file_open(f_in,  BASE_DIR & "frame_" & frame_str & "_pixels.txt", read_mode);
      file_open(f_out, BASE_DIR & "frame_" & frame_str & "_hog_out.txt",   write_mode);

      -- header
      write(Lout, string'("word_index BIN32 TLAST"));
      writeline(f_out, Lout);

      -- pulso frame_start (igual ao seu TB anterior funcional)
      frame_start <= '1';
      wait until rising_edge(clk);
      frame_start <= '0';

      -- =========================
      -- Envia TOTAL_PIXELS_IN pixels (1156)
      -- =========================
      sent_pixels := 0;
      holding := false;
      in_valid <= '0';
      pixel_in <= (others => '0');

      while sent_pixels < TOTAL_PIXELS_IN loop
        wait until rising_edge(clk);

        if (not holding) then
          if endfile(f_in) then
            assert false report "ERRO: arquivo de pixels acabou antes de TOTAL_PIXELS_IN" severity failure;
          end if;

          readline(f_in, Lin);
          pix_slv := (others => '0');
          read(Lin, pix_slv);              -- lê 8 bits ASCII "01010101"
          pixel_in <= unsigned(pix_slv);
          in_valid <= '1';
          holding := true;
        end if;

        if (in_valid='1') and (in_ready='1') then
          sent_pixels := sent_pixels + 1;
          in_valid <= '0';
          holding := false;
        end if;
      end loop;

      in_valid <= '0';
      pixel_in <= (others => '0');
      file_close(f_in);

      -- =========================
      -- Captura exatamente NUM_WORDS (18) por frame
      -- (ou para antes se frame_done vier)
      -- =========================
      word_count := 0;
      cycles := 0;

      while (cycles < MAX_CYCLES_PER_FRAME) loop
        wait until rising_edge(clk);
        cycles := cycles + 1;

        if (m_axis_tvalid='1') and (m_axis_tready='1') then
          write(Lout, word_count);
          write(Lout, string'(" "));
          write(Lout, m_axis_tdata);       -- BINÁRIO 32 bits: "0101..."
          write(Lout, string'(" "));
          write(Lout, m_axis_tlast);
          writeline(f_out, Lout);

          word_count := word_count + 1;
        end if;

        exit when (word_count = NUM_WORDS);
        exit when (frame_done = '1');
      end loop;

      file_close(f_out);

      report "FRAME " & frame_str &
             " | sent_pixels=" & integer'image(sent_pixels) &
             " | words=" & integer'image(word_count) &
             " | frame_done=" & std_logic'image(frame_done)
             severity note;

      if word_count /= NUM_WORDS then
        report "FRAME " & frame_str & " WARNING: words != NUM_WORDS (esperado=" &
               integer'image(NUM_WORDS) & ")" severity warning;
      end if;

      if cycles >= MAX_CYCLES_PER_FRAME then
        report "FRAME " & frame_str & " TIMEOUT esperando saída" severity warning;
      end if;

      wait for 50 ns;
    end loop;

    report "SIMULACAO FINALIZADA" severity note;
    wait;
  end process;

end architecture;
