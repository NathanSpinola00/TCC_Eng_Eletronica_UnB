library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_valida_hog is
end entity;

architecture sim of tb_valida_hog is
  constant CLK_PERIOD : time := 10 ns;

  constant BASE_DIR : string :=
    "C:\Users\Natan\Documents\Codigos_Python\sim_inputs\";

  -- Agora vamos varrer ROIs geradas pelo script:
  -- frames: 0..N_FRAMES-1
  -- rois:   0..N_ROIS-1  (roi_000 = GT, roi_001..roi_005 = offsets)
  constant N_FRAMES : integer := 10;
  constant N_ROIS   : integer := 6;

  -- timeout por ROI (antes era por frame)
  constant MAX_CYCLES_PER_ROI : integer := 500000;

  -- =========================
  -- Backpressure determinístico
  -- =========================
  constant READY_ON_CYCLES  : integer := 7;
  constant READY_OFF_CYCLES : integer := 3;

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

  -- =========================
  -- util: inteiro -> "0000"
  -- =========================
  function to_4digits(n : integer) return string is
    variable s : string(1 to 4);
    variable v : integer := n;
  begin
    if v < 0 then v := 0; end if;
    if v > 9999 then v := 9999; end if;

    s(1) := character'val(character'pos('0') + ((v/1000) mod 10));
    s(2) := character'val(character'pos('0') + ((v/100)  mod 10));
    s(3) := character'val(character'pos('0') + ((v/10)   mod 10));
    s(4) := character'val(character'pos('0') + ( v        mod 10));
    return s;
  end function;

  -- =========================
  -- util: inteiro -> "000"  (ROI id)
  -- =========================
  function to_3digits(n : integer) return string is
    variable s : string(1 to 3);
    variable v : integer := n;
  begin
    if v < 0 then v := 0; end if;
    if v > 999 then v := 999; end if;

    s(1) := character'val(character'pos('0') + ((v/100) mod 10));
    s(2) := character'val(character'pos('0') + ((v/10)  mod 10));
    s(3) := character'val(character'pos('0') + ( v       mod 10));
    return s;
  end function;

begin
  clk <= not clk after CLK_PERIOD/2;

  -- =========================
  -- DUT
  -- =========================
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

  -- ============================================================
  -- GERADOR DE BACKPRESSURE (único driver de m_axis_tready)
  -- ============================================================
  process(clk)
    variable ph : integer := 0;
    constant PERIOD_LEN : integer := READY_ON_CYCLES + READY_OFF_CYCLES;
  begin
    if rising_edge(clk) then
      if rst='1' or frame_start='1' then
        ph := 0;
        m_axis_tready <= '1';
      else
        if ph = PERIOD_LEN-1 then
          ph := 0;
        else
          ph := ph + 1;
        end if;

        if ph < READY_ON_CYCLES then
          m_axis_tready <= '1';
        else
          m_axis_tready <= '0';
        end if;
      end if;
    end if;
  end process;

  -- ============================================================
  -- PROCESS PRINCIPAL (varre frame + ROI)
  --   Lê:  frame_xxxx_roi_yyy_pixels.txt
  --   Escreve: frame_xxxx_roi_yyy_hog_out.txt
  -- ============================================================
  process
    file f_in  : text;
    file f_out : text;

    variable Lin  : line;
    variable Lout : line;

    variable pix_slv : std_logic_vector(PIXEL_BITS-1 downto 0);

    variable frame_id  : integer;
    variable roi_id    : integer;
    variable frame_str : string(1 to 4);
    variable roi_str   : string(1 to 3);

    variable sent_pixels : integer;
    variable word_count  : integer;
    variable cycles      : integer;

    variable holding     : boolean;

    variable in_name  : string(1 to 512);
    variable out_name : string(1 to 512);
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

      for roi_id in 0 to N_ROIS-1 loop
        roi_str := to_3digits(roi_id);

        -- monta nomes
        -- entrada: frame_0000_roi_000_pixels.txt
        -- saída:   frame_0000_roi_000_hog_out.txt
        in_name  := (others => ' ');
        out_name := (others => ' ');

        -- (string concatenation direto no file_open é ok aqui)
        file_open(
          f_in,
          BASE_DIR & "frame_" & frame_str & "_roi_" & roi_str & "_pixels.txt",
          read_mode
        );

        file_open(
          f_out,
          BASE_DIR & "frame_" & frame_str & "_roi_" & roi_str & "_hog_out.txt",
          write_mode
        );

        -- header
        write(Lout, string'("word_index BIN32 TLAST"));
        writeline(f_out, Lout);

        -- frame_start por ROI (reinicia pipeline/contadores)
        frame_start <= '1';
        wait until rising_edge(clk);
        frame_start <= '0';

        sent_pixels := 0;
        word_count  := 0;
        cycles      := 0;
        holding     := false;

        in_valid <= '0';
        pixel_in <= (others => '0');

        while (cycles < MAX_CYCLES_PER_ROI) loop
          wait until rising_edge(clk);
          cycles := cycles + 1;

          -- =========================
          -- AXI CAPTURE (só no handshake)
          -- =========================
          if (m_axis_tvalid='1') and (m_axis_tready='1') then
            write(Lout, word_count);
            write(Lout, string'(" "));
            write(Lout, m_axis_tdata); -- BIN32
            write(Lout, string'(" "));
            write(Lout, m_axis_tlast);
            writeline(f_out, Lout);
            word_count := word_count + 1;
          end if;

          -- =========================
          -- PIXELS (1156)
          -- =========================
          if sent_pixels < TOTAL_PIXELS_IN then
            if not holding then
              if endfile(f_in) then
                assert false
                  report "ERRO: arquivo acabou antes de TOTAL_PIXELS_IN (frame=" &
                         frame_str & " roi=" & roi_str & ")"
                  severity failure;
              end if;

              readline(f_in, Lin);
              pix_slv := (others => '0');
              read(Lin, pix_slv);            -- "01010101"
              pixel_in <= unsigned(pix_slv);
              in_valid <= '1';
              holding := true;
            end if;

            if (in_valid='1') and (in_ready='1') then
              sent_pixels := sent_pixels + 1;
              in_valid <= '0';
              holding := false;
            end if;
          else
            in_valid <= '0';
            pixel_in <= (others => '0');
          end if;

          -- parada: 18 words
          exit when (word_count = NUM_WORDS);
        end loop;

        file_close(f_in);
        file_close(f_out);

        report "FRAME " & frame_str & " ROI " & roi_str &
               " | sent_pixels=" & integer'image(sent_pixels) &
               " | words=" & integer'image(word_count) &
               " | frame_done=" & std_logic'image(frame_done)
               severity note;

        if sent_pixels /= TOTAL_PIXELS_IN then
          report "WARNING: sent_pixels != TOTAL_PIXELS_IN (frame=" & frame_str &
                 " roi=" & roi_str & ")" severity warning;
        end if;

        if word_count /= NUM_WORDS then
          report "WARNING: words != NUM_WORDS (frame=" & frame_str &
                 " roi=" & roi_str & ")" severity warning;
        end if;

        if cycles >= MAX_CYCLES_PER_ROI then
          report "WARNING: TIMEOUT (frame=" & frame_str &
                 " roi=" & roi_str & ")" severity warning;
        end if;

        -- gap entre ROIs
        wait for 50 ns;
      end loop;
    end loop;

    report "SIMULACAO FINALIZADA" severity note;
    wait;
  end process;

end architecture;
